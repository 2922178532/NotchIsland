import AppKit
import ApplicationServices

/// 状态栏管理功能所需的两项系统权限。
///
/// - 辅助功能：枚举各应用的状态栏项并模拟点击（核心，必须）。
/// - 屏幕录制：截取控制中心模块的真实图标（可选，缺了就用应用图标代替）。
enum MenuBarPermissions {
    static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// 触发系统的辅助功能授权弹窗。
    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static var screenCaptureGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestScreenCapture() {
        CGRequestScreenCaptureAccess()
    }

    /// 打开系统设置里的「辅助功能」授权页，方便用户手动开启。
    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
