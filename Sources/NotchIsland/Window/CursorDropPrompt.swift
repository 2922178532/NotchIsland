import AppKit
import SwiftUI

@MainActor
final class CursorDropPromptState: ObservableObject {
    @Published var isTargeted = false
}

private struct CursorDropPromptView: View {
    @ObservedObject var state: CursorDropPromptState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: state.isTargeted ? "arrow.down.circle.fill" : "arrow.down.to.line.compact")
                .font(.system(size: 16, weight: .semibold))
            VStack(alignment: .leading, spacing: 1) {
                Text(state.isTargeted ? "松开即可存入" : "拖到这里")
                    .font(.system(size: 12, weight: .semibold))
                Text("存入刘海岛")
                    .font(.system(size: 9, weight: .medium))
                    .opacity(0.9)
            }
        }
        .foregroundStyle(.white)
        .glassLegible()
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background { cardBackground }
        // 面板和卡片一样大，留一圈边距给放大与玻璃的边缘高光，避免被窗口裁掉。
        .padding(3)
        .scaleEffect(state.isTargeted && !IslandStyle.reduceMotion ? 1.04 : 1)
        .animation(IslandStyle.reduceMotion ? .easeOut(duration: 0.12)
                   : .spring(response: 0.22, dampingFraction: 0.76), value: state.isTargeted)
        .accessibilityLabel(state.isTargeted ? "松开即可存入刘海岛" : "拖到这里存入刘海岛")
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    @ViewBuilder
    private var cardBackground: some View {
        if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(.clear, in: cardShape)
                .mask { cardShape.strokeBorder(lineWidth: 5) }
                .overlay {
                    cardShape.strokeBorder(.white.opacity(state.isTargeted ? 0.6 : 0), lineWidth: 1)
                }
        } else {
            cardShape
                .fill(IslandStyle.brandGradient(startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    cardShape.stroke(.white.opacity(state.isTargeted ? 0.75 : 0.22), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.3), radius: 12, y: 5)
        }
    }
}

/// 仅在外部拖拽期间出现的接收视图。卡片固定在拖拽被识别时的光标旁边，
/// 用户只需移动很短距离即可进入；若持续跟着光标移动，反而永远无法命中它。
@MainActor
final class CursorDropTargetView: NSView {
    let state: CursorDropPromptState
    var onTargeted: (() -> Void)?
    var onEnded: (() -> Void)?
    var onDrop: ((NSPasteboard) -> Bool)?

    init(frame frameRect: NSRect, state: CursorDropPromptState) {
        self.state = state
        super.init(frame: frameRect)
        registerForDraggedTypes(PasteboardImporter.acceptedTypes)

        let hosting = InteractiveHostingView(rootView: CursorDropPromptView(state: state))
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        if #available(macOS 13.0, *) { hosting.sizingOptions = [] }
        addSubview(hosting)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDragging(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDragging(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        state.isTargeted = false
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        state.isTargeted = false
        onEnded?()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        canAccept(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard canAccept(sender) else { return false }
        let accepted = onDrop?(sender.draggingPasteboard) ?? false
        state.isTargeted = false
        onEnded?()
        return accepted
    }

    private func updateDragging(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard canAccept(sender) else {
            state.isTargeted = false
            return []
        }
        if !state.isTargeted {
            state.isTargeted = true
            onTargeted?()
        }
        return .copy
    }

    private func canAccept(_ sender: NSDraggingInfo) -> Bool {
        sender.draggingSourceOperationMask.contains(.copy)
            && PasteboardImporter.canImport(from: sender.draggingPasteboard)
    }
}

private final class CursorDropPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class CursorDropPromptController {
    static let cardSize = CGSize(width: 138, height: 54)
    static let cursorGap: CGFloat = 18

    private let panel: CursorDropPanel
    private let state = CursorDropPromptState()
    private let dropView: CursorDropTargetView

    var onTargeted: (() -> Void)? {
        didSet { dropView.onTargeted = onTargeted }
    }
    var onEnded: (() -> Void)? {
        didSet { dropView.onEnded = onEnded }
    }
    var onDrop: ((NSPasteboard) -> Bool)? {
        didSet { dropView.onDrop = onDrop }
    }

    init() {
        let frame = CGRect(origin: .zero, size: Self.cardSize)
        panel = CursorDropPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        dropView = CursorDropTargetView(frame: frame, state: state)
        panel.contentView = dropView
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = true
    }

    var isVisible: Bool { panel.isVisible }

    func show(near cursor: CGPoint) {
        guard !panel.isVisible else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(cursor) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }
        state.isTargeted = false
        panel.setFrame(Self.cardFrame(near: cursor, in: screen.visibleFrame), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        guard panel.isVisible else { return }
        state.isTargeted = false
        panel.orderOut(nil)
    }

    static func cardFrame(near cursor: CGPoint, in availableFrame: CGRect) -> CGRect {
        var x = cursor.x + cursorGap
        if x + cardSize.width > availableFrame.maxX {
            x = cursor.x - cursorGap - cardSize.width
        }
        var y = cursor.y - cursorGap - cardSize.height
        if y < availableFrame.minY {
            y = cursor.y + cursorGap
        }
        x = min(max(x, availableFrame.minX), availableFrame.maxX - cardSize.width)
        y = min(max(y, availableFrame.minY), availableFrame.maxY - cardSize.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: cardSize)
    }
}
