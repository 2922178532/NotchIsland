import Foundation

/// 用户偏好，存放在 `UserDefaults` 中。
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private enum Key {
        static let expirationDays = "NotchIsland.expirationDays"
        static let hideOnFullScreen = "NotchIsland.hideOnFullScreen"
        static let menuBarManagerEnabled = "NotchIsland.menuBarManagerEnabled"
        static let expandDelay = "NotchIsland.expandDelay"
        static let hideIdleIndicator = "NotchIsland.hideIdleIndicator"
        static let autoCollectClipboard = "NotchIsland.autoCollectClipboard"
        static let hiddenMenuBarApps = "NotchIsland.hiddenMenuBarApps"
        static let importSoundName = "NotchIsland.importSoundName"
    }

    /// 暂存内容保留的天数，0 表示不自动清理。
    @Published var expirationDays: Int {
        didSet { UserDefaults.standard.set(expirationDays, forKey: Key.expirationDays) }
    }

    /// 有应用处于全屏时是否隐藏岛。
    @Published var hideOnFullScreen: Bool {
        didSet { UserDefaults.standard.set(hideOnFullScreen, forKey: Key.hideOnFullScreen) }
    }

    /// 是否在岛里显示被刘海挡住的状态栏图标。
    @Published var menuBarManagerEnabled: Bool {
        didSet { UserDefaults.standard.set(menuBarManagerEnabled, forKey: Key.menuBarManagerEnabled) }
    }

    /// 鼠标悬停刘海后到展开完整面板的等待秒数。
    @Published var expandDelay: Double {
        didSet { UserDefaults.standard.set(expandDelay, forKey: Key.expandDelay) }
    }

    /// 收起状态下隐藏「刘海岛有文件」的渐变指示条，让刘海保持原生外观。
    /// 只影响视觉：悬停、拖拽、快捷键等交互不受影响。
    @Published var hideIdleIndicator: Bool {
        didSet { UserDefaults.standard.set(hideIdleIndicator, forKey: Key.hideIdleIndicator) }
    }

    /// 自动把复制到剪贴板的文件和图片收进刘海岛。
    @Published var autoCollectClipboard: Bool {
        didSet { UserDefaults.standard.set(autoCollectClipboard, forKey: Key.autoCollectClipboard) }
    }

    /// 用户选择「不再显示」的状态栏图标所属应用（bundle identifier）。
    @Published var hiddenMenuBarApps: [String] {
        didSet { UserDefaults.standard.set(hiddenMenuBarApps, forKey: Key.hiddenMenuBarApps) }
    }

    /// 存入成功时的提示音名称（系统音效），空字符串表示关闭。
    @Published var importSoundName: String {
        didSet { UserDefaults.standard.set(importSoundName, forKey: Key.importSoundName) }
    }

    /// 可供选择的存入提示音。
    static let importSoundOptions: [(name: String, title: String)] = [
        ("", "关闭"),
        ("Tink", "叮 · Tink"),
        ("Pop", "啵 · Pop"),
        ("Glass", "玻璃 · Glass"),
        ("Ping", "乒 · Ping"),
        ("Purr", "轻震 · Purr"),
        ("Bottle", "瓶音 · Bottle"),
        ("Submarine", "潜艇 · Submarine"),
        ("Hero", "号角 · Hero"),
    ]

    /// 可供选择的保留时长。
    static let expirationOptions: [(days: Int, title: String)] = [
        (0, "一直保留"),
        (1, "1 天"),
        (3, "3 天"),
        (7, "7 天"),
        (30, "30 天"),
    ]

    /// 可供选择的悬停展开延迟。
    static let expandDelayOptions: [(delay: Double, title: String)] = [
        (0, "立即展开"),
        (0.1, "较快（0.1 秒）"),
        (0.25, "默认（0.25 秒）"),
        (0.5, "较慢（0.5 秒）"),
        (1.0, "慢（1 秒）"),
    ]

    private init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Key.expirationDays: 7,
            Key.hideOnFullScreen: true,
            Key.menuBarManagerEnabled: true,
            Key.expandDelay: 0.25,
            Key.hideIdleIndicator: false,
            Key.autoCollectClipboard: false,
            Key.importSoundName: "Tink",
        ])
        expirationDays = defaults.integer(forKey: Key.expirationDays)
        hideOnFullScreen = defaults.bool(forKey: Key.hideOnFullScreen)
        menuBarManagerEnabled = defaults.bool(forKey: Key.menuBarManagerEnabled)
        expandDelay = defaults.double(forKey: Key.expandDelay)
        hideIdleIndicator = defaults.bool(forKey: Key.hideIdleIndicator)
        autoCollectClipboard = defaults.bool(forKey: Key.autoCollectClipboard)
        hiddenMenuBarApps = defaults.stringArray(forKey: Key.hiddenMenuBarApps) ?? []
        importSoundName = defaults.string(forKey: Key.importSoundName) ?? "Tink"
    }
}
