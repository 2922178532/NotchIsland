import SwiftUI

/// Ligne du classement : icône, nom, barre proportionnelle, puissance.
struct AppEnergyRow: View {
    let app: AppPower
    let maxImpact: Double
    var isSelected = false
    @State private var isHovering = false

    private var color: Color { app.displayColor }

    var body: some View {
        HStack(spacing: 10) {
            iconView
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(app.name)
                        .font(.callout)
                        .lineLimit(1)
                    if app.isRunaway {
                        badge("flame.fill", .red, help: "功耗急剧上升")
                    }
                    if app.isBackgroundActive {
                        badge("moon.fill", .indigo, help: "后台仍在耗电")
                    }
                }
                if app.processCount > 1 {
                    Text("\(app.processCount) 个进程")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 12)

            bar

            Text(app.displayValue)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .frame(width: 56, alignment: .trailing)
        }
        // Hauteur constante quelle que soit la présence du sous-titre :
        // évite que la liste change de taille à chaque rafraîchissement.
        .frame(height: 34)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected
                      ? Color.primary.opacity(0.08)
                      : isHovering ? Color.primary.opacity(0.05) : .clear)
        )
        .overlay(alignment: .leading) {
            // Liseré accent : sélection neutre et lisible quel que soit le
            // thème, sans teinter toute la ligne.
            if isSelected {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 5)
            }
        }
        .padding(.horizontal, -8)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    /// Pastille pleine : glyphe blanc sur cercle coloré — visible au premier
    /// coup d'œil, contrairement aux petites icônes teintées.
    private func badge(_ symbol: String, _ color: Color, help: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 8.5, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 15, height: 15)
            .background(Circle().fill(color.gradient))
            .help(help)
    }

    @ViewBuilder
    private var iconView: some View {
        if let icon = app.icon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
        } else {
            let glyph = DaemonGlyph.forApp(app)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(glyph.color.opacity(0.16))
                .overlay {
                    Image(systemName: glyph.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(glyph.color)
                }
        }
    }

    private var bar: some View {
        Capsule()
            .fill(.quinary)
            .frame(width: 84, height: 6)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(color.gradient)
                    .frame(width: max(84 * app.energyImpact / max(maxImpact, 0.001), 5), height: 6)
            }
    }

}
