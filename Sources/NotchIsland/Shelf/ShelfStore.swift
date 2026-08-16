import AppKit
import Combine
import UniformTypeIdentifiers

/// 刘海岛的数据与文件管理。
///
/// 目录结构：
/// ```
/// ~/Library/Application Support/NotchIsland/
///   index.json          // 元数据
///   Items/<uuid>/<原文件名>
/// ```
@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []
    /// 正在后台复制的文件数量。
    @Published private(set) var importingCount = 0
    /// 最近一次操作的提示文案，用于在岛上做轻量反馈。
    @Published var lastMessage: String?

    private let fileManager = FileManager.default
    private let rootURL: URL
    private let itemsURL: URL
    private let indexURL: URL

    init() {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        rootURL = support.appendingPathComponent("NotchIsland", isDirectory: true)
        itemsURL = rootURL.appendingPathComponent("Items", isDirectory: true)
        indexURL = rootURL.appendingPathComponent("index.json")

        try? fileManager.createDirectory(at: itemsURL, withIntermediateDirectories: true)
        load()
    }

    // MARK: - 查询

    var isEmpty: Bool { items.isEmpty }

    var totalSize: Int64 { items.reduce(0) { $0 + $1.byteSize } }

    /// 某一项在暂存目录中的实际路径。
    func fileURL(for item: ShelfItem) -> URL {
        itemsURL
            .appendingPathComponent(item.storageID, isDirectory: true)
            .appendingPathComponent(item.fileName)
    }

    /// 文本 / 链接条目的正文内容（链接解析出网址本身）。
    /// 非文本条目或内容过大时返回 nil，调用方退回文件语义。
    func textContent(of item: ShelfItem) -> String? {
        guard item.category == .text else { return nil }
        guard let data = try? Data(contentsOf: fileURL(for: item)), data.count <= 2_000_000 else {
            return nil
        }
        var text = String(decoding: data, as: UTF8.self)
        if text.hasPrefix("[InternetShortcut]"),
           let line = text.split(separator: "\n").first(where: { $0.hasPrefix("URL=") }) {
            text = String(line.dropFirst(4))
        }
        return text
    }

    // MARK: - 增删

    /// 把若干个文件 URL 复制进刘海岛。
    ///
    /// 复制在后台进行，拖入大文件时界面不会卡住；返回值是开始导入的文件数量。
    @discardableResult
    func add(urls: [URL]) -> Int {
        let candidates = urls
            .map { $0.resolvingSymlinksInPath() }
            .filter { fileManager.fileExists(atPath: $0.path) }
        guard !candidates.isEmpty else { return 0 }

        importingCount += candidates.count
        let destination = itemsURL

        Task.detached(priority: .userInitiated) {
            let imported = Self.copyItems(at: candidates, into: destination)
            await MainActor.run {
                self.items.insert(contentsOf: imported, at: 0)
                self.importingCount = max(0, self.importingCount - candidates.count)
                self.lastMessage = imported.isEmpty
                    ? "文件存入失败"
                    : "已存入 \(imported.count) 个文件"
                self.save()
                if !imported.isEmpty { self.playImportSound() }
            }
        }
        return candidates.count
    }

    /// 存入成功的轻量提示音，对静默进行的剪贴板自动收存尤其重要。
    private func playImportSound() {
        let name = Preferences.shared.importSoundName
        guard !name.isEmpty else { return }
        NSSound(named: name)?.play()
    }

    /// 在后台线程执行实际的复制，不触碰任何主线程状态。
    private nonisolated static func copyItems(at urls: [URL], into itemsDirectory: URL) -> [ShelfItem] {
        let fileManager = FileManager.default
        var results: [ShelfItem] = []

        for url in urls {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentTypeKey])
            let isDirectory = values?.isDirectory ?? false

            var item = ShelfItem(
                fileName: url.lastPathComponent,
                originalPath: url.path,
                byteSize: 0,
                isDirectory: isDirectory,
                typeIdentifier: values?.contentType?.identifier
            )

            let directory = itemsDirectory.appendingPathComponent(item.storageID, isDirectory: true)
            let destination = directory.appendingPathComponent(item.fileName)
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                try fileManager.copyItem(at: url, to: destination)
            } catch {
                try? fileManager.removeItem(at: directory)
                continue
            }

            item.byteSize = totalSize(of: destination, isDirectory: isDirectory)
            results.append(item)
        }
        return results
    }

    /// 存入一段原始数据（例如从浏览器拖来的图片或选中的文本）。
    @discardableResult
    func add(data: Data, preferredName: String, type: UTType) -> Bool {
        let name = uniqueName(base: preferredName, extension: type.preferredFilenameExtension)
        let item = ShelfItem(
            fileName: name,
            originalPath: nil,
            byteSize: Int64(data.count),
            isDirectory: false,
            typeIdentifier: type.identifier
        )
        let directory = itemsURL.appendingPathComponent(item.storageID, isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent(name))
        } catch {
            try? fileManager.removeItem(at: directory)
            return false
        }
        items.insert(item, at: 0)
        save()
        lastMessage = "已存入 \(name)"
        playImportSound()
        return true
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        let directory = itemsURL.appendingPathComponent(item.storageID, isDirectory: true)
        try? fileManager.removeItem(at: directory)
        save()
    }

    func removeAll() {
        for item in items {
            let directory = itemsURL.appendingPathComponent(item.storageID, isDirectory: true)
            try? fileManager.removeItem(at: directory)
        }
        items.removeAll()
        save()
        lastMessage = "已清空"
    }

    /// 清掉存入时间超过指定天数的内容，`days` 为 0 时不做任何事。
    @discardableResult
    func removeExpired(olderThan days: Int) -> Int {
        guard days > 0 else { return 0 }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let expired = items.filter { $0.addedAt < cutoff }
        guard !expired.isEmpty else { return 0 }

        for item in expired {
            let directory = itemsURL.appendingPathComponent(item.storageID, isDirectory: true)
            try? fileManager.removeItem(at: directory)
        }
        items.removeAll { $0.addedAt < cutoff }
        save()
        return expired.count
    }

    // MARK: - 打开与定位

    func open(_ item: ShelfItem) {
        NSWorkspace.shared.open(fileURL(for: item))
    }

    func revealInFinder(_ item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL(for: item)])
    }

    func revealOriginal(_ item: ShelfItem) {
        guard let path = item.originalPath, fileManager.fileExists(atPath: path) else {
            revealInFinder(item)
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// 应用自己最后一次写剪贴板时的变化计数，剪贴板自动收存据此跳过自家内容。
    static var lastSelfWriteChangeCount = -1

    /// 把所有暂存文件写入剪贴板，便于在目标应用里直接粘贴。
    func copyAllToPasteboard() {
        guard !items.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(items.map { fileURL(for: $0) as NSURL })
        Self.lastSelfWriteChangeCount = pasteboard.changeCount
        lastMessage = "已复制 \(items.count) 个文件"
    }

    /// 复制单项：文本和链接条目还原成文字本身（粘贴出内容而不是一个 txt 文件），
    /// 文件和图片保持文件语义。
    func copyToPasteboard(_ item: ShelfItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let text = textContent(of: item) {
            pasteboard.setString(text, forType: .string)
            lastMessage = "已复制文本内容"
        } else {
            pasteboard.writeObjects([fileURL(for: item) as NSURL])
            lastMessage = "已复制 \(item.fileName)"
        }
        Self.lastSelfWriteChangeCount = pasteboard.changeCount
    }

    // MARK: - 持久化

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([ShelfItem].self, from: data) else { return }
        // 过滤掉暂存文件已经不存在的记录（例如用户手动清理过目录）。
        items = decoded.filter { fileManager.fileExists(atPath: fileURL(for: $0).path) }
        if items.count != decoded.count { save() }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    // MARK: - 工具

    private nonisolated static func totalSize(of url: URL, isDirectory: Bool) -> Int64 {
        if !isDirectory {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            return Int64(values?.fileSize ?? 0)
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let child as URL in enumerator {
            let values = try? child.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }

    private func uniqueName(base: String, extension ext: String?) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        if let ext, !ext.isEmpty {
            return "\(base) \(stamp).\(ext)"
        }
        return "\(base) \(stamp)"
    }

    /// 暂存目录，供菜单里的「在访达中打开」使用。
    var storageDirectory: URL { rootURL }
}
