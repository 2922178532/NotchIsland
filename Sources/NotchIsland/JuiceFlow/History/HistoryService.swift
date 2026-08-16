import Foundation

/// Enregistre l'historique (un échantillon batterie par minute, énergie par
/// app en paniers horaires) et sert les requêtes des vues Historique.
@MainActor
@Observable
final class HistoryService {
    private(set) var isAvailable = false

    @ObservationIgnored private let battery: BatteryService
    @ObservationIgnored private let processes: ProcessService
    @ObservationIgnored private let store: HistoryStore?
    @ObservationIgnored private var recordTask: Task<Void, Never>?

    init(battery: BatteryService, processes: ProcessService) {
        self.battery = battery
        self.processes = processes
        store = HistoryStore()
        isAvailable = store != nil

        store?.prune(
            samplesBefore: .now.addingTimeInterval(-30 * 86_400),
            bucketsBefore: .now.addingTimeInterval(-90 * 86_400)
        )
        recordTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60), tolerance: .seconds(5))
                self?.recordTick()
            }
        }
    }

    // MARK: - Enregistrement (1 tick par minute)

    private func recordTick() {
        guard let store, battery.hasBattery else { return }
        let snap = battery.snapshot
        store.insertSample(
            timestamp: .now,
            percentage: snap.percentage,
            batteryWatts: snap.watts,
            systemWatts: snap.systemWatts,
            plugged: snap.isExternalConnected
        )

        // Énergie par app : uniquement en précision (les scores d'estimation
        // ne sont pas des milliwatts). 1 min à X mW = X/60 mWh.
        guard processes.source == .precision,
              let hourStart = Calendar.current.dateInterval(of: .hour, for: .now)?.start else { return }
        for app in processes.apps.prefix(20) where app.energyImpact >= 5 {
            store.addAppEnergy(
                hourStart: hourStart,
                name: app.name,
                bundleID: app.bundleID,
                incrementMWh: app.energyImpact / 60,
                currentMilliwatts: app.energyImpact
            )
        }
    }

    // MARK: - Requêtes

    func curve(hoursBack: Int) -> [CurvePoint] {
        store?.curve(since: .now.addingTimeInterval(-Double(hoursBack) * 3600)) ?? []
    }

    func topAppsToday(limit: Int) -> [AppDayTotal] {
        store?.topApps(since: Calendar.current.startOfDay(for: .now), limit: limit) ?? []
    }

    func daySummary() -> DaySummary {
        store?.daySummary(since: Calendar.current.startOfDay(for: .now))
            ?? DaySummary(minutesOnBattery: 0, energyWh: 0)
    }

    /// Variation vs hier à la même heure, en % (nil si pas assez de données).
    func energyDeltaVersusYesterday() -> Double? {
        guard let store else { return nil }
        let midnight = Calendar.current.startOfDay(for: .now)
        let elapsed = Date.now.timeIntervalSince(midnight)
        let yesterdayStart = midnight.addingTimeInterval(-86_400)
        let yesterday = store.energyWh(since: yesterdayStart,
                                       until: yesterdayStart.addingTimeInterval(elapsed))
        let today = store.energyWh(since: midnight, until: .now)
        guard yesterday > 0.3, today > 0.1 else { return nil }
        return (today - yesterday) / yesterday * 100
    }
}
