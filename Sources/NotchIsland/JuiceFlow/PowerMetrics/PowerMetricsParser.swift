import Foundation

/// Une tâche telle que rapportée par `powermetrics --samplers tasks`.
struct PMTask: Sendable, Equatable {
    var pid: pid_t
    var name: String
    /// Score « impact énergétique » officiel d'Apple (celui du Moniteur
    /// d'activité), pondéré CPU P/E, GPU et wakeups.
    var energyImpact: Double
    var cpuMsPerS: Double
    var gpuMsPerS: Double
}

/// Parseur pur des documents plist émis par powermetrics. Défensif sur les
/// deux formes rencontrées selon les versions de macOS : tableau `coalitions`
/// (avec sous-tableau `tasks`) ou tableau `tasks` à plat.
enum PowerMetricsParser {
    static func tasks(from data: Data) -> [PMTask] {
        guard let root = (try? PropertyListSerialization.propertyList(from: data, format: nil))
            as? [String: Any] else { return [] }

        var result: [PMTask] = []
        if let coalitions = root["coalitions"] as? [[String: Any]] {
            for coalition in coalitions {
                if let subTasks = coalition["tasks"] as? [[String: Any]] {
                    result.append(contentsOf: subTasks.compactMap(task(from:)))
                } else if let task = task(from: coalition) {
                    result.append(task)
                }
            }
        }
        if let flatTasks = root["tasks"] as? [[String: Any]] {
            result.append(contentsOf: flatTasks.compactMap(task(from:)))
        }
        return result
    }

    /// Découpe un flux continu powermetrics en documents plist complets.
    /// powermetrics sépare les échantillons par un octet NUL ; on garde le
    /// reliquat en tampon pour le prochain appel.
    static func splitStream(buffer: inout Data) -> [Data] {
        var documents: [Data] = []
        while let nulIndex = buffer.firstIndex(of: 0) {
            let chunk = buffer.subdata(in: buffer.startIndex..<nulIndex)
            buffer.removeSubrange(buffer.startIndex...nulIndex)
            if !chunk.isEmpty { documents.append(chunk) }
        }
        return documents
    }

    private static func task(from dict: [String: Any]) -> PMTask? {
        guard let pid = (dict["pid"] as? NSNumber)?.int32Value,
              pid >= 0,  // exclut l'agrégat ALL_TASKS (pid -2)
              let name = dict["name"] as? String else { return nil }
        return PMTask(
            pid: pid,
            name: name,
            // Vérifié sur ce Mac : energy_impact_per_s est en milliwatts
            // (somme des tâches ≈ cpu_power du sampler cpu_power).
            energyImpact: number(dict["energy_impact_per_s"]) ?? number(dict["energy_impact"]) ?? 0,
            cpuMsPerS: number(dict["cputime_ms_per_s"]) ?? 0,
            gpuMsPerS: number(dict["gputime_ms_per_s"]) ?? 0
        )
    }

    private static func number(_ any: Any?) -> Double? {
        (any as? NSNumber)?.doubleValue
    }
}
