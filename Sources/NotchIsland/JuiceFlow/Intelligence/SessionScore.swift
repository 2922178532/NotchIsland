import SwiftUI

/// Santé énergétique de la session en cours, sur 100 — avec le détail des
/// pénalités pour que le score soit toujours explicable.
struct SessionScore {
    let value: Int
    let factors: [String]

    var color: Color {
        if value >= 80 { .green } else if value >= 50 { .orange } else { .red }
    }

    @MainActor
    static func compute(battery: BatteryService, processes: ProcessService) -> SessionScore {
        var score = 100.0
        var factors: [String] = []

        // Consommation globale : ne juge que sur batterie — branché, c'est le
        // chargeur qui paie, une grosse charge de travail n'est pas une faute.
        if battery.snapshot.state == .discharging,
           let drain = battery.smoothedDrainWatts, drain > 7 {
            let penalty = min((drain - 7) * 4, 40)
            score -= penalty
            factors.append("−\(Int(penalty)) · 功耗偏高（\(String(format: "%.1f", drain)) W）")
        }

        for app in processes.apps.filter(\.isRunaway).prefix(2) {
            score -= 12
            factors.append("−12 · \(app.name) 功耗异常")
        }

        for app in processes.apps.filter({ $0.isBackgroundActive && !$0.isRunaway }).prefix(3) {
            score -= 6
            factors.append("−6 · \(app.name) 后台活跃")
        }

        if battery.snapshot.temperature >= 40 {
            score -= 8
            factors.append("−8 · 温度偏高")
        }

        return SessionScore(value: max(Int(score.rounded()), 0), factors: factors)
    }
}
