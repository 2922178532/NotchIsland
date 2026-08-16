import AppKit
import UniformTypeIdentifiers

/// 把粘贴板里的内容解析后存进刘海岛。拖入和快捷键两条路径共用这套逻辑。
enum PasteboardImporter {
    /// 拖入时需要注册的类型。
    /// 「文件承诺」放最前：微信、照片这类应用拖出图片时文件还不存在，
    /// 松手后源应用才会把文件写出来，必须走承诺接收的流程。
    static let acceptedTypes: [NSPasteboard.PasteboardType] = {
        var types = NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        types += [.fileURL, .URL, .png, .tiff, .rtf, .string]
        return types
    }()

    /// 承诺文件的接收回调队列。
    private static let promiseQueue = OperationQueue()

    static func canImport(from pasteboard: NSPasteboard) -> Bool {
        pasteboard.availableType(from: acceptedTypes) != nil
    }

    @MainActor
    @discardableResult
    static func importContents(of pasteboard: NSPasteboard, into store: ShelfStore) -> Bool {
        // 1. 现成的文件路径。
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
           !urls.isEmpty {
            return store.add(urls: urls) > 0
        }

        // 2. 文件承诺：先让源应用把文件写到临时目录，写完再正常导入。
        if let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver],
           !receivers.isEmpty {
            receivePromisedFiles(receivers, into: store)
            return true
        }

        // 3. 位图数据（例如浏览器里直接拖出的图片）。
        if let image = NSImage(pasteboard: pasteboard),
           let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            return store.add(data: png, preferredName: "图片", type: .png)
        }

        // 4. 文本与链接。
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            if let link = URL(string: text), link.scheme?.hasPrefix("http") == true {
                let contents = "[InternetShortcut]\nURL=\(text)\n"
                return store.add(data: Data(contents.utf8), preferredName: "链接", type: .internetShortcut)
            }
            return store.add(data: Data(text.utf8), preferredName: "文本", type: .plainText)
        }

        return false
    }

    @MainActor
    private static func receivePromisedFiles(_ receivers: [NSFilePromiseReceiver], into store: ShelfStore) {
        // 放系统临时目录，导入完成后由系统自行清理，避免和异步复制抢时序。
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchIsland-promise-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for receiver in receivers {
            receiver.receivePromisedFiles(atDestination: directory, options: [:], operationQueue: promiseQueue) { url, error in
                guard error == nil else { return }
                Task { @MainActor in
                    store.add(urls: [url])
                }
            }
        }
    }
}
