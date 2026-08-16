import AppKit
import Combine

/// 岛的展示状态。
enum NotchMode: Equatable {
    /// 完全收起，与物理刘海融为一体。
    case collapsed
    /// 鼠标靠近时的轻微放大提示。
    case hovering
    /// 展开成面板，显示刘海岛内容。
    case expanded
}

/// 岛的布局常量。
enum NotchLayout {
    /// 收起态在刘海下方额外保留的感应高度，用于更容易命中悬停与拖拽。
    /// 这是收起时唯一会占用屏幕的区域，所以要尽量小。
    static let collapsedHotZone: CGFloat = 6
    /// 悬停态相对刘海各方向的放大量。高度要容得下一行功耗数字。
    static let hoverPadding = CGSize(width: 14, height: 22)
    /// 展开态刘海下方的内容区高度。要容得下分类筛选行加一排文件卡片。
    static let expandedContentHeight: CGFloat = 202
    /// 状态栏图标行的高度（显示被刘海挡住的图标时追加）。
    static let menuBarStripHeight: CGFloat = 44
    /// 展开态的最小宽度。要保证刘海右侧放得下功耗徽章加全部操作按钮。
    static let expandedMinWidth: CGFloat = 640
    /// 展开态窗口在岛两侧预留的空白，用于绘制反向圆角与阴影。
    static let horizontalMargin: CGFloat = 48
    /// 展开态窗口在岛下方预留的空白，用于绘制阴影。
    static let bottomMargin: CGFloat = 48
    /// 展开态底部圆角。
    static let expandedBottomRadius: CGFloat = 22
    /// 展开态顶部反向圆角。
    static let expandedTopRadius: CGFloat = 12
}

/// 驱动岛的界面状态，由 `NotchWindowController` 更新，被 SwiftUI 视图观察。
@MainActor
final class NotchModel: ObservableObject {
    @Published private(set) var mode: NotchMode = .collapsed
    /// 是否有文件正被拖到岛上方。
    @Published var isDropTargeted = false
    /// 用户是否正把文件从岛里拖往别处，此时不能收起。
    @Published private(set) var isDraggingOut = false
    /// 用户是否手动固定了展开状态（点击岛之后，鼠标移开也不收起）。
    @Published private(set) var isPinned = false
    /// 展开面板里是否显示状态栏图标行（有被挡住的图标、或需要引导授权时为真）。
    @Published var menuBarStripVisible = false
    @Published private(set) var metrics: NotchMetrics

    let shelf: ShelfStore

    init(metrics: NotchMetrics, shelf: ShelfStore) {
        self.metrics = metrics
        self.shelf = shelf
    }

    func update(metrics: NotchMetrics) {
        guard metrics != self.metrics else { return }
        self.metrics = metrics
    }

    func setMode(_ newMode: NotchMode) {
        guard newMode != mode else { return }
        mode = newMode
        if newMode != .expanded { isPinned = false }
    }

    func togglePinned() {
        isPinned.toggle()
    }

    func unpin() {
        isPinned = false
    }

    func beginDraggingOut() {
        isDraggingOut = true
    }

    func endDraggingOut() {
        guard isDraggingOut else { return }
        isDraggingOut = false
    }

    // MARK: - 尺寸

    /// 当前状态下岛本身的尺寸。
    var islandSize: CGSize {
        switch mode {
        case .collapsed:
            return metrics.notchSize
        case .hovering:
            return CGSize(
                width: metrics.notchSize.width + NotchLayout.hoverPadding.width * 2,
                height: metrics.notchSize.height + NotchLayout.hoverPadding.height
            )
        case .expanded:
            return expandedIslandSize
        }
    }

    var expandedIslandSize: CGSize {
        CGSize(
            width: max(NotchLayout.expandedMinWidth, metrics.notchSize.width + 340),
            height: metrics.notchSize.height
                + NotchLayout.expandedContentHeight
                + (menuBarStripVisible ? NotchLayout.menuBarStripHeight : 0)
        )
    }

    var bottomCornerRadius: CGFloat {
        switch mode {
        case .collapsed: return metrics.hasPhysicalNotch ? 10 : 8
        case .hovering: return 14
        case .expanded: return NotchLayout.expandedBottomRadius
        }
    }

    var topCornerRadius: CGFloat {
        switch mode {
        case .collapsed: return 0
        case .hovering: return 8
        case .expanded: return NotchLayout.expandedTopRadius
        }
    }

    // MARK: - 窗口几何

    /// 当前状态下窗口需要占据的屏幕矩形（全局坐标）。
    func windowFrame(for targetMode: NotchMode) -> CGRect {
        let notch = metrics.notchRect
        switch targetMode {
        case .collapsed:
            return CGRect(
                x: notch.minX,
                y: notch.minY - NotchLayout.collapsedHotZone,
                width: notch.width,
                height: notch.height + NotchLayout.collapsedHotZone
            )
        case .hovering:
            let size = CGSize(
                width: metrics.notchSize.width + NotchLayout.hoverPadding.width * 2 + 24,
                height: metrics.notchSize.height + NotchLayout.hoverPadding.height + 16
            )
            return CGRect(
                x: notch.midX - size.width / 2,
                y: notch.maxY - size.height,
                width: size.width,
                height: size.height
            )
        case .expanded:
            let island = expandedIslandSize
            let size = CGSize(
                width: island.width + NotchLayout.horizontalMargin * 2,
                height: island.height + NotchLayout.bottomMargin
            )
            return CGRect(
                x: notch.midX - size.width / 2,
                y: notch.maxY - size.height,
                width: size.width,
                height: size.height
            )
        }
    }

    /// 用于判定鼠标是否仍停留在岛上的矩形（全局坐标）。
    var activeHitRect: CGRect {
        let notch = metrics.notchRect
        let size = islandSize
        let base = CGRect(
            x: notch.midX - size.width / 2,
            y: notch.maxY - size.height,
            width: size.width,
            height: size.height
        )
        // 收起态额外向下放宽，便于用户把鼠标或文件送进来。
        if mode == .collapsed {
            return base.insetBy(dx: -6, dy: 0)
                .offsetBy(dx: 0, dy: -NotchLayout.collapsedHotZone / 2)
                .insetBy(dx: 0, dy: -NotchLayout.collapsedHotZone / 2)
        }
        return base
    }
}
