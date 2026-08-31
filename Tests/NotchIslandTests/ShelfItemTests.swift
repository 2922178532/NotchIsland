import UniformTypeIdentifiers
import XCTest
@testable import NotchIsland

/// 暂存条目的分类与编解码。纯数据，不涉及磁盘。
final class ShelfItemTests: XCTestCase {

    private func item(fileName: String, typeIdentifier: String? = nil, isDirectory: Bool = false) -> ShelfItem {
        ShelfItem(
            fileName: fileName,
            originalPath: nil,
            byteSize: 0,
            isDirectory: isDirectory,
            typeIdentifier: typeIdentifier
        )
    }

    func testStorageIDMatchesID() {
        let id = UUID()
        let item = ShelfItem(
            id: id, fileName: "a.txt", originalPath: nil,
            byteSize: 0, isDirectory: false, typeIdentifier: nil
        )
        XCTAssertEqual(item.storageID, id.uuidString)
    }

    // MARK: - 分类

    func testImageIsCategorizedAsImage() {
        XCTAssertEqual(item(fileName: "截图.png").category, .image)
        XCTAssertEqual(item(fileName: "照片.JPEG").category, .image)
        XCTAssertEqual(item(fileName: "动图.gif").category, .image)
        XCTAssertEqual(item(fileName: "raw.heic").category, .image)
    }

    func testTextIsCategorizedAsText() {
        XCTAssertEqual(item(fileName: "笔记.txt").category, .text)
        XCTAssertEqual(item(fileName: "README.md").category, .text)
    }

    /// 链接快捷方式在筛选里归入「文本」。
    func testInternetShortcutIsCategorizedAsText() {
        XCTAssertEqual(item(fileName: "链接.url").category, .text)
        XCTAssertEqual(item(fileName: "无扩展名", typeIdentifier: UTType.internetShortcut.identifier).category, .text)
    }

    func testOtherTypesFallBackToFile() {
        XCTAssertEqual(item(fileName: "安装包.dmg").category, .file)
        XCTAssertEqual(item(fileName: "音频.mp3").category, .file)
        XCTAssertEqual(item(fileName: "没有扩展名").category, .file)
    }

    /// 目录一律算「文件」，即使名字带图片扩展名（.app 之类的包会命中这条）。
    func testDirectoryIsAlwaysFile() {
        XCTAssertEqual(item(fileName: "文件夹.png", isDirectory: true).category, .file)
        XCTAssertEqual(item(fileName: "刘海岛.app", isDirectory: true).category, .file)
    }

    /// 显式的 typeIdentifier 优先于扩展名推断。
    func testExplicitTypeIdentifierWins() {
        let mislabeled = item(fileName: "其实是图片.txt", typeIdentifier: UTType.png.identifier)
        XCTAssertEqual(mislabeled.category, .image)
    }

    /// 无法识别的 typeIdentifier 退回按扩展名判断。
    func testInvalidTypeIdentifierFallsBackToExtension() {
        XCTAssertEqual(item(fileName: "图.png", typeIdentifier: "不是一个有效的 UTI").category, .image)
    }

    // MARK: - 编解码

    /// index.json 用 ISO8601 存时间，round-trip 后必须完全一致。
    func testCodableRoundTrip() throws {
        let original = ShelfItem(
            fileName: "文件 名.txt",
            originalPath: "/tmp/文件 名.txt",
            addedAt: Date(timeIntervalSince1970: 1_700_000_000),
            byteSize: 4096,
            isDirectory: false,
            typeIdentifier: UTType.plainText.identifier
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(ShelfItem.self, from: try encoder.encode(original))

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.storageID, original.storageID)
    }

    func testFormattedSizeIsHumanReadable() {
        let item = ShelfItem(
            fileName: "a.bin", originalPath: nil, byteSize: 1_500_000,
            isDirectory: false, typeIdentifier: nil
        )
        XCTAssertTrue(item.formattedSize.contains("MB"), "实际为 \(item.formattedSize)")
    }
}
