import SwiftUI

/// Pastille de statistique compacte : icône teintée, valeur, libellé.
struct StatChip: View {
    let icon: String
    let color: Color
    let value: String
    let label: String
    /// false : rangée nue, pour intégration dans une carte existante.
    var showsBackground = true

    var body: some View {
        if showsBackground {
            content
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .card()
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(color.opacity(0.14))
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
