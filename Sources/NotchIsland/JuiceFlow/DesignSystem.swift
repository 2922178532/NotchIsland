import SwiftUI

// MARK: - Langage visuel commun

extension BatterySnapshot {
    /// Couleur du niveau de charge (jauge, teinte d'ambiance).
    var levelColor: Color {
        if percentage <= 10 { .red } else if percentage <= 20 { .orange } else { .green }
    }

    /// Couleur du flux batterie : vert = charge, orange/rouge = décharge.
    var wattsColor: Color {
        if watts > 0.5 { .green } else if watts < -0.5 { percentage <= 20 ? .red : .orange } else { .secondary }
    }

    var stateShortLabel: String {
        switch state {
        case .charging: "充电中"
        case .discharging: "用电池"
        case .full: "已充满"
        case .pluggedNotCharging: "已暂停"
        }
    }

    var wattsLabel: String {
        abs(watts) < 0.05 ? "0 W" : String(format: "%+.1f W", watts)
    }

    var batterySymbol: String {
        if state == .charging { return "battery.100percent.bolt" }
        let levels = [0, 25, 50, 75, 100]
        let nearest = levels.min { abs($0 - percentage) < abs($1 - percentage) } ?? 100
        return "battery.\(nearest)percent"
    }

    /// Valeur principale de la carte « temps restant » : « 3 h 24 », « ∞ », « … ».
    var timeRemainingValue: String {
        guard let minutes = timeRemainingMinutes else {
            return state == .full ? "∞" : "…"
        }
        return "\(minutes / 60) h \(String(format: "%02d", minutes % 60))"
    }

    var timeRemainingCaption: String {
        guard timeRemainingMinutes != nil else {
            return state == .full ? "已充满" : "正在计算"
        }
        return state == .charging ? "后充满" : "预估续航"
    }
}

// MARK: - Modèle d'autonomie

extension BatterySnapshot {
    /// Énergie restante estimée : mAh restants × tension instantanée.
    var remainingEnergyWh: Double {
        Double(rawCurrentCapacity) / 1000 * voltage
    }

    /// Drain de référence en watts : le drain batterie réel en décharge,
    /// sinon la consommation système (hypothèse « si débranché maintenant »).
    var referenceDrainWatts: Double? {
        if state == .discharging, watts < -0.3 { return -watts }
        if let systemWatts, systemWatts > 0.5 { return systemWatts }
        return nil
    }

    /// Autonomie estimée au rythme de consommation actuel.
    var estimatedAutonomyHours: Double? {
        guard let drain = referenceDrainWatts, remainingEnergyWh > 0 else { return nil }
        return remainingEnergyWh / drain
    }

    /// Minutes d'autonomie gagnées si on libère `freeingWatts` de consommation
    /// (ex : en quittant une app). Nil si non calculable.
    func autonomyGainMinutes(freeingWatts: Double) -> Double? {
        guard freeingWatts > 0.05,
              let drain = referenceDrainWatts,
              drain - freeingWatts > 0.3,
              remainingEnergyWh > 0 else { return nil }
        let now = remainingEnergyWh / drain
        let without = remainingEnergyWh / (drain - freeingWatts)
        return (without - now) * 60
    }
}

enum TimeFormat {
    static func hours(_ hours: Double) -> String {
        guard hours.isFinite, hours > 0 else { return "—" }
        guard hours < 24 else { return "> 24 小时" }
        var minutes = Int(hours * 60)
        // Arrondi aux 5 min au-delà d'une demi-heure : une estimation n'a pas
        // à afficher une fausse précision qui bouge sans arrêt.
        if minutes > 30 { minutes = (minutes + 2) / 5 * 5 }
        guard minutes >= 60 else { return "\(minutes) 分钟" }
        return "\(minutes / 60) 小时 \(String(format: "%02d", minutes % 60)) 分"
    }

    static func gain(_ minutes: Double) -> String {
        let rounded = Int(minutes.rounded())
        guard rounded >= 60 else { return "+\(max(rounded, 1)) 分钟" }
        return "+\(rounded / 60) 小时 \(String(format: "%02d", rounded % 60)) 分"
    }
}

// MARK: - Affichage des apps du classement

extension AppPower {
    /// Valeur affichable : watts réels en précision, score en estimation.
    var displayValue: String {
        if let watts {
            return watts < 1
                ? String(format: "%.0f mW", watts * 1000)
                : String(format: "%.1f W", watts)
        }
        return String(format: energyImpact < 10 ? "%.1f" : "%.0f", energyImpact)
    }

    var displayColor: Color {
        if let watts {
            if watts < 0.5 { return .green }
            return watts < 2.5 ? .orange : .red
        }
        if energyImpact < 10 { return .green }
        return energyImpact < 60 ? .orange : .red
    }
}

// MARK: - Glyphes des processus sans icône

/// Symbole + couleur pour les daemons et processus système : chaque famille
/// de service a son identité au lieu d'un engrenage générique répété.
enum DaemonGlyph {
    static func forApp(_ app: AppPower) -> (symbol: String, color: Color) {
        forName(app.name)
    }

    static func forName(_ name: String) -> (symbol: String, color: Color) {
        if name.contains("WindowServer") || name.contains("显示") || name.contains("Affichage") { return ("display", .blue) }
        if name.contains("内核") || name.contains("Noyau") || name == "kernel_task" { return ("cpu", .purple) }
        if name.localizedCaseInsensitiveContains("spotlight") || name.hasPrefix("mds") {
            return ("magnifyingglass", .indigo)
        }
        if name.contains("iCloud") || name == "bird" { return ("icloud.fill", .cyan) }
        if name.contains("Time Machine") { return ("clock.arrow.circlepath", .teal) }
        if name.contains("Audio") || name == "coreaudiod" { return ("speaker.wave.2.fill", .pink) }
        if name.contains("安全") || name.contains("Sécurité") || ["trustd", "tccd", "syspolicyd"].contains(name) {
            return ("lock.shield.fill", .green)
        }
        if name.contains("Bluetooth") || name.contains("蓝牙") { return ("dot.radiowaves.left.and.right", .blue) }
        if name.contains("Wi-Fi") || name.contains("无线") || name == "airportd" { return ("wifi", .blue) }
        if name.contains("分析") || name.contains("Analyse") || name.contains("Photos") || name.contains("照片") { return ("photo.on.rectangle", .orange) }
        if name.contains("日志") || name.contains("Journaux") || name == "logd" { return ("doc.text", .gray) }
        if name.contains("Virtual") || ["limactl", "colima", "docker", "qemu"]
            .contains(where: { name.localizedCaseInsensitiveContains($0) }) {
            return ("shippingbox.fill", .brown)
        }
        return ("gearshape.fill", .gray)
    }
}

// MARK: - Style de carte partagé

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.quinary)
            )
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}
