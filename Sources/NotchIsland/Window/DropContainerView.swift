import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
protocol DropContainerDelegate: AnyObject {
    func dropContainerContainsDraggingLocation(_ location: CGPoint) -> Bool
    func dropContainerDidBeginDragging()
    func dropContainerDidEndDragging()
    /// 返回是否成功接收了内容。
    func dropContainer(didReceive pasteboard: NSPasteboard) -> Bool
}

/// 面板的内容视图：负责接收从其他应用拖来的文件，并把 SwiftUI 界面作为子视图承载。
///
/// 拖拽处理放在 AppKit 层，这样在岛处于收起状态、窗口还很小的时候也能可靠地感知到拖拽进入。
final class DropContainerView: NSView {
    weak var delegate: DropContainerDelegate?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(PasteboardImporter.acceptedTypes)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDragging(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDragging(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        delegate?.dropContainerDidEndDragging()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        delegate?.dropContainerDidEndDragging()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        canAccept(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard canAccept(sender) else { return false }
        let accepted = delegate?.dropContainer(didReceive: sender.draggingPasteboard) ?? false
        delegate?.dropContainerDidEndDragging()
        return accepted
    }

    private func updateDragging(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard canAccept(sender) else {
            delegate?.dropContainerDidEndDragging()
            return []
        }
        // 透明留白进入实体色块时不一定再收到 draggingEntered，需要持续更新命中状态。
        delegate?.dropContainerDidBeginDragging()
        return .copy
    }

    private func canAccept(_ sender: NSDraggingInfo) -> Bool {
        guard let window,
              delegate?.dropContainerContainsDraggingLocation(
                window.convertPoint(toScreen: sender.draggingLocation)
              ) == true else { return false }
        return sender.draggingSourceOperationMask.contains(.copy)
            && PasteboardImporter.canImport(from: sender.draggingPasteboard)
    }
}

/// 允许在面板未激活时直接响应首次点击的宿主视图。
final class InteractiveHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
