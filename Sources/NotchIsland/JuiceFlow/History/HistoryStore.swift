import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Persistance SQLite minimaliste — SwiftData exige un plugin de macros
/// absent des Command Line Tools, et nos besoins tiennent en deux tables.
/// Base : ~/Library/Application Support/JuiceFlow/history.sqlite (mode WAL).
final class HistoryStore {
    private let db: OpaquePointer

    init?() {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JuiceFlow", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("history.sqlite").path

        var handle: OpaquePointer?
        guard sqlite3_open(path, &handle) == SQLITE_OK, let handle else {
            sqlite3_close(handle)
            return nil
        }
        db = handle
        execute("PRAGMA journal_mode = WAL")
        execute("""
        CREATE TABLE IF NOT EXISTS battery_samples(
            ts REAL PRIMARY KEY,
            percentage INTEGER NOT NULL,
            battery_watts REAL NOT NULL,
            system_watts REAL,
            plugged INTEGER NOT NULL)
        """)
        execute("""
        CREATE TABLE IF NOT EXISTS app_energy(
            hour_start REAL NOT NULL,
            app_name TEXT NOT NULL,
            bundle_id TEXT,
            energy_mwh REAL NOT NULL,
            peak_mw REAL NOT NULL,
            PRIMARY KEY(hour_start, app_name))
        """)
    }

    deinit { sqlite3_close(db) }

    // MARK: - Écriture

    func insertSample(timestamp: Date, percentage: Int, batteryWatts: Double,
                      systemWatts: Double?, plugged: Bool) {
        withStatement("INSERT OR REPLACE INTO battery_samples VALUES (?,?,?,?,?)") { statement in
            sqlite3_bind_double(statement, 1, timestamp.timeIntervalSince1970)
            sqlite3_bind_int(statement, 2, Int32(percentage))
            sqlite3_bind_double(statement, 3, batteryWatts)
            if let systemWatts {
                sqlite3_bind_double(statement, 4, systemWatts)
            } else {
                sqlite3_bind_null(statement, 4)
            }
            sqlite3_bind_int(statement, 5, plugged ? 1 : 0)
            sqlite3_step(statement)
        }
    }

    func addAppEnergy(hourStart: Date, name: String, bundleID: String?,
                      incrementMWh: Double, currentMilliwatts: Double) {
        let sql = """
        INSERT INTO app_energy VALUES (?,?,?,?,?)
        ON CONFLICT(hour_start, app_name) DO UPDATE SET
            energy_mwh = energy_mwh + excluded.energy_mwh,
            peak_mw = MAX(peak_mw, excluded.peak_mw)
        """
        withStatement(sql) { statement in
            sqlite3_bind_double(statement, 1, hourStart.timeIntervalSince1970)
            sqlite3_bind_text(statement, 2, name, -1, SQLITE_TRANSIENT)
            if let bundleID {
                sqlite3_bind_text(statement, 3, bundleID, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(statement, 3)
            }
            sqlite3_bind_double(statement, 4, incrementMWh)
            sqlite3_bind_double(statement, 5, currentMilliwatts)
            sqlite3_step(statement)
        }
    }

    func prune(samplesBefore: Date, bucketsBefore: Date) {
        withStatement("DELETE FROM battery_samples WHERE ts < ?") { statement in
            sqlite3_bind_double(statement, 1, samplesBefore.timeIntervalSince1970)
            sqlite3_step(statement)
        }
        withStatement("DELETE FROM app_energy WHERE hour_start < ?") { statement in
            sqlite3_bind_double(statement, 1, bucketsBefore.timeIntervalSince1970)
            sqlite3_step(statement)
        }
    }

    // MARK: - Lecture

    func curve(since: Date) -> [CurvePoint] {
        var points: [CurvePoint] = []
        withStatement("SELECT ts, percentage, plugged FROM battery_samples WHERE ts >= ? ORDER BY ts") { statement in
            sqlite3_bind_double(statement, 1, since.timeIntervalSince1970)
            while sqlite3_step(statement) == SQLITE_ROW {
                points.append(CurvePoint(
                    timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 0)),
                    percentage: Int(sqlite3_column_int(statement, 1)),
                    isExternalConnected: sqlite3_column_int(statement, 2) == 1
                ))
            }
        }
        return points
    }

    func topApps(since: Date, limit: Int) -> [AppDayTotal] {
        var result: [AppDayTotal] = []
        let sql = """
        SELECT app_name, MAX(bundle_id), SUM(energy_mwh) AS total
        FROM app_energy WHERE hour_start >= ?
        GROUP BY app_name ORDER BY total DESC LIMIT ?
        """
        withStatement(sql) { statement in
            sqlite3_bind_double(statement, 1, since.timeIntervalSince1970)
            sqlite3_bind_int(statement, 2, Int32(limit))
            while sqlite3_step(statement) == SQLITE_ROW {
                result.append(AppDayTotal(
                    name: text(statement, column: 0) ?? "?",
                    bundleID: text(statement, column: 1),
                    energyMWh: sqlite3_column_double(statement, 2)
                ))
            }
        }
        return result
    }

    /// Énergie système consommée entre deux instants, en Wh.
    func energyWh(since: Date, until: Date) -> Double {
        var energy = 0.0
        withStatement("SELECT COALESCE(SUM(system_watts), 0) / 60 FROM battery_samples WHERE ts >= ? AND ts < ?") { statement in
            sqlite3_bind_double(statement, 1, since.timeIntervalSince1970)
            sqlite3_bind_double(statement, 2, until.timeIntervalSince1970)
            if sqlite3_step(statement) == SQLITE_ROW {
                energy = sqlite3_column_double(statement, 0)
            }
        }
        return energy
    }

    func daySummary(since: Date) -> DaySummary {
        var summary = DaySummary(minutesOnBattery: 0, energyWh: 0)
        let sql = """
        SELECT COUNT(CASE WHEN plugged = 0 THEN 1 END),
               COALESCE(SUM(system_watts), 0) / 60
        FROM battery_samples WHERE ts >= ?
        """
        withStatement(sql) { statement in
            sqlite3_bind_double(statement, 1, since.timeIntervalSince1970)
            if sqlite3_step(statement) == SQLITE_ROW {
                summary.minutesOnBattery = Int(sqlite3_column_int(statement, 0))
                summary.energyWh = sqlite3_column_double(statement, 1)
            }
        }
        return summary
    }

    // MARK: - Plomberie

    private func text(_ statement: OpaquePointer, column: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, column) else { return nil }
        return String(decodingCString: pointer, as: UTF8.self)
    }

    private func withStatement(_ sql: String, _ body: (OpaquePointer) -> Void) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return }
        defer { sqlite3_finalize(statement) }
        body(statement)
    }

    private func execute(_ sql: String) {
        sqlite3_exec(db, sql, nil, nil, nil)
    }
}
