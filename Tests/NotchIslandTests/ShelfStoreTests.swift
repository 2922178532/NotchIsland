import UniformTypeIdentifiers
import XCTest
@testable import NotchIsland

/// 暂存目录的增删、过期清理与持久化。全程在临时目录里进行。
@MainActor
final class ShelfStoreTests: XCTestCase {

    private var rootDirectory: URL!
    private var store: ShelfStore!

    override func setUp() {
        super.setUp()
        rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchIslandTests-\(UUID().uuidString)", isDirectory: true)
        store = ShelfStore(rootDirectory: rootDirectory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: rootDirectory)
        store = nil
        rootDirectory = nil
        super.tearDown()
    }

    @discardableResult
    private func addText(_ text: String, name: String = "文本") -> ShelfItem {
        XCTAssertTrue(store.add(data: Data(text.utf8), preferredName: name, type: .plainText))
        return store.items[0]
    }

    // MARK: - 增删

    func testAddDataWritesFileAndPrependsItem() {
        let first = addText("一")
        let second = addText("二")

        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.items[0].id, second.id, "新条目应插到最前面")
        XCTAssertEqual(store.items[1].id, first.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL(for: first).path))
    }

    func testTotalSizeSumsItems() {
        addText("12345")
        addText("123")

        XCTAssertEqual(store.totalSize, 8)
    }

    func testIsEmpty() {
        XCTAssertTrue(store.isEmpty)
        addText("x")
        XCTAssertFalse(store.isEmpty)
    }

    /// 删除条目要连它的暂存目录一起删掉，不能只从列表里摘出去。
    func testRemoveDeletesBackingDirectory() {
        let item = addText("待删除")
        let fileURL = store.fileURL(for: item)

        store.remove(item)

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testRemoveAllDeletesEverything() {
        let a = addText("一")
        let b = addText("二")

        store.removeAll()

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL(for: a).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL(for: b).path))
    }

    /// 同一秒内连续存两段文本也不能互相覆盖：文件名会撞，但目录按 UUID 分开。
    func testConsecutiveAddsGetDistinctStorage() {
        let a = addText("一")
        let b = addText("二")

        XCTAssertNotEqual(a.storageID, b.storageID)
        XCTAssertEqual(try? String(contentsOf: store.fileURL(for: a), encoding: .utf8), "一")
        XCTAssertEqual(try? String(contentsOf: store.fileURL(for: b), encoding: .utf8), "二")
    }

    // MARK: - 过期清理

    /// 天数为 0 表示「一直保留」，不能删任何东西。
    func testRemoveExpiredIsNoOpWhenDaysIsZero() {
        seed([("旧.txt", "old", 999)])

        XCTAssertEqual(store.removeExpired(olderThan: 0), 0)
        XCTAssertEqual(store.items.count, 1)
    }

    /// 超过保留天数的条目连文件一起清掉，未超期的保留。
    func testRemoveExpiredDeletesOnlyOldItems() {
        let seeded = seed([("旧.txt", "old", 10), ("新.txt", "fresh", 2)])
        let oldFileURL = store.fileURL(for: seeded[0])

        XCTAssertEqual(store.removeExpired(olderThan: 7), 1)

        XCTAssertEqual(store.items.map(\.id), [seeded[1].id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldFileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL(for: seeded[1]).path))
    }

    /// 刚好落在保留窗口内侧的条目不该被删。
    func testRemoveExpiredKeepsItemsInsideWindow() {
        seed([("边界.txt", "edge", 6.9)])

        XCTAssertEqual(store.removeExpired(olderThan: 7), 0)
        XCTAssertEqual(store.items.count, 1)
    }

    /// 清理结果要落盘：重开 store 时被删掉的条目不能又回来。
    func testRemoveExpiredIsPersisted() {
        seed([("旧.txt", "old", 30), ("新.txt", "fresh", 1)])
        store.removeExpired(olderThan: 7)

        XCTAssertEqual(ShelfStore(rootDirectory: rootDirectory).items.count, 1)
    }

    func testRemoveExpiredOnEmptyStore() {
        XCTAssertEqual(store.removeExpired(olderThan: 7), 0)
    }

    // MARK: - 持久化

    /// index.json 落盘后，新开的 store 指向同一目录应能读回来。
    func testItemsSurviveReload() {
        addText("持久化", name: "笔记")
        let expected = store.items.map(\.id)

        let reloaded = ShelfStore(rootDirectory: rootDirectory)

        XCTAssertEqual(reloaded.items.map(\.id), expected)
        XCTAssertEqual(reloaded.textContent(of: reloaded.items[0]), "持久化")
    }

    /// 用户手动删掉暂存文件后，load 时要把这些死记录过滤掉。
    func testReloadDropsRecordsWithMissingFiles() throws {
        let ghost = addText("会被手动删掉")
        addText("还在")
        try FileManager.default.removeItem(
            at: rootDirectory.appendingPathComponent("Items", isDirectory: true)
                .appendingPathComponent(ghost.storageID, isDirectory: true)
        )

        let reloaded = ShelfStore(rootDirectory: rootDirectory)

        XCTAssertEqual(reloaded.items.count, 1)
        XCTAssertEqual(reloaded.textContent(of: reloaded.items[0]), "还在")
    }

    /// index.json 损坏时应当空手启动，而不是崩溃。
    func testCorruptIndexIsIgnored() throws {
        addText("x")
        try Data("{ 这不是合法 JSON".utf8)
            .write(to: rootDirectory.appendingPathComponent("index.json"))

        XCTAssertTrue(ShelfStore(rootDirectory: rootDirectory).items.isEmpty)
    }

    // MARK: - textContent

    /// 非文本条目不返回正文，调用方退回文件语义。
    func testTextContentIsNilForNonTextItems() {
        XCTAssertTrue(store.add(
            data: Data([0x89, 0x50, 0x4E, 0x47]), preferredName: "图片", type: .png
        ))
        XCTAssertNil(store.textContent(of: store.items[0]))
    }

    // MARK: - 工具

    /// 按指定的「存入时间」预置暂存内容：直接写文件和 index.json，
    /// 再让 store 走正常的加载流程读进来，不需要给生产代码开测试后门。
    @discardableResult
    private func seed(_ specs: [(name: String, text: String, daysAgo: Double)]) -> [ShelfItem] {
        let itemsDirectory = rootDirectory.appendingPathComponent("Items", isDirectory: true)
        var items: [ShelfItem] = []

        for spec in specs {
            let item = ShelfItem(
                fileName: spec.name,
                originalPath: nil,
                addedAt: Date().addingTimeInterval(-spec.daysAgo * 86_400),
                byteSize: Int64(spec.text.utf8.count),
                isDirectory: false,
                typeIdentifier: UTType.plainText.identifier
            )
            let directory = itemsDirectory.appendingPathComponent(item.storageID, isDirectory: true)
            try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try! Data(spec.text.utf8).write(to: directory.appendingPathComponent(spec.name))
            items.append(item)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try! encoder.encode(items).write(to: rootDirectory.appendingPathComponent("index.json"))

        store = ShelfStore(rootDirectory: rootDirectory)
        return items
    }
}
