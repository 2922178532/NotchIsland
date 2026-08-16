import AppKit
import SwiftUI

/// 功耗监测中心：持有从 JuiceFlow 移植来的电池 / 进程 / 历史 / 告警服务，
/// 并管理仪表盘与设置窗口。
///
/// 服务随应用常驻：电池读数每 3 秒一次（IOKit，极轻），历史与告警持续工作；
/// 进程采样由 `ProcessService` 自己的可见性巡检调节——仪表盘窗口打开时全速，
/// 关闭后自动降到 30 秒一档，并把应用切回纯菜单栏形态。
@MainActor
final class PowerCenter {
    let battery = BatteryService()
    let processes = ProcessService()
    private(set) lazy var history = HistoryService(battery: battery, processes: processes)
    private(set) lazy var alerts = AlertService(battery: battery, processes: processes)

    private var dashboardWindow: NSWindow?
    private var settingsWindow: NSWindow?

    init() {
        // lazy 属性显式触发，让历史记录与告警从启动起就开始工作。
        _ = history
        _ = alerts
    }

    /// 岛上显示的当前功耗文字，优先系统总功耗，退回电池功率。
    var wattsText: String? {
        guard battery.hasBattery else { return nil }
        let snapshot = battery.snapshot
        if let system = snapshot.systemWatts, system > 0.05 {
            return String(format: "%.1f W", system)
        }
        let batteryWatts = abs(snapshot.watts)
        guard batteryWatts > 0.05 else { return nil }
        return String(format: "%.1f W", batteryWatts)
    }

    // MARK: - 窗口

    func openDashboard() {
        if dashboardWindow == nil {
            let root = ContentView()
                .environment(battery)
                .environment(processes)
                .environment(history)
            let hosting = NSHostingController(rootView: root)
            let window = NSWindow(contentViewController: hosting)
            // 标识符前缀 "main" 是 ProcessService 可见性巡检识别仪表盘的依据。
            window.identifier = NSUserInterfaceItemIdentifier("main-power-dashboard")
            window.title = "功耗监测"
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.isMovableByWindowBackground = true
            window.center()
            dashboardWindow = window
        }
        present(dashboardWindow)
        processes.syncViewers()
    }

    func openSettings() {
        if settingsWindow == nil {
            let root = SettingsView()
                .environment(processes)
            let hosting = NSHostingController(rootView: root)
            let window = NSWindow(contentViewController: hosting)
            window.title = "功耗监测设置"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        present(settingsWindow)
    }

    private func present(_ window: NSWindow?) {
        guard let window else { return }
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
