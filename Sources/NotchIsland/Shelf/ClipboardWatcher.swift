import AppKit

/// 监听系统剪贴板，自动把复制的文件、图片和文本收进刘海岛。
///
/// macOS 没有剪贴板变化通知，业界通行做法是轮询 `changeCount`（一次整数比较，
/// 开销可忽略）。遵守剪贴板工具的行业约定：标记为私密（密码管理器）或
/// 瞬态的内容一律不收。
@MainActor
final class ClipboardWatcher {
    /// 剪贴板工具的行业约定标记：私密内容（密码管理器）与瞬态内容。
    private static let skippedTypes: [NSPasteboard.PasteboardType] = [
        NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
        NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
    ]
    private let store: ShelfStore
    private var timer: Timer?
    private var lastChangeCount: Int
    /// 上次收集内容的指纹，避免用户对同一内容反复按 ⌘C 时重复入库。
    private var lastFingerprint: String?

    /// 单次自动收集的文件数上限，防止全选复制大量文件时把暂存目录塞爆。
    private static let maxFilesPerCapture = 10

    init(store: ShelfStore) {
        self.store = store
        lastChangeCount = NSPasteboard.general.changeCount

        let timer = Timer(timeInterval: 0.7, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in self?.tick() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit {
        timer?.invalidate()
    }

    private func tick() {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        // 开关关闭时也要跟踪计数，否则一打开开关就会把很久之前复制的内容收进来。
        lastChangeCount = changeCount

        // 刘海岛自己写入剪贴板的内容（复制文本/复制全部）不要再收一遍。
        guard changeCount != ShelfStore.lastSelfWriteChangeCount else { return }

        guard Preferences.shared.autoCollectClipboard else { return }
        collect(from: pasteboard)
    }

    private func collect(from pasteboard: NSPasteboard) {
        // 密码管理器等来源的私密内容绝不能落盘成明文文件。
        guard pasteboard.availableType(from: Self.skippedTypes) == nil else { return }

        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
           !urls.isEmpty {
            // 排除自家暂存目录：否则「复制全部文件」会让刘海岛把自己再收一遍。
            let storageRoot = store.storageDirectory.path
            let external = urls.filter { !$0.path.hasPrefix(storageRoot) }
            guard !external.isEmpty else { return }

            let capped = Array(external.prefix(Self.maxFilesPerCapture))
            let fingerprint = "files|" + capped.map(\.path).joined(separator: "\n")
            guard fingerprint != lastFingerprint else { return }
            lastFingerprint = fingerprint

            store.add(urls: capped)
            return
        }

        if let image = NSImage(pasteboard: pasteboard),
           let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            let fingerprint = "image|\(png.count)|\(png.prefix(512).hashValue)"
            guard fingerprint != lastFingerprint else { return }
            lastFingerprint = fingerprint

            store.add(data: png, preferredName: "剪贴板图片", type: .png)
            return
        }

        if let text = pasteboard.string(forType: .string) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let fingerprint = "text|\(text.count)|\(text.hashValue)"
            guard fingerprint != lastFingerprint else { return }
            lastFingerprint = fingerprint

            if let link = URL(string: trimmed), link.scheme?.hasPrefix("http") == true {
                let contents = "[InternetShortcut]\nURL=\(trimmed)\n"
                store.add(data: Data(contents.utf8), preferredName: "链接", type: .internetShortcut)
            } else {
                store.add(data: Data(text.utf8), preferredName: "文本", type: .plainText)
            }
        }
    }
}
