import AppKit

/// 承载岛的无边框浮动面板。
///
/// 使用 `.nonactivatingPanel` 保证与岛交互时不会抢走当前应用的焦点，
/// 层级高于状态栏以便展开后覆盖菜单栏区域。
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        acceptsMouseMovedEvents = true
        hidesOnDeactivate = false
        animationBehavior = .none
        // 岛不参与窗口截图之外的系统行为，避免出现在「窗口」菜单与 Mission Control 中。
        isExcludedFromWindowsMenu = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
