import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 负责岛的窗口生命周期：跟踪鼠标、在收起/悬停/展开之间切换、并同步调整面板尺寸。
///
/// 面板的尺寸始终跟随当前状态：收起时只覆盖物理刘海（那块区域本来就点不到，
/// 不会干扰任何操作），展开时才扩大到完整面板，因此不会长期遮挡屏幕顶部。
@MainActor
final class NotchWindowController: NSObject {
    private let store: ShelfStore
    private let powerCenter: PowerCenter
    let model: NotchModel
    let menuBarMonitor = MenuBarItemMonitor()

    /// 岛面板上的齿轮按钮弹出的设置菜单（由 AppDelegate 注入，与状态栏菜单共用）。
    var settingsMenuProvider: (() -> NSMenu)?

    private let panel: NotchPanel
    private let container: DropContainerView
    private var hostingView: InteractiveHostingView<NotchRootView>?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var expandWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var resizeWork: DispatchWorkItem?
    private var idleTimer: Timer?
    private var visibilityTimer: Timer?

    /// 从收起态悬停到自动展开之间的等待时间，用户可在菜单里调整。
    private var expandDelay: TimeInterval { Preferences.shared.expandDelay }
    /// 鼠标离开后延迟收起，避免手抖导致闪烁。
    private let collapseDelay: TimeInterval = 0.28
    private let animationDuration: TimeInterval = 0.5

    /// 鼠标不在岛上时的目标状态，由用户偏好决定。
    private var restingMode: NotchMode {
        Preferences.shared.idleRestMode.notchMode
    }

    private(set) var isEnabled = true
    /// 用户主动呼出后，暂时忽略「全屏时隐藏」，直到重新收起。
    private var overridesFullScreenHiding = false
    /// 上一次检测到的辅助功能授权状态，用于在用户授权后自动刷新界面。
    private var lastAccessibilityGranted = MenuBarPermissions.accessibilityGranted

    init(store: ShelfStore, powerCenter: PowerCenter) {
        self.store = store
        self.powerCenter = powerCenter

        let metrics = Self.currentMetrics()
        self.model = NotchModel(metrics: metrics, shelf: store)

        let initialFrame = model.windowFrame(for: .collapsed)
        self.panel = NotchPanel(contentRect: initialFrame)
        self.container = DropContainerView(frame: CGRect(origin: .zero, size: initialFrame.size))

        super.init()

        container.delegate = self
        container.autoresizingMask = [.width, .height]

        let root = NotchRootView(
            model: model,
            store: store,
            menuBarMonitor: menuBarMonitor,
            power: powerCenter,
            onTogglePin: { [weak self] in self?.togglePin() },
            onRequestCollapse: { [weak self] in self?.collapseNow() },
            onOpenSettings: { [weak self] in self?.openSettingsMenu() },
            onActivateMenuBarItem: { [weak self] in self?.activateMenuBarItem($0) },
            onRequestAccessibility: { [weak self] in self?.requestMenuBarPermissions() },
            onOpenPowerDashboard: { [weak self] in self?.openPowerDashboard() }
        )
        let hosting = InteractiveHostingView(rootView: root)
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        if #available(macOS 13.0, *) {
            hosting.sizingOptions = []
        }
        container.addSubview(hosting)
        hostingView = hosting

        panel.contentView = container
        panel.setFrame(initialFrame, display: false)
        panel.orderFrontRegardless()

        menuBarMonitor.onUpdate = { [weak self] in
            self?.reevaluateMenuBarStrip()
        }

