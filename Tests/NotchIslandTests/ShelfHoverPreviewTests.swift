import AppKit
import XCTest
@testable import NotchIsland

final class ShelfHoverPreviewTests: XCTestCase {
    @MainActor
    func testNativePreviewWindowHasVisibleSizeForEveryCategory() {
        _ = NSApplication.shared
        let panel = ShelfPreviewPanel()
        defer { panel.close() }
        for (name, width) in [("note.txt", 400.0), ("photo.png", 480.0), ("report.docx", 400.0), ("archive.zip", 400.0)] {
            let item = ShelfItem(fileName: name, originalPath: nil, byteSize: 100, isDirectory: false, typeIdentifier: nil)
            // 加载中和加载完成都必须有尺寸，避免出现“visible=true 但窗口为 0×0”。
            for content in [ShelfPreviewContent(item: item), ShelfPreviewContent(
                item: item, text: "第一行预览文本\n第二行预览文本", image: NSImage(size: CGSize(width: 960, height: 600))
            )] {
                panel.setContent(content)
                XCTAssertEqual(panel.frame.width, width, accuracy: 1)
                XCTAssertGreaterThan(panel.frame.height, 80)
                XCTAssertLessThan(panel.frame.height, 600)
            }
        }
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertTrue(panel.ignoresMouseEvents)
    }

    @MainActor
    func testUnclippedBackgroundCannotClaimNeighboringCards() {
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 612, height: 100))
        container.clipsToBounds = true
        let card = ShelfHoverAnchorView(frame: CGRect(x: 88, y: 0, width: 74, height: 100))
        card.clipsToBounds = false
        container.addSubview(card)
        XCTAssertEqual(card.visibleCardRect, card.bounds)
        XCTAssertFalse(card.visibleCardRect.contains(CGPoint(x: 100, y: 50)))

        card.frame.origin.x = 590
        XCTAssertEqual(card.visibleCardRect.width, 22)
        card.frame.origin.x = 700
        XCTAssertTrue(card.visibleCardRect.isEmpty)
    }

    func testStationaryPointerShowsAfterDelayAndStaysVisible() {
        var session = ShelfHoverSession()
        let id = UUID()
        XCTAssertNil(session.update(target: id, now: 0))
        XCTAssertNil(session.update(target: id, now: 0.2))
        XCTAssertEqual(session.update(target: id, now: 0.31), id)
        XCTAssertEqual(session.update(target: id, now: 30), id)
    }

    func testSwitchingCardsRequiresFreshDwell() {
        var session = ShelfHoverSession()
        let a = UUID(), b = UUID()
        _ = session.update(target: a, now: 0)
        XCTAssertEqual(session.update(target: a, now: 1), a)
        XCTAssertNil(session.update(target: b, now: 1.1))
        XCTAssertEqual(session.update(target: b, now: 1.5), b)
        XCTAssertNil(session.update(target: a, now: 1.6))
    }

    func testLeavingBeforeDelayNeverShowsOldTargetAndCanReenter() {
        var session = ShelfHoverSession()
        let id = UUID()
        _ = session.update(target: id, now: 0)
        XCTAssertNil(session.update(target: nil, now: 0.2))
        XCTAssertNil(session.update(target: nil, now: 3))
        XCTAssertNil(session.update(target: id, now: 4))
        XCTAssertEqual(session.update(target: id, now: 4.4), id)
    }

    func testDraggingSuppressesPreviewAndRestartsDwellOnRelease() {
        var session = ShelfHoverSession()
        let id = UUID()
        _ = session.update(target: id, now: 0)
        XCTAssertEqual(session.update(target: id, now: 1), id)
        XCTAssertNil(session.update(target: id, now: 2, blocked: true))
        XCTAssertNil(session.update(target: id, now: 4, blocked: true))
        XCTAssertNil(session.update(target: id, now: 5))
        XCTAssertEqual(session.update(target: id, now: 5.4), id)
    }

    func testScrollOrCollapseCancelsPendingPreview() {
        var session = ShelfHoverSession()
        let id = UUID()
        _ = session.update(target: id, now: 0)
        session.reset()
        XCTAssertNil(session.update(target: id, now: 1))
        XCTAssertEqual(session.update(target: id, now: 1.4), id)
    }

    @MainActor
    func testPreviewFitsExternalScreenAndStaysBelowCards() {
        let screen = CGRect(x: -1920, y: 200, width: 1920, height: 1055)
        let parent = CGRect(x: -1250, y: 900, width: 640, height: 320)
        for x: CGFloat in [-1900, -960, -20] {
            let frame = ShelfHoverPreviewController.previewFrame(
                size: CGSize(width: 480, height: 400),
                anchor: CGRect(x: x, y: 980, width: 74, height: 100),
                parent: parent, screen: screen
            )
            XCTAssertTrue(screen.contains(frame))
            XCTAssertLessThan(frame.maxY, parent.minY)
        }
    }

    @MainActor
    func testOversizePreviewIsClampedToSmallScreen() {
        let screen = CGRect(x: 100, y: -600, width: 350, height: 500)
        let frame = ShelfHoverPreviewController.previewFrame(
            size: CGSize(width: 480, height: 600),
            anchor: CGRect(x: 200, y: -200, width: 74, height: 100),
            parent: CGRect(x: 100, y: -400, width: 350, height: 300), screen: screen
        )
        XCTAssertTrue(screen.contains(frame))
    }

    func testCardAndLargePreviewUseDifferentCacheEntries() {
        let item = ShelfItem(fileName: "preview.png", originalPath: nil, byteSize: 0, isDirectory: false, typeIdentifier: nil)
        let card = ThumbnailLoader.cacheKey(for: item, size: CGSize(width: 128, height: 128), scale: 2)
        let preview = ThumbnailLoader.cacheKey(for: item, size: CGSize(width: 480, height: 320), scale: 2)
        let otherScale = ThumbnailLoader.cacheKey(for: item, size: CGSize(width: 480, height: 320), scale: 1)
        XCTAssertNotEqual(card, preview)
        XCTAssertNotEqual(preview, otherScale)
    }
}
