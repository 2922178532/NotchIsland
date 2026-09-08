import AppKit
import SwiftUI

/// 停留计时与视图刷新解耦：同一卡片内移动或刷新不会重新计时。
struct ShelfHoverSession {
    static let delay: TimeInterval = 0.3
    private(set) var target: UUID?
    private var enteredAt: TimeInterval = 0

    mutating func update(target: UUID?, now: TimeInterval, blocked: Bool = false) -> UUID? {
        guard !blocked, let target else {
            reset()
            return nil
        }
        if self.target != target {
            self.target = target
            enteredAt = now
        }
        return now - enteredAt >= Self.delay ? target : nil
    }

    mutating func reset() {
        target = nil
        enteredAt = 0
    }
}

/// 透明锚点仅提供卡片的实际可见范围，不抢点击、拖拽或滚轮。
struct ShelfHoverPreviewAnchor: NSViewRepresentable {
    let item: ShelfItem
    let url: URL
    let controller: ShelfHoverPreviewController

    func makeNSView(context: Context) -> ShelfHoverAnchorView {
        let view = ShelfHoverAnchorView()
        view.item = item
        view.url = url
        controller.register(view)
        return view
    }

    func updateNSView(_ view: ShelfHoverAnchorView, context: Context) {
        view.item = item
        view.url = url
    }

    static func dismantleNSView(_ view: ShelfHoverAnchorView, coordinator: ()) {
        view.previewController?.unregister(view)
    }
}

final class ShelfHoverAnchorView: NSView {
    var item: ShelfItem?
    var url: URL?
    weak var previewController: ShelfHoverPreviewController?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    var visibleCardRect: CGRect { visibleRect.intersection(bounds) }

    var screenRect: CGRect? {
        // SwiftUI 的 AppKit 背景视图可能不裁剪子视图，visibleRect 会大于 bounds。
        // 必须再与自身 bounds 相交，否则整行卡片会得到同一个命中范围。
        let clipped = visibleCardRect
        guard let window, window.isVisible, window.isOnActiveSpace,
              !isHiddenOrHasHiddenAncestor, !clipped.isEmpty else { return nil }
        return window.convertToScreen(convert(clipped, to: nil))
    }
}

