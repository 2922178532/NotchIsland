import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import NotchIsland

/// 粘贴板解析的测试。用独立命名的粘贴板和临时暂存目录，不碰系统剪贴板和用户数据。
@MainActor
final class PasteboardImporterTests: XCTestCase {

    private var pasteboard: NSPasteboard!
    private var rootDirectory: URL!
    private var store: ShelfStore!

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard.withUniqueName()
        rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchIslandTests-\(UUID().uuidString)", isDirectory: true)
        store = ShelfStore(rootDirectory: rootDirectory)
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: rootDirectory)
        pasteboard = nil
        store = nil
        rootDirectory = nil
        super.tearDown()
    }

    private func write(string: String) {
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    // MARK: - canImport

    func testCannotImportFromEmptyPasteboard() {
        pasteboard.clearContents()
        XCTAssertFalse(PasteboardImporter.canImport(from: pasteboard))
    }

    func testCanImportPlainString() {
        write(string: "随便一段文字")
        XCTAssertTrue(PasteboardImporter.canImport(from: pasteboard))
    }

    // MARK: - 文本

    /// 普通文本存成 .txt，分类为「文本」，正文可原样读回。
    func testImportsPlainTextAsTextItem() {
        write(string: "刘海岛测试文本")

        XCTAssertTrue(PasteboardImporter.importContents(of: pasteboard, into: store))

        XCTAssertEqual(store.items.count, 1)
        let item = store.items[0]
        XCTAssertEqual(item.category, .text)
        XCTAssertTrue(item.fileName.hasPrefix("文本 "), "文件名应以「文本」开头，实际为 \(item.fileName)")
        XCTAssertEqual(item.fileName.hasSuffix(".txt"), true)
        XCTAssertEqual(store.textContent(of: item), "刘海岛测试文本")
        XCTAssertNil(item.originalPath, "粘贴板内容没有原始路径")
    }

    /// 多行文本不应被误判成链接。
    func testMultilineTextIsNotTreatedAsLink() {
        write(string: "第一行\nhttps://example.com\n第三行")

        XCTAssertTrue(PasteboardImporter.importContents(of: pasteboard, into: store))

        let item = store.items[0]
        XCTAssertTrue(item.fileName.hasSuffix(".txt"))
        XCTAssertEqual(store.textContent(of: item), "第一行\nhttps://example.com\n第三行")
    }

    /// 没有 scheme 的字符串是文本，不是链接。
    func testBareDomainIsTreatedAsText() {
        write(string: "example.com")

        XCTAssertTrue(PasteboardImporter.importContents(of: pasteboard, into: store))
        XCTAssertTrue(store.items[0].fileName.hasSuffix(".txt"))
    }

    /// 非 http(s) 的 scheme 也按文本处理。
    func testNonHTTPSchemeIsTreatedAsText() {
        write(string: "ftp://example.com/file.zip")

        XCTAssertTrue(PasteboardImporter.importContents(of: pasteboard, into: store))
        XCTAssertTrue(store.items[0].fileName.hasSuffix(".txt"))
    }

    func testEmptyStringIsNotImported() {
        write(string: "")

        XCTAssertFalse(PasteboardImporter.importContents(of: pasteboard, into: store))
        XCTAssertTrue(store.items.isEmpty)
    }

    // MARK: - 链接

    /// http/https 链接存成 .url 快捷方式，读回时还原成网址本身。
    func testImportsHTTPLinkAsInternetShortcut() {
        write(string: "https://github.com/2922178532/NotchIsland")

        XCTAssertTrue(PasteboardImporter.importContents(of: pasteboard, into: store))

        let item = store.items[0]
        XCTAssertEqual(item.category, .text, "链接在筛选里归入「文本」")
        XCTAssertTrue(item.fileName.hasPrefix("链接 "), "实际为 \(item.fileName)")
        XCTAssertEqual(item.contentType, .internetShortcut)
        XCTAssertEqual(
            store.textContent(of: item),
            "https://github.com/2922178532/NotchIsland",
            "textContent 应剥掉 [InternetShortcut] 头部只留网址"
        )
    }

    func testImportsPlainHTTPLink() {
        write(string: "http://example.com")

        XCTAssertTrue(PasteboardImporter.importContents(of: pasteboard, into: store))
        XCTAssertEqual(store.textContent(of: store.items[0]), "http://example.com")
    }

    /// 落盘的快捷方式必须是 Windows .url 的格式，否则双击打不开。
    func testInternetShortcutFileFormat() {
        write(string: "https://example.com/a?b=c")
        PasteboardImporter.importContents(of: pasteboard, into: store)

        let contents = try! String(contentsOf: store.fileURL(for: store.items[0]), encoding: .utf8)

        XCTAssertEqual(contents, "[InternetShortcut]\nURL=https://example.com/a?b=c\n")
    }

    // MARK: - 文件

    /// 拖入真实文件：复制进暂存目录，原文件删掉后副本依然可用。
    func testImportsFileURLAndKeepsCopyAfterOriginalIsDeleted() async throws {
        let source = rootDirectory.appendingPathComponent("源文件.txt")
        try FileManager.default.createDirectory(
            at: rootDirectory, withIntermediateDirectories: true
        )
        try Data("原始内容".utf8).write(to: source)

        pasteboard.clearContents()
        pasteboard.writeObjects([source as NSURL])

        XCTAssertTrue(PasteboardImporter.importContents(of: pasteboard, into: store))

        // add(urls:) 在后台线程复制，等它落库。
        try await waitForItems(count: 1)

        let item = store.items[0]
        XCTAssertEqual(item.fileName, "源文件.txt")
        XCTAssertEqual(item.originalPath, source.resolvingSymlinksInPath().path)
        XCTAssertEqual(item.byteSize, Int64(Data("原始内容".utf8).count))
        XCTAssertFalse(item.isDirectory)

        try FileManager.default.removeItem(at: source)
        let copied = try String(contentsOf: store.fileURL(for: item), encoding: .utf8)
        XCTAssertEqual(copied, "原始内容", "原文件删除后暂存副本仍应存在")
    }

    /// 不存在的路径不应产生条目。
    func testIgnoresNonexistentFileURL() {
        let missing = rootDirectory.appendingPathComponent("并不存在.txt")
        pasteboard.clearContents()
        pasteboard.writeObjects([missing as NSURL])

        XCTAssertFalse(PasteboardImporter.importContents(of: pasteboard, into: store))
        XCTAssertTrue(store.items.isEmpty)
    }

    // MARK: - 工具

    /// 轮询等待后台导入完成，避免依赖固定的 sleep 时长。
    private func waitForItems(count: Int, timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while store.items.count < count {
            if Date() > deadline {
                XCTFail("等待 \(count) 个条目超时，当前 \(store.items.count) 个")
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
