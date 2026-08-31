import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: ShelfStore?
    private var controller: NotchWindowController?
    private var powerCenter: PowerCenter?
    private var clipboardWatcher: ClipboardWatcher?
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var cleanupTimer: Timer?

    private var toggleHotKeyRegistered = false
    private var clipboardHotKeyRegistered = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = ShelfStore()
        self.store = store
        let powerCenter = PowerCenter()
        self.powerCenter = powerCenter
        controller = NotchWindowController(store: store, powerCenter: powerCenter)
        clipboardWatcher = ClipboardWatcher(store: store)

        setupStatusItem()
        registerHotKeys()
        startExpirationCleanup()

        // 调试用：无需移动鼠标即可看到展开后的样子。
        if ProcessInfo.processInfo.environment["NOTCHISLAND_AUTOEXPAND"] == "1" {
            controller?.expandNow(pin: true)
        } else {
            showOnboardingIfNeeded()
        }
        // 调试用：直接打开功耗仪表盘。
        if ProcessInfo.processInfo.environment["NOTCHISLAND_DASHBOARD"] == "1" {
            powerCenter.openDashboard()
        }
        if ProcessInfo.processInfo.environment["NOTCHISLAND_DEBUG"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                let snapshot = powerCenter.battery.snapshot
                let line = "功耗诊断：hasBattery=\(powerCenter.battery.hasBattery)"
                    + " systemWatts=\(snapshot.systemWatts.map { String($0) } ?? "nil")"
                    + " watts=\(snapshot.watts)"
                    + " wattsText=\(powerCenter.wattsText ?? "nil")\n"
                FileHandle.standardError.write(Data(line.utf8))
            }
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    /// 首次启动时自动展开一次，让用户知道岛在哪、怎么用。
    private func showOnboardingIfNeeded() {
        let key = "NotchIsland.hasLaunchedBefore"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        controller?.expandNow(pin: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.controller?.collapseNow()
        }
    }

    // MARK: - 全局快捷键

    private func registerHotKeys() {
        toggleHotKeyRegistered = HotKeyManager.shared.register(.toggleShelf) { [weak self] in
            self?.controller?.toggleExpanded()
        }
        clipboardHotKeyRegistered = HotKeyManager.shared.register(.importClipboard) { [weak self] in
            self?.controller?.importFromClipboard()
        }

        if ProcessInfo.processInfo.environment["NOTCHISLAND_DEBUG"] == "1" {
            let report = "快捷键注册：\(HotKeyManager.Shortcut.toggleShelf.display)=\(toggleHotKeyRegistered)"
                + " \(HotKeyManager.Shortcut.importClipboard.display)=\(clipboardHotKeyRegistered)\n"
            FileHandle.standardError.write(Data(report.utf8))
        }
    }

    // MARK: - 过期清理

    private func startExpirationCleanup() {
        runExpirationCleanup()
        let timer = Timer(timeInterval: 3600, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in self?.runExpirationCleanup() }
        }
        RunLoop.main.add(timer, forMode: .common)
        cleanupTimer = timer
    }

    private func runExpirationCleanup() {
        store?.removeExpired(olderThan: Preferences.shared.expirationDays)
    }

    // MARK: - 菜单栏

    private func setupStatusItem() {
        let menu = buildMenu()
        statusMenu = menu
        // 岛面板上的齿轮共用同一份菜单——菜单栏图标本身也可能被刘海吞掉。
        controller?.settingsMenuProvider = { [weak self] in
            self?.statusMenu ?? NSMenu()
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "tray.full",
            accessibilityDescription: "刘海岛"
        )
        item.button?.image?.isTemplate = true
        item.menu = menu
        statusItem = item
    }

    private enum MenuTag: Int {
        case toggleIsland = 1
        case launchAtLogin = 2
        case hideOnFullScreen = 3
        case moveToApplications = 4
        case expandShelf = 5
        case importClipboard = 6
        case menuBarManager = 7
        case expirationMenu = 8
        case expandDelayMenu = 9
        case autoCollectClipboard = 10
        case restoreExcludedIcons = 11
        case importSound = 12
        case idleRestModeMenu = 13
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let expand = NSMenuItem(title: "展开刘海岛", action: #selector(expandShelf), keyEquivalent: " ")
        expand.keyEquivalentModifierMask = [.control, .option]
        expand.tag = MenuTag.expandShelf.rawValue
        menu.addItem(expand)

        let clipboard = NSMenuItem(title: "存入剪贴板内容", action: #selector(importClipboard), keyEquivalent: "c")
        clipboard.keyEquivalentModifierMask = [.control, .option]
        clipboard.tag = MenuTag.importClipboard.rawValue
        menu.addItem(clipboard)

        menu.addItem(withTitle: "复制全部文件", action: #selector(copyAll), keyEquivalent: "")
        menu.addItem(withTitle: "清空全部内容", action: #selector(clearShelf), keyEquivalent: "")
        menu.addItem(.separator())

        menu.addItem(withTitle: "功耗监测面板", action: #selector(openPowerDashboard), keyEquivalent: "")
        menu.addItem(withTitle: "功耗监测设置…", action: #selector(openPowerSettings), keyEquivalent: "")
        menu.addItem(.separator())

        let expiration = NSMenuItem(title: "自动清理", action: nil, keyEquivalent: "")
        expiration.tag = MenuTag.expirationMenu.rawValue
        expiration.submenu = buildExpirationMenu()
        menu.addItem(expiration)

        let expandDelay = NSMenuItem(title: "悬停展开延迟", action: nil, keyEquivalent: "")
        expandDelay.tag = MenuTag.expandDelayMenu.rawValue
        expandDelay.submenu = buildExpandDelayMenu()
        menu.addItem(expandDelay)

        let idleRest = NSMenuItem(title: "空闲时显示", action: nil, keyEquivalent: "")
        idleRest.tag = MenuTag.idleRestModeMenu.rawValue
        idleRest.submenu = buildIdleRestModeMenu()
        menu.addItem(idleRest)

        let autoCollect = NSMenuItem(title: "自动收存剪贴板内容", action: #selector(toggleAutoCollectClipboard), keyEquivalent: "")
        autoCollect.tag = MenuTag.autoCollectClipboard.rawValue
        menu.addItem(autoCollect)

        let importSound = NSMenuItem(title: "存入提示音", action: nil, keyEquivalent: "")
        importSound.tag = MenuTag.importSound.rawValue
        importSound.submenu = buildImportSoundMenu()
        menu.addItem(importSound)

        let menuBarManager = NSMenuItem(title: "显示被刘海挡住的图标", action: #selector(toggleMenuBarManager), keyEquivalent: "")
        menuBarManager.tag = MenuTag.menuBarManager.rawValue
        menu.addItem(menuBarManager)

        let restoreExcluded = NSMenuItem(title: "重新显示「不再显示」的图标", action: #selector(restoreExcludedIcons), keyEquivalent: "")
        restoreExcluded.tag = MenuTag.restoreExcludedIcons.rawValue
        menu.addItem(restoreExcluded)

        let fullScreen = NSMenuItem(title: "全屏应用时隐藏", action: #selector(toggleHideOnFullScreen), keyEquivalent: "")
        fullScreen.tag = MenuTag.hideOnFullScreen.rawValue
        menu.addItem(fullScreen)

        let toggle = NSMenuItem(title: "隐藏待机指示条", action: #selector(toggleIdleIndicator), keyEquivalent: "")
        toggle.tag = MenuTag.toggleIsland.rawValue
        menu.addItem(toggle)
        menu.addItem(.separator())

        let launch = NSMenuItem(title: "开机时自动启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.tag = MenuTag.launchAtLogin.rawValue
        menu.addItem(launch)

        let move = NSMenuItem(title: "移动到「应用程序」文件夹", action: #selector(moveToApplications), keyEquivalent: "")
        move.tag = MenuTag.moveToApplications.rawValue
        menu.addItem(move)

        menu.addItem(withTitle: "打开暂存文件夹", action: #selector(openStorage), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出", action: #selector(quit), keyEquivalent: "q")

        for menuItem in menu.items where menuItem.action != nil {
            menuItem.target = self
        }
        return menu
    }

    private func buildExpirationMenu() -> NSMenu {
        let submenu = NSMenu()
        for option in Preferences.expirationOptions {
            let item = NSMenuItem(title: option.title, action: #selector(selectExpiration(_:)), keyEquivalent: "")
            item.tag = option.days
            item.target = self
            submenu.addItem(item)
        }
        return submenu
    }

    private func buildExpandDelayMenu() -> NSMenu {
        let submenu = NSMenu()
        for option in Preferences.expandDelayOptions {
            let item = NSMenuItem(title: option.title, action: #selector(selectExpandDelay(_:)), keyEquivalent: "")
            // tag 只能存整数，用毫秒表示。
            item.tag = Int(option.delay * 1000)
            item.target = self
            submenu.addItem(item)
        }
        return submenu
    }

    private func buildIdleRestModeMenu() -> NSMenu {
        let submenu = NSMenu()
        for mode in IdleRestMode.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(selectIdleRestMode(_:)), keyEquivalent: "")
            item.representedObject = mode.rawValue
            item.target = self
            submenu.addItem(item)
        }
        return submenu
    }

    private func buildImportSoundMenu() -> NSMenu {
        let submenu = NSMenu()
        for option in Preferences.importSoundOptions {
            let item = NSMenuItem(title: option.title, action: #selector(selectImportSound(_:)), keyEquivalent: "")
            item.representedObject = option.name
            item.target = self
            submenu.addItem(item)
            if option.name.isEmpty {
                submenu.addItem(.separator())
            }
        }
        return submenu
    }

    // MARK: - 菜单动作

    @objc private func expandShelf() {
        controller?.expandNow(pin: true)
    }

    @objc private func importClipboard() {
        controller?.importFromClipboard()
    }

    @objc private func copyAll() {
        store?.copyAllToPasteboard()
    }

    @objc private func clearShelf() {
        store?.removeAll()
    }

    /// 只隐藏收起态的渐变指示条，悬停、拖拽等交互不受影响。
    /// 之前的「整个隐藏刘海岛」会让用户失去所有恢复入口（菜单栏图标可能被刘海吞掉）。
    @objc private func toggleIdleIndicator() {
        Preferences.shared.hideIdleIndicator.toggle()
    }

    @objc private func toggleAutoCollectClipboard() {
        Preferences.shared.autoCollectClipboard.toggle()
    }

    @objc private func restoreExcludedIcons() {
        Preferences.shared.hiddenMenuBarApps.removeAll()
        controller?.menuBarMonitor.refresh(metrics: controller!.model.metrics, force: true)
    }

    /// 选中即试播，方便直接对比音色。
    @objc private func selectImportSound(_ sender: NSMenuItem) {
        let name = sender.representedObject as? String ?? ""
        Preferences.shared.importSoundName = name
        if !name.isEmpty {
            NSSound(named: name)?.play()
        }
    }

    @objc private func toggleHideOnFullScreen() {
        Preferences.shared.hideOnFullScreen.toggle()
    }

    @objc private func toggleMenuBarManager() {
        Preferences.shared.menuBarManagerEnabled.toggle()
        controller?.reevaluateMenuBarStrip()
    }

    @objc private func openPowerDashboard() {
        powerCenter?.openDashboard()
    }

    @objc private func openPowerSettings() {
        powerCenter?.openSettings()
    }

    @objc private func selectExpiration(_ sender: NSMenuItem) {
        Preferences.shared.expirationDays = sender.tag
        runExpirationCleanup()
    }

    @objc private func selectExpandDelay(_ sender: NSMenuItem) {
        Preferences.shared.expandDelay = Double(sender.tag) / 1000
    }

    @objc private func selectIdleRestMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = IdleRestMode(rawValue: raw) else { return }
        Preferences.shared.idleRestMode = mode
        controller?.applyRestingModeIfIdle()
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法修改开机启动设置"
            alert.informativeText = isInstalledInApplications
                ? error.localizedDescription
                : "请先用菜单里的「移动到「应用程序」文件夹」，再设置开机启动。"
            alert.runModal()
        }
    }

    @objc private func moveToApplications() {
        let current = Bundle.main.bundleURL
        let target = URL(fileURLWithPath: "/Applications").appendingPathComponent(current.lastPathComponent)

        do {
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.copyItem(at: current, to: target)
        } catch {
            let alert = NSAlert()
            alert.messageText = "移动失败"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            return
        }

        // 先把当前实例的岛藏起来，避免和新副本的岛短暂重叠。
        controller?.setEnabled(false)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", target.path]
        try? task.run()

        NSApp.terminate(nil)
    }

    @objc private func openStorage() {
        guard let store else { return }
        NSWorkspace.shared.open(store.storageDirectory)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private var isInstalledInApplications: Bool {
        Bundle.main.bundleURL.deletingLastPathComponent().path == "/Applications"
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        if let item = menu.item(withTag: MenuTag.toggleIsland.rawValue) {
            item.state = Preferences.shared.hideIdleIndicator ? .on : .off
        }
        if let item = menu.item(withTag: MenuTag.autoCollectClipboard.rawValue) {
            item.state = Preferences.shared.autoCollectClipboard ? .on : .off
        }
        if let item = menu.item(withTag: MenuTag.restoreExcludedIcons.rawValue) {
            item.isHidden = Preferences.shared.hiddenMenuBarApps.isEmpty
        }
        if let submenu = menu.item(withTag: MenuTag.importSound.rawValue)?.submenu {
            let current = Preferences.shared.importSoundName
            for option in submenu.items {
                guard let name = option.representedObject as? String else { continue }
                option.state = name == current ? .on : .off
            }
        }
        if let item = menu.item(withTag: MenuTag.launchAtLogin.rawValue) {
            item.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
        if let item = menu.item(withTag: MenuTag.hideOnFullScreen.rawValue) {
            item.state = Preferences.shared.hideOnFullScreen ? .on : .off
        }
        if let item = menu.item(withTag: MenuTag.menuBarManager.rawValue) {
            item.state = Preferences.shared.menuBarManagerEnabled ? .on : .off
        }
        if let item = menu.item(withTag: MenuTag.moveToApplications.rawValue) {
            item.isHidden = isInstalledInApplications
        }
        if let item = menu.item(withTag: MenuTag.expandShelf.rawValue), !toggleHotKeyRegistered {
            item.title = "展开刘海岛（快捷键被占用）"
            item.keyEquivalent = ""
        }
        if let item = menu.item(withTag: MenuTag.importClipboard.rawValue), !clipboardHotKeyRegistered {
            item.title = "存入剪贴板内容（快捷键被占用）"
            item.keyEquivalent = ""
        }

        if let submenu = menu.item(withTag: MenuTag.expirationMenu.rawValue)?.submenu {
            let expiration = Preferences.shared.expirationDays
            for option in submenu.items {
                option.state = option.tag == expiration ? .on : .off
            }
        }
        if let submenu = menu.item(withTag: MenuTag.expandDelayMenu.rawValue)?.submenu {
            let delayMS = Int(Preferences.shared.expandDelay * 1000)
            for option in submenu.items {
                option.state = option.tag == delayMS ? .on : .off
            }
        }
        if let submenu = menu.item(withTag: MenuTag.idleRestModeMenu.rawValue)?.submenu {
            let current = Preferences.shared.idleRestMode.rawValue
            for option in submenu.items {
                option.state = (option.representedObject as? String) == current ? .on : .off
            }
        }
    }
}
