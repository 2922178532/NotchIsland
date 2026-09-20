import XCTest
@testable import NotchIsland

final class DragIntentSessionTests: XCTestCase {
    func testDragPromptStyleRawValuesRemainStable() {
        XCTAssertEqual(DragPromptStyle.notch.rawValue, "notch")
        XCTAssertEqual(DragPromptStyle.cursor.rawValue, "cursor")
        XCTAssertEqual(DragPromptStyle.allCases.map(\.title), ["刘海下拉色卡", "光标旁悬浮卡"])
    }

    @MainActor
    func testCursorCardAppearsBesidePointerAndStaysOnScreen() {
        let screen = CGRect(x: -1512, y: 200, width: 1512, height: 982)
        let middle = CGPoint(x: -700, y: 700)
        let normal = CursorDropPromptController.cardFrame(near: middle, in: screen)
        XCTAssertGreaterThan(normal.minX, middle.x)
        XCTAssertLessThan(normal.maxY, middle.y)
        XCTAssertFalse(normal.contains(middle), "悬浮卡不能盖住拖拽中的光标")
        XCTAssertTrue(screen.contains(normal))

        for pointer in [
            CGPoint(x: screen.minX, y: screen.minY),
            CGPoint(x: screen.maxX, y: screen.minY),
            CGPoint(x: screen.minX, y: screen.maxY),
            CGPoint(x: screen.maxX, y: screen.maxY),
        ] {
            XCTAssertTrue(screen.contains(CursorDropPromptController.cardFrame(near: pointer, in: screen)))
        }
    }

    func testHoldingFreshDragShowsPromptEvenWithoutFurtherMovement() {
        var session = DragIntentSession(changeCount: 10)
        XCTAssertFalse(session.update(changeCount: 11, hasSupportedContent: true, now: 1))
        XCTAssertFalse(session.update(changeCount: 11, hasSupportedContent: true, now: 1.2))
        XCTAssertTrue(session.update(changeCount: 11, hasSupportedContent: true, now: 1.36))
        XCTAssertTrue(session.update(changeCount: 11, hasSupportedContent: true, now: 60))
    }

    func testSelectionOrLongPressCannotReusePreviousDragContents() {
        var session = DragIntentSession(changeCount: 10)
        XCTAssertFalse(session.update(changeCount: 10, hasSupportedContent: true, now: 0))
        XCTAssertFalse(session.update(changeCount: 10, hasSupportedContent: true, now: 10))
    }

    func testReleaseDismissesAndNextPressNeedsFreshContents() {
        var session = DragIntentSession(changeCount: 0)
        _ = session.update(changeCount: 1, hasSupportedContent: true, now: 0)
        XCTAssertTrue(session.update(changeCount: 1, hasSupportedContent: true, now: 1))
        XCTAssertFalse(session.update(changeCount: 1, hasSupportedContent: true, didEndDragging: true, now: 2))
        XCTAssertFalse(session.update(changeCount: 1, hasSupportedContent: true, now: 3))
        XCTAssertFalse(session.update(changeCount: 1, hasSupportedContent: true, now: 4))
        XCTAssertFalse(session.update(changeCount: 2, hasSupportedContent: true, now: 5))
        XCTAssertTrue(session.update(changeCount: 2, hasSupportedContent: true, now: 6))
    }

    func testQuickDragDoesNotFlashPromptAfterRelease() {
        var session = DragIntentSession(changeCount: 0)
        _ = session.update(changeCount: 1, hasSupportedContent: true, now: 0)
        XCTAssertFalse(session.update(changeCount: 1, hasSupportedContent: true, didEndDragging: true, now: 0.1))
        XCTAssertFalse(session.update(changeCount: 1, hasSupportedContent: true, now: 1))
    }

    func testUnsupportedDragsNeverShowPrompt() {
        var session = DragIntentSession(changeCount: 0)
        _ = session.update(changeCount: 1, hasSupportedContent: false, now: 0)
        XCTAssertFalse(session.update(changeCount: 1, hasSupportedContent: false, now: 1))
    }

    func testHiddenIslandAndOutgoingDragConsumeChangesWithoutArming() {
        var session = DragIntentSession(changeCount: 0)
        XCTAssertFalse(session.update(changeCount: 1, hasSupportedContent: true, suppressed: true, now: 0))
        XCTAssertFalse(session.update(changeCount: 1, hasSupportedContent: true, now: 1))
        XCTAssertFalse(session.update(changeCount: 1, hasSupportedContent: true, now: 2))
    }

    func testEscapeOrManualCollapseCannotRearmTheSameDrag() {
        var session = DragIntentSession(changeCount: 0)
        _ = session.update(changeCount: 1, hasSupportedContent: true, now: 0)
        XCTAssertTrue(session.update(changeCount: 1, hasSupportedContent: true, now: 1))
        session.cancel()
        XCTAssertFalse(session.update(changeCount: 1, hasSupportedContent: true, now: 2))
    }

    func testIncrementalTypeDeclarationsDoNotRestartDelay() {
        var session = DragIntentSession(changeCount: 0)
        _ = session.update(changeCount: 1, hasSupportedContent: false, now: 0)
        _ = session.update(changeCount: 2, hasSupportedContent: true, now: 0.1)
        XCTAssertTrue(session.update(changeCount: 3, hasSupportedContent: true, now: 0.5))
    }

    func testSupportedDragPasteboardDoesNotRequirePressedMouseButton() {
        var session = DragIntentSession(changeCount: 0)
        _ = session.update(changeCount: 1, hasSupportedContent: true, now: 0)
        XCTAssertTrue(session.update(changeCount: 1, hasSupportedContent: true, now: 1))
    }

    @MainActor
    func testPromptExtendsBelowNotchAndExpandedTargetKeepsTheDropPoint() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let shelf = ShelfStore(rootDirectory: directory)
        // 覆盖内屏、负坐标副屏、无刘海模拟屏。
        for origin in [CGPoint.zero, CGPoint(x: -1512, y: 300)] {
            for physical in [true, false] {
                let screen = CGRect(origin: origin, size: CGSize(width: 1512, height: 982))
                let notch = CGRect(x: screen.midX - 125, y: screen.maxY - 37, width: 250, height: 37)
                let model = NotchModel(metrics: NotchMetrics(
                    notchRect: notch, screenFrame: screen, hasPhysicalNotch: physical
                ), shelf: shelf)
                model.setMode(.dragPrompt)
                let frame = model.windowFrame(for: .dragPrompt)
                let dropPoint = CGPoint(x: notch.midX, y: notch.minY - 35)
                XCTAssertEqual(frame.maxY, notch.maxY)
                XCTAssertEqual(frame.midX, notch.midX)
                XCTAssertTrue(frame.contains(model.activeHitRect))
                XCTAssertTrue(model.activeHitRect.contains(dropPoint), "无需顶到屏幕上沿即可命中")
                XCTAssertFalse(model.activeHitRect.contains(CGPoint(x: notch.minX + 5, y: dropPoint.y)),
                               "色块两侧的透明区域不应触发接收")
                model.setMode(.expanded)
                XCTAssertTrue(model.activeHitRect.contains(dropPoint), "展开后仍应接住原来的拖入位置")
                model.setMode(.collapsed)
                XCTAssertFalse(model.windowFrame(for: .collapsed).contains(dropPoint), "收起后释放屏幕区域")
            }
        }
    }
}
