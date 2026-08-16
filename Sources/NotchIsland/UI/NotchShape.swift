import SwiftUI

/// 灵动岛形状：顶部贴住屏幕上边缘并向两侧外扩出反向圆角，底部两角为普通圆角。
///
/// 注意路径会在水平方向超出 `rect` 各 `topCornerRadius`，
/// 使用时需要给视图预留同等的水平留白。
struct NotchShape: Shape {
    var bottomCornerRadius: CGFloat
    var topCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottomCornerRadius, topCornerRadius) }
        set {
            bottomCornerRadius = newValue.first
            topCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let bottom = min(bottomCornerRadius, rect.height / 2, rect.width / 2)
        let top = min(topCornerRadius, rect.width / 2)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX - top, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + top),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - bottom, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + top))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX + top, y: rect.minY),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}
