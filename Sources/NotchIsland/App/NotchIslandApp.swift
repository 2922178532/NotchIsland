import AppKit

@main
enum NotchIslandApp {
    /// 持有强引用，`NSApplication.delegate` 本身是弱引用。
    @MainActor private static var delegate: AppDelegate?

    @MainActor
    static func main() {
        let app = NSApplication.shared
        // 只在菜单栏出现，不占用程序坞。
        app.setActivationPolicy(.accessory)

        if CommandLine.arguments.contains("--diagnose") {
            printDiagnostics()
            return
        }

        let delegate = AppDelegate()
        Self.delegate = delegate
        app.delegate = delegate
        app.run()
    }

    /// 打印屏幕与刘海识别结果，便于排查岛的位置问题。
    @MainActor
    private static func printDiagnostics() {
        print("屏幕数量：\(NSScreen.screens.count)")
        for (index, screen) in NSScreen.screens.enumerated() {
            let metrics = ScreenGeometry.metrics(for: screen)
            print("""
            [\(index)] \(screen.localizedName)
                frame            = \(screen.frame)
                visibleFrame     = \(screen.visibleFrame)
                safeAreaInsets   = \(screen.safeAreaInsets)
                auxTopLeftArea   = \(screen.auxiliaryTopLeftArea.map { "\($0)" } ?? "nil")
                auxTopRightArea  = \(screen.auxiliaryTopRightArea.map { "\($0)" } ?? "nil")
                物理刘海          = \(metrics.hasPhysicalNotch ? "是" : "否（使用模拟区域）")
                岛依附矩形        = \(metrics.notchRect)
            """)
        }
        if let preferred = ScreenGeometry.preferredScreen() {
            print("岛将显示在：\(preferred.localizedName)")
        }
    }
}
