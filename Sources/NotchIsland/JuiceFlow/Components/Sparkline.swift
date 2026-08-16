import SwiftUI

/// Mini-graphe de tendance : ligne + dégradé sous la courbe.
struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            if values.count >= 2 {
                let points = normalizedPoints(in: geometry.size)
                ZStack {
                    areaPath(points, size: geometry.size)
                        .fill(LinearGradient(
                            colors: [color.opacity(0.28), color.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        ))
                    linePath(points)
                        .stroke(color, style: StrokeStyle(
                            lineWidth: 1.5, lineCap: .round, lineJoin: .round
                        ))
                }
            } else {
                Text("historique en cours…")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        // Échelle min → max : une conso stable et élevée dessine une ligne,
        // pas une nappe pleine ; seules les variations remplissent la hauteur.
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1
        let span = max(maxValue - minValue, maxValue * 0.08, 0.0001)
        let step = size.width / CGFloat(max(values.count - 1, 1))
        return values.enumerated().map { index, value in
            CGPoint(
                x: step * CGFloat(index),
                // marges 8 % en haut / en bas
                y: size.height * (0.92 - 0.84 * CGFloat((value - minValue) / span))
            )
        }
    }

    private func linePath(_ points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
        }
    }

    private func areaPath(_ points: [CGPoint], size: CGSize) -> Path {
        Path { path in
            guard let first = points.first, let last = points.last else { return }
            path.move(to: CGPoint(x: first.x, y: size.height))
            path.addLine(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            path.addLine(to: CGPoint(x: last.x, y: size.height))
            path.closeSubpath()
        }
    }
}
