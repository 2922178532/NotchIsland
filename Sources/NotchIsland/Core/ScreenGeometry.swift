import AppKit

/// 一块屏幕上「岛」所依附的刘海区域信息。
///
/// 所有矩形都使用 AppKit 的全局屏幕坐标（原点在主屏左下角，y 轴向上）。
struct NotchMetrics: Equatable {
    /// 刘海（真实或模拟）在全局坐标中的矩形。
    var notchRect: CGRect
    /// 所属屏幕的完整矩形。
    var screenFrame: CGRect
    /// 该屏幕是否具备物理刘海。
    var hasPhysicalNotch: Bool

    var notchSize: CGSize { notchRect.size }
}

enum ScreenGeometry {
    /// 没有物理刘海时模拟出来的岛宽度。
    static let simulatedNotchWidth: CGFloat = 200

    /// 选择用于承载岛的屏幕：优先带物理刘海的屏幕，其次是当前主屏。
    static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.physicalNotchRect != nil })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    static func metrics(for screen: NSScreen) -> NotchMetrics {
        if let notch = screen.physicalNotchRect {
            return NotchMetrics(notchRect: notch, screenFrame: screen.frame, hasPhysicalNotch: true)
        }

        // 无刘海机型（或外接屏）：在屏幕顶部正中模拟一块与菜单栏等高的区域。
        let height = max(screen.menuBarHeight, 24)
        let width = min(simulatedNotchWidth, screen.frame.width * 0.4)
        let rect = CGRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
        return NotchMetrics(notchRect: rect, screenFrame: screen.frame, hasPhysicalNotch: false)
    }
}

extension NSScreen {
    /// 物理刘海在全局坐标中的矩形；没有刘海时返回 nil。
    var physicalNotchRect: CGRect? {
        let height = safeAreaInsets.top
        guard height > 0,
              let left = auxiliaryTopLeftArea,
              let right = auxiliaryTopRightArea
        else { return nil }

        // 用左右两块可用区域的宽度反推刘海宽度，避免依赖辅助区域矩形的坐标原点约定。
        let width = frame.width - left.width - right.width
        guard width > 1 else { return nil }

        return CGRect(
            x: frame.midX - width / 2,
            y: frame.maxY - height,
            width: width,
            height: height
        )
    }

    /// 菜单栏高度。有刘海的屏幕上等于刘海高度。
    var menuBarHeight: CGFloat {
        let inset = safeAreaInsets.top
        if inset > 0 { return inset }
        let gap = frame.maxY - visibleFrame.maxY
        return gap > 0 ? gap : NSStatusBar.system.thickness
    }
}
