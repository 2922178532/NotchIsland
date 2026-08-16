import AppKit
import Carbon.HIToolbox

/// 全局快捷键。
///
/// 用 Carbon 的 `RegisterEventHotKey` 实现，好处是不需要「辅助功能」权限，
/// 用户装上就能用，不必先去系统设置里授权。
@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()

    struct Shortcut {
        var keyCode: UInt32
        var modifiers: UInt32
        /// 用于显示在菜单里的符号，例如 "⌃⌥Space"。
        var display: String
    }

    private var handlers: [UInt32: () -> Void] = [:]
    private var references: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    private init() {}

    /// 注册一个全局快捷键，返回是否成功（失败通常意味着被别的程序占用了）。
    @discardableResult
    func register(_ shortcut: Shortcut, handler: @escaping () -> Void) -> Bool {
        installEventHandlerIfNeeded()

        let id = nextID
        nextID += 1

        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &reference
        )

        guard status == noErr, let reference else { return false }
        references[id] = reference
        handlers[id] = handler
        return true
    }

    func unregisterAll() {
        for reference in references.values {
            UnregisterEventHotKey(reference)
        }
        references.removeAll()
        handlers.removeAll()
    }

    fileprivate func handle(id: UInt32) {
        handlers[id]?()
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetEventDispatcherTarget(), hotKeyEventCallback, 1, &spec, nil, &eventHandler)
    }

    /// 四字符签名 'NISL'。
    private static let signature: OSType = 0x4E49_534C
}

private let hotKeyEventCallback: EventHandlerUPP = { _, event, _ in
    guard let event else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    let id = hotKeyID.id
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            HotKeyManager.shared.handle(id: id)
        }
    }
    return noErr
}

extension HotKeyManager.Shortcut {
    /// 呼出 / 收起刘海岛：⌃⌥Space
    static let toggleShelf = HotKeyManager.Shortcut(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(controlKey | optionKey),
        display: "⌃⌥Space"
    )

    /// 把剪贴板内容存进刘海岛：⌃⌥C
    static let importClipboard = HotKeyManager.Shortcut(
        keyCode: UInt32(kVK_ANSI_C),
        modifiers: UInt32(controlKey | optionKey),
        display: "⌃⌥C"
    )
}