/// 自管悬浮预览，避免系统 tooltip 在非激活面板和视图刷新时被取消。
/// 只在岛展开时使用一个定时器；即使鼠标静止、卡片滚入，也能重新命中。
@MainActor
final class ShelfHoverPreviewController {
    private let anchors = NSHashTable<ShelfHoverAnchorView>.weakObjects()
    private var timer: Timer?
    private var session = ShelfHoverSession()
    private var activeID: UUID?
    private var loadingTask: Task<Void, Never>?
    private var panel: ShelfPreviewPanel?
    private var menuTrackingDepth = 0
    private var menuObservers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        menuObservers = [
            center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.menuTrackingDepth += 1
                    self?.suspend()
                }
            },
            center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.menuTrackingDepth = max(0, self.menuTrackingDepth - 1)
                    self.suspend()
                }
            },
        ]
    }

    deinit {
        timer?.invalidate()
        loadingTask?.cancel()
        menuObservers.forEach(NotificationCenter.default.removeObserver)
    }

    func register(_ anchor: ShelfHoverAnchorView) {
        anchor.previewController = self
        anchors.add(anchor)
    }

    func unregister(_ anchor: ShelfHoverAnchorView) {
        anchors.remove(anchor)
        anchor.previewController = nil
        if session.target == anchor.item?.id { suspend() }
    }

    func setEnabled(_ enabled: Bool) {
        timer?.invalidate()
        timer = nil
        suspend()
        guard enabled else { return }
        let timer = Timer(timeInterval: 0.06, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func suspend() {
        session.reset()
        dismiss()
    }

    private func dismiss() {
        loadingTask?.cancel()
        loadingTask = nil
        activeID = nil
        if let panel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
            panel.contentView = nil
        }
    }

    private func update() {
        let mouse = NSEvent.mouseLocation
        let anchor = anchors.allObjects.first { $0.screenRect?.contains(mouse) == true }
        let ready = session.update(
            target: anchor?.item?.id,
            now: ProcessInfo.processInfo.systemUptime,
            blocked: NSEvent.pressedMouseButtons != 0 || menuTrackingDepth > 0
        )
        guard let ready, let anchor, let item = anchor.item, let url = anchor.url else {
            if activeID != nil { dismiss() }
            return
        }
        if activeID == ready {
            position(relativeTo: anchor)
            return
        }

        dismiss()
        activeID = ready
        show(ShelfPreviewContent(item: item), relativeTo: anchor)
        loadingTask = Task { [weak self, weak anchor] in
            let content: ShelfPreviewContent
            switch item.category {
            case .text:
                let text = await Task.detached(priority: .userInitiated) {
                    ShelfPreviewContent.readText(at: url)
                }.value
                content = ShelfPreviewContent(item: item, text: text)
            case .image:
                let image = await ThumbnailLoader.thumbnail(
                    for: item, at: url, size: CGSize(width: 480, height: 320)
                )
                content = ShelfPreviewContent(item: item, image: image)
            case .file:
                content = ShelfPreviewContent(item: item, image: NSWorkspace.shared.icon(forFile: url.path))
            }
            // 快速划过 A → B → A 时，旧任务也必须作废，不能只比较 item ID。
            guard !Task.isCancelled, let self, let anchor, self.activeID == ready,
                  anchor.screenRect?.contains(NSEvent.mouseLocation) == true else { return }
            self.show(content, relativeTo: anchor)
        }
    }

    private func show(_ content: ShelfPreviewContent, relativeTo anchor: ShelfHoverAnchorView) {
        guard let parent = anchor.window else { return }
        let panel = panel ?? ShelfPreviewPanel()
        self.panel = panel
        panel.setContent(content)
        position(relativeTo: anchor)
        if panel.parent !== parent {
            panel.parent?.removeChildWindow(panel)
            parent.addChildWindow(panel, ordered: .above)
        }
        panel.orderFrontRegardless()
    }

    private func position(relativeTo anchor: ShelfHoverAnchorView) {
        guard let panel, let parent = anchor.window, let rect = anchor.screenRect,
              let screen = parent.screen else { return }
        let frame = Self.previewFrame(
            size: panel.frame.size, anchor: rect, parent: parent.frame, screen: screen.visibleFrame
        )
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    /// 放在岛下方，避免遮住相邻卡片；左右边界按所在屏幕夹紧。
    static func previewFrame(size: CGSize, anchor: CGRect, parent: CGRect, screen: CGRect) -> CGRect {
        let safe = screen.insetBy(dx: 8, dy: 8)
        let size = CGSize(width: min(size.width, safe.width), height: min(size.height, safe.height))
        let x = min(max(anchor.midX - size.width / 2, safe.minX), safe.maxX - size.width)
        let y = min(max(parent.minY - size.height - 8, safe.minY), safe.maxY - size.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}

final class ShelfPreviewPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func setContent(_ content: ShelfPreviewContent) {
        let hosting = NSHostingView(rootView: content)
        // 预览依赖内容计算窗口大小，不能像固定尺寸的岛一样禁用固有尺寸。
        hosting.sizingOptions = [.intrinsicContentSize]
        contentView = hosting
        setContentSize(hosting.intrinsicContentSize)
    }
}

struct ShelfPreviewContent: View {
    let item: ShelfItem
    var text: String?
    var image: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: item.category.symbolName)
                    .foregroundStyle(.secondary)
                Text(item.fileName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)
            }

            if item.category == .text {
                if let text {
                    Text(text.isEmpty ? "无法读取文本内容" : text)
                        .font(.system(size: 13))
                        .lineSpacing(4)
                        .lineLimit(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 60)
                }
            } else if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(height: item.category == .image ? 300 : 160)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: item.category == .image ? 300 : 160)
            }

            Divider()
            Text("\(item.formattedSize) · 双击卡片\(item.category == .text ? "查看完整内容" : "打开")")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: item.category == .image ? 480 : (item.category == .text ? 400 : 240))
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.15), lineWidth: 1)
        }
        .environment(\.colorScheme, .dark)
    }

    nonisolated static func readText(at url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 64 * 1024) else { return "" }
        var text = String(decoding: data, as: UTF8.self)
        if text.hasPrefix("[InternetShortcut]"),
           let line = text.split(separator: "\n").first(where: { $0.hasPrefix("URL=") }) {
            text = String(line.dropFirst(4))
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
