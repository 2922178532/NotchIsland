import Foundation

/// 只用本轮拖拽粘贴板的新内容识别意图；上次拖拽残留的内容不能让普通长按弹出岛。
/// 不读取实际文件/图片数据，文件承诺仍留到用户松手导入时兑现。
struct DragIntentSession {
    static let activationDelay: TimeInterval = 0.35

    private var changeCount: Int
    private var startedAt: TimeInterval?
    private(set) var isActive = false

    init(changeCount: Int) {
        self.changeCount = changeCount
    }

    @discardableResult
    mutating func update(
        changeCount: Int,
        hasSupportedContent: Bool,
        didEndDragging: Bool = false,
        suppressed: Bool = false,
        now: TimeInterval
    ) -> Bool {
        let hasNewContent = changeCount != self.changeCount
        self.changeCount = changeCount

        guard !didEndDragging, !suppressed else {
            cancel()
            return false
        }

        // 三指拖拽不一定会反映到 NSEvent.pressedMouseButtons，但系统仍会为真正的
        // 拖放会话更新 drag pasteboard。只信本轮新出现的可接收内容，普通长按不会触发。
        if hasNewContent {
            guard hasSupportedContent else {
                cancel()
                return false
            }
            if startedAt == nil { startedAt = now }
        }
        isActive = startedAt.map { now - $0 >= Self.activationDelay } ?? false
        return isActive
    }

    mutating func cancel() {
        startedAt = nil
        isActive = false
    }
}
