import Darwin
import Foundation

/// Échantillonnage libproc de tous les processus visibles, sans privilèges.
/// Temps CPU (comptabilisé en continu par l'ordonnanceur) et wakeups : les
/// deltas entre deux échantillons alimentent le score d'impact énergétique.
/// Note : `ri_billed_energy` a été testé et abandonné — le compteur n'est
/// mis à jour qu'à de rares événements de facturation sur macOS (~3 mW
/// apparents pour tout le système). Les vraies mesures viendront de
/// powermetrics à l'étape 4.
enum ProcessSampler {
    struct Usage: Sendable {
        var cpuNS: UInt64 = 0
        var idleWakeups: UInt64 = 0
    }

    struct Snapshot: Sendable {
        var instant: ContinuousClock.Instant
        var usage: [pid_t: Usage]
    }

    static func snapshot() -> Snapshot {
        var pids = [pid_t](repeating: 0, count: 8192)
        let count = Int(proc_listallpids(&pids, Int32(8192 * MemoryLayout<pid_t>.size)))
        var usage: [pid_t: Usage] = [:]
        usage.reserveCapacity(max(count, 0))

        for pid in pids.prefix(max(count, 0)) where pid > 0 {
            guard let info = rusage(pid) else { continue }
            usage[pid] = Usage(
                cpuNS: machToNS(info.ri_user_time &+ info.ri_system_time),
                idleWakeups: info.ri_pkg_idle_wkups
            )
        }
        return Snapshot(instant: .now, usage: usage)
    }

    /// PID « responsable » : l'application à qui macOS impute ce processus
    /// (les helpers Chrome/Slack/VS Code remontent à leur app). C'est le même
    /// regroupement que le Moniteur d'activité. API privée mais stable,
    /// résolue dynamiquement avec repli sur le PID lui-même.
    static func responsiblePid(_ pid: pid_t) -> pid_t {
        guard let fn = responsibleFn else { return pid }
        let responsible = fn(pid)
        return responsible > 0 ? responsible : pid
    }

    static func name(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 64)
        guard proc_name(pid, &buffer, 64) > 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    // MARK: - Privé

    private static func rusage(_ pid: pid_t) -> rusage_info_current? {
        var info = rusage_info_current()
        let ok = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0) == 0
            }
        }
        return ok ? info : nil
    }

    private static let timebase: mach_timebase_info_data_t = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return tb
    }()

    private static func machToNS(_ ticks: UInt64) -> UInt64 {
        ticks * UInt64(timebase.numer) / UInt64(timebase.denom)
    }

    private static let responsibleFn: (@convention(c) (pid_t) -> pid_t)? = {
        guard let sym = dlsym(dlopen(nil, RTLD_NOW), "responsibility_get_pid_responsible_for_pid") else {
            return nil
        }
        return unsafeBitCast(sym, to: (@convention(c) (pid_t) -> pid_t).self)
    }()
}