        startMonitoring()
        observeSystemChanges()
        applyRestingModeIfIdle(animated: false)
    }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        idleTimer?.invalidate()
        visibilityTimer?.invalidate()
    }

    // MARK: - 对外操作

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        updatePanelVisibility()
    }

    /// 快捷键呼出：已经展开就收起。
    ///
    /// 岛处于「隐藏」状态时按快捷键会直接把它叫回来——这是唯一可靠的逃生通道：
    /// 菜单栏图标可能正好被刘海吞掉，用户隐藏岛之后会找不到任何恢复入口。
    func toggleExpanded() {
        if !isEnabled {
            setEnabled(true)
            expandNow(pin: true)
            return
        }
        if model.mode == .expanded {
            collapseNow()
        } else {
            expandNow(pin: true)
        }
    }

    /// 快捷键把剪贴板内容存进刘海岛，并短暂展开作为反馈。
    func importFromClipboard() {
        guard PasteboardImporter.importContents(of: .general, into: store) else {
            NSSound.beep()
            return
        }
        if !isEnabled { setEnabled(true) }
        expandNow(pin: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            guard let self else { return }
            if self.model.activeHitRect.contains(NSEvent.mouseLocation) {
                self.model.unpin()
            } else {
                self.collapseNow()
            }
        }
    }

    /// 手动展开（例如从菜单栏或快捷键触发）。
    func expandNow(pin: Bool = false) {
        guard isEnabled else { return }
        // 用户主动呼出时，即使当前有应用全屏也要让岛出来。
        overridesFullScreenHiding = true
        if !panel.isVisible { panel.orderFrontRegardless() }

        cancelPendingTransitions()
        transition(to: .expanded)
        if pin, !model.isPinned { model.togglePinned() }
    }

    func collapseNow() {
        cancelPendingTransitions()
        overridesFullScreenHiding = false
        model.unpin()
        model.isDropTargeted = false
        transition(to: restingMode)
    }

    /// 根据偏好切换到空闲时的展示状态（收起或常显悬停）。
    func applyRestingModeIfIdle(animated: Bool = true) {
        guard isEnabled, model.mode != .expanded, !model.isPinned, !model.isDropTargeted, !model.isDraggingOut else { return }
        let target = restingMode
        guard model.mode != target else { return }

        if animated {
            transition(to: target)
        } else {
            cancelPendingTransitions()
            model.setMode(target)
            panel.setFrame(model.windowFrame(for: target), display: false)
            updateMouseTransparency(inside: model.activeHitRect.contains(NSEvent.mouseLocation))
            updateIdleTimer()
        }
    }

    func togglePin() {
        if model.mode == .expanded {
            model.togglePinned()
        } else {
            expandNow(pin: true)
        }
    }

    /// 屏幕分辨率或显示器组合变化后重新计算几何。
    func refreshGeometry() {
        model.update(metrics: Self.currentMetrics())
        panel.setFrame(model.windowFrame(for: model.mode), display: true)
    }

    // MARK: - 显示与让位

    private var hostScreen: NSScreen? {
        NSScreen.screens.first { $0.frame == model.metrics.screenFrame }
            ?? ScreenGeometry.preferredScreen()
    }

    /// 判断岛所在屏幕上是否有应用处于全屏。
    ///
    /// 全屏时菜单栏会消失，屏幕的可见区域一直顶到上沿；平时可见区域顶部会空出菜单栏的高度。
    /// 如果用户本来就把菜单栏设成了自动隐藏，这个判断会一直成立，此时干脆不做让位，
    /// 否则岛会莫名其妙地一直不出现。
    private func isFullScreenAppPresent() -> Bool {
        guard !UserDefaults.standard.bool(forKey: "_HIHideMenuBar"),
              let screen = hostScreen
        else { return false }
        return screen.visibleFrame.maxY >= screen.frame.maxY - 1
    }

    private func updatePanelVisibility() {
        let hiddenByFullScreen = Preferences.shared.hideOnFullScreen
            && !overridesFullScreenHiding
            && isFullScreenAppPresent()
        let shouldShow = isEnabled && !hiddenByFullScreen

        if shouldShow {
            guard !panel.isVisible else { return }
            refreshGeometry()
            panel.orderFrontRegardless()
            // 隐藏面板时 forceCollapse() 把状态硬置成了收起，这里要按偏好恢复：
            // 否则选了「悬停」的用户退出全屏后，岛会一直保持收起直到手动划过去。
            applyRestingModeIfIdle(animated: false)
        } else {
            guard panel.isVisible else { return }
            forceCollapse()
            panel.orderOut(nil)
        }
    }

    // MARK: - 状态栏图标管理

    /// 根据权限与扫描结果决定是否显示状态栏图标行；展开状态下尺寸变化要联动窗口。
    func reevaluateMenuBarStrip() {
        let preferences = Preferences.shared
        let visible: Bool
        if !preferences.menuBarManagerEnabled {
            visible = false
        } else if !MenuBarPermissions.accessibilityGranted {
            visible = true // 展示授权引导。
        } else {
            visible = !menuBarMonitor.hiddenItems.isEmpty || menuBarMonitor.isRefreshing
        }
        guard visible != model.menuBarStripVisible else { return }

        guard model.mode == .expanded else {
            model.menuBarStripVisible = visible
            return
        }

        resizeWork?.cancel()
        let before = model.windowFrame(for: .expanded)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            model.menuBarStripVisible = visible
        }
        let after = model.windowFrame(for: .expanded)
        panel.setFrame(before.union(after), display: true)

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.model.mode == .expanded else { return }
            self.panel.setFrame(after, display: true)
        }
        resizeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration, execute: work)
    }

    /// 点击岛里的状态栏图标：先收起让出屏幕顶部，再模拟点击原图标弹出它的菜单。
    func activateMenuBarItem(_ item: MenuBarItem) {
        collapseNow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            MenuBarItemMonitor.press(item)
        }
    }

    func requestMenuBarPermissions() {
        if !MenuBarPermissions.accessibilityGranted {
            MenuBarPermissions.requestAccessibility()
            // TCC 里残留失效记录时系统不会再弹授权窗，兜底直接打开设置页。
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if !MenuBarPermissions.accessibilityGranted {
                    MenuBarPermissions.openAccessibilitySettings()
                }
            }
        } else if !MenuBarPermissions.screenCaptureGranted {
            MenuBarPermissions.requestScreenCapture()
        }
    }

    func openSettingsMenu() {
        guard let menu = settingsMenuProvider?() else { return }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// 打开功耗仪表盘：先收起岛，避免面板出现时被岛压在下面。
    func openPowerDashboard() {
        collapseNow()
        powerCenter.openDashboard()
    }

    /// 不带动画地立刻回到收起状态，用于隐藏面板前的重置。
    private func forceCollapse() {
        cancelPendingTransitions()
        resizeWork?.cancel()
        idleTimer?.invalidate()
        idleTimer = nil
        overridesFullScreenHiding = false

        model.unpin()
        model.isDropTargeted = false
        model.endDraggingOut()
        model.setMode(.collapsed)

        panel.setFrame(model.windowFrame(for: .collapsed), display: false)
        panel.ignoresMouseEvents = false
    }

    // MARK: - 状态切换

    private func transition(to newMode: NotchMode) {
        guard isEnabled, newMode != model.mode else { return }

        if newMode == .collapsed { overridesFullScreenHiding = false }
        if newMode == .expanded {
            // 展开前先确定状态栏图标行是否占位，让窗口一步到位。
            menuBarMonitor.refresh(metrics: model.metrics)
            reevaluateMenuBarStrip()
        }
        resizeWork?.cancel()

        // 动画期间先把窗口扩大到「变化前后的并集」，避免内容被窗口边界裁掉。
        // 所有状态的窗口都顶部贴屏幕上沿、水平居中于刘海，因此取并集不会让内容发生位移。
        let union = model.windowFrame(for: model.mode).union(model.windowFrame(for: newMode))
        panel.setFrame(union, display: true)

        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            model.setMode(newMode)
        }

        let target = model.windowFrame(for: newMode)
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.model.mode == newMode else { return }
            self.panel.setFrame(target, display: true)
            // 收起后窗口只剩刘海那么大，必须重新接收事件，否则感知不到拖进来的文件。
            if newMode == .collapsed {
                self.panel.ignoresMouseEvents = false
            }
        }
        resizeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration, execute: work)

        updateIdleTimer()
    }

    private func cancelPendingTransitions() {
        expandWork?.cancel()
        expandWork = nil
        collapseWork?.cancel()
        collapseWork = nil
    }

    private func scheduleExpand() {
        guard expandWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.expandWork = nil
            guard self.model.mode == .hovering else { return }
            self.transition(to: .expanded)
        }
        expandWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + expandDelay, execute: work)
    }

    private func scheduleCollapse() {
        guard collapseWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.collapseWork = nil
            guard !self.model.isPinned, !self.model.isDropTargeted, !self.model.isDraggingOut else { return }
            guard !self.model.activeHitRect.contains(NSEvent.mouseLocation) else { return }
            self.transition(to: self.restingMode)
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + collapseDelay, execute: work)
    }

    // MARK: - 鼠标跟踪

    private func startMonitoring() {
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { _ in
            MainActor.assumeIsolated { [weak self] in self?.evaluateMouseLocation() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { event in
            MainActor.assumeIsolated { [weak self] in self?.evaluateMouseLocation() }
            return event
        }
    }

    private func evaluateMouseLocation() {
        guard isEnabled else { return }

        // 从岛里往外拖文件时不收起；松开鼠标后才解除保护。
        if model.isDraggingOut {
            guard NSEvent.pressedMouseButtons == 0 else { return }
            model.endDraggingOut()
        }

        let location = NSEvent.mouseLocation
        let inside = model.activeHitRect.contains(location)
        updateMouseTransparency(inside: inside)

        if inside {
            collapseWork?.cancel()
            collapseWork = nil
            switch model.mode {
            case .collapsed:
                transition(to: .hovering)
                scheduleExpand()
            case .hovering:
                scheduleExpand()
            case .expanded:
                break
            }
        } else {
            expandWork?.cancel()
            expandWork = nil
            guard model.mode != restingMode, !model.isPinned, !model.isDropTargeted else { return }
            scheduleCollapse()
        }
    }

    /// 岛比刘海大的时候，鼠标一旦离开就让点击穿透到下层，避免挡住菜单栏。
    ///
    /// 收起态必须保持接收事件：那时窗口只覆盖刘海，且要靠它感知拖进来的文件。
    private func updateMouseTransparency(inside: Bool) {
        let shouldIgnore = model.mode != .collapsed
            && !inside
            && !model.isPinned
            && !model.isDropTargeted
            && !model.isDraggingOut
        if panel.ignoresMouseEvents != shouldIgnore {
            panel.ignoresMouseEvents = shouldIgnore
        }
    }

    /// 鼠标可能在岛外停止移动而不再产生事件，用低频定时器兜底检查。
    private func updateIdleTimer() {
        idleTimer?.invalidate()
        guard !(model.mode == .collapsed && restingMode == .collapsed) else {
            idleTimer = nil
            return
        }
        let timer = Timer(timeInterval: 0.4, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in self?.evaluateMouseLocation() }
        }
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    // MARK: - 系统事件

    private func observeSystemChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { [weak self] in
                self?.refreshGeometry()
                self?.updatePanelVisibility()
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { [weak self] in self?.updatePanelVisibility() }
        }

        // 有些应用进入全屏不会切换空间，用低频轮询兜底；顺带监测权限变化。
        let timer = Timer(timeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in
                self?.updatePanelVisibility()
                self?.checkPermissionChanges()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        visibilityTimer = timer
    }

    /// 用户在系统设置里授予或撤销辅助功能权限后，界面自动跟着更新，不需要重开面板。
    private func checkPermissionChanges() {
        let granted = MenuBarPermissions.accessibilityGranted
        guard granted != lastAccessibilityGranted else { return }
        lastAccessibilityGranted = granted
        menuBarMonitor.refresh(metrics: model.metrics, force: true)
        reevaluateMenuBarStrip()
    }

    private static func currentMetrics() -> NotchMetrics {
        if let screen = ScreenGeometry.preferredScreen() {
            return ScreenGeometry.metrics(for: screen)
        }
        let fallbackScreen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        return NotchMetrics(
            notchRect: CGRect(x: 620, y: 876, width: 200, height: 24),
            screenFrame: fallbackScreen,
            hasPhysicalNotch: false
        )
    }
}

// MARK: - 接收拖入的内容

extension NotchWindowController: DropContainerDelegate {
    func dropContainerDidBeginDragging() {
        guard isEnabled else { return }
        cancelPendingTransitions()
        model.isDropTargeted = true
        transition(to: .expanded)
    }

    func dropContainerDidEndDragging() {
        guard model.isDropTargeted else { return }
        model.isDropTargeted = false
        // 拖拽结束后如果鼠标已经不在岛上，正常走收起流程。
        scheduleCollapse()
    }

    func dropContainer(didReceive pasteboard: NSPasteboard) -> Bool {
        PasteboardImporter.importContents(of: pasteboard, into: store)
    }
}
