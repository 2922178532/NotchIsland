import AppKit
import SwiftUI

/// 覆盖在 SwiftUI 标签之上的透明拖拽源，用于一次把多个文件拖到别的应用里。
///
/// 拖拽操作被强制为 `.copy`，接收方只会复制副本，刘海岛里的暂存文件不会被移走。
struct MultiFileDragView: NSViewRepresentable {
    var urls: () -> [URL]
    var onDragStart: () -> Void = {}
    var onDragEnd: () -> Void = {}

    func makeNSView(context: Context) -> MultiDragSourceView {
        let view = MultiDragSourceView()
        view.urlsProvider = urls
        view.onDragStart = onDragStart
        view.onDragEnd = onDragEnd
        return view
    }

    func updateNSView(_ nsView: MultiDragSourceView, context: Context) {
        nsView.urlsProvider = urls
        nsView.onDragStart = onDragStart
        nsView.onDragEnd = onDragEnd
    }
}

final class MultiDragSourceView: NSView, NSDraggingSource {
    var urlsProvider: () -> [URL] = { [] }
    var onDragStart: () -> Void = {}
    var onDragEnd: () -> Void = {}

    private var mouseDownLocation: NSPoint?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownLocation = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownLocation else { return }
        let distance = hypot(
            event.locationInWindow.x - start.x,
            event.locationInWindow.y - start.y
        )
        guard distance > 4 else { return }
        mouseDownLocation = nil
        beginDrag(with: event)
    }

    private func beginDrag(with event: NSEvent) {
        let urls = urlsProvider()
        guard !urls.isEmpty else { return }

        let items: [NSDraggingItem] = urls.enumerated().map { index, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 56, height: 56)
            let offset = CGFloat(min(index, 4)) * 7
            item.setDraggingFrame(
                NSRect(x: offset, y: -offset, width: icon.size.width, height: icon.size.height),
                contents: icon
            )
            return item
        }

        onDragStart()
        beginDraggingSession(with: items, event: event, source: self)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        onDragEnd()
    }
}
