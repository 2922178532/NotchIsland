import SwiftUI

/// Le cœur visuel de JuiceFlow : le flux d'énergie en direct
/// entre le chargeur, le Mac et la batterie.
///
///   Chargeur ──▶ Système ◀── Batterie   (décharge)
///   Chargeur ──▶ Système ──▶ Batterie   (charge)
struct PowerFlowCard: View {
    let snapshot: BatterySnapshot

    var body: some View {
        HStack(spacing: 2) {
            node(
                icon: "powerplug.fill",
                label: "充电器",
                value: snapshot.isExternalConnected
                    ? snapshot.adapterWatts.map { String(format: "%.1f W", $0) } ?? "—"
                    : "—",
                tint: .blue,
                active: snapshot.isExternalConnected
            )

            arrow(
                "arrow.forward",
                active: snapshot.isExternalConnected && (snapshot.adapterWatts ?? 0) > 0.5,
                color: .blue
            )

            node(
                icon: "laptopcomputer",
                label: "系统",
                value: snapshot.systemWatts.map { String(format: "%.1f W", $0) } ?? "—",
                tint: .primary,
                active: true
            )

            arrow(
                snapshot.watts < -0.5 ? "arrow.backward" : "arrow.forward",
                active: abs(snapshot.watts) > 0.5,
                color: snapshot.wattsColor
            )

            node(
                icon: snapshot.batterySymbol,
                label: "电池",
                value: snapshot.wattsLabel,
                tint: snapshot.wattsColor,
                active: true
            )
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .card()
    }

    private func node(icon: String, label: String, value: String,
                      tint: Color, active: Bool) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(tint)
                .frame(height: 20)
            Text(value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .opacity(active ? 1 : 0.35)
    }

    private func arrow(_ symbol: String, active: Bool, color: Color) -> some View {
        Image(systemName: active ? symbol : "minus")
            .font(.footnote.weight(.bold))
            .foregroundStyle(active ? color : Color.primary.opacity(0.15))
            .frame(width: 18)
    }
}
