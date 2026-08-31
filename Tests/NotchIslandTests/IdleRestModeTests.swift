import XCTest
@testable import NotchIsland

/// 空闲展示模式的取值映射与持久化字符串。
final class IdleRestModeTests: XCTestCase {

    func testMapsToNotchMode() {
        XCTAssertEqual(IdleRestMode.collapsed.notchMode, .collapsed)
        XCTAssertEqual(IdleRestMode.hovering.notchMode, .hovering)
    }

    /// rawValue 会写进 UserDefaults，改动会让老用户的设置失效。
    func testRawValuesAreStable() {
        XCTAssertEqual(IdleRestMode.collapsed.rawValue, "collapsed")
        XCTAssertEqual(IdleRestMode.hovering.rawValue, "hovering")
    }

    func testAllCasesAreSelectable() {
        XCTAssertEqual(IdleRestMode.allCases.count, 2)
        for mode in IdleRestMode.allCases {
            XCTAssertFalse(mode.title.isEmpty)
            XCTAssertEqual(IdleRestMode(rawValue: mode.rawValue), mode)
        }
    }

    /// 空闲态只能是收起或悬停，绝不能是展开——否则面板会永久挡住屏幕顶部。
    func testNeverRestsExpanded() {
        for mode in IdleRestMode.allCases {
            XCTAssertNotEqual(mode.notchMode, .expanded)
        }
    }

    func testUnknownRawValueIsRejected() {
        XCTAssertNil(IdleRestMode(rawValue: "expanded"))
        XCTAssertNil(IdleRestMode(rawValue: ""))
    }
}
