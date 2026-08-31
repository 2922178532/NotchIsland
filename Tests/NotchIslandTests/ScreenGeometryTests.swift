import XCTest
@testable import NotchIsland

/// 刘海几何计算的测试。用真实机型的数值构造输入，不依赖 `NSScreen`。
final class ScreenGeometryTests: XCTestCase {

    /// 14 吋 MacBook Pro 的实际数值：1512×982 逻辑分辨率，安全区 37pt，
    /// 左右可用区域各 631pt，反推出的刘海宽度为 250pt。
    func testDerivesNotchWidthFromAuxiliaryAreas() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

        let notch = ScreenGeometry.physicalNotchRect(
            screenFrame: screen,
            safeAreaTop: 37,
            auxiliaryLeftWidth: 631,
            auxiliaryRightWidth: 631
        )

        XCTAssertEqual(notch?.width, 250)
        XCTAssertEqual(notch?.height, 37)
        XCTAssertEqual(notch?.midX, screen.midX, "刘海应水平居中")
        XCTAssertEqual(notch?.maxY, screen.maxY, "刘海上沿应贴住屏幕顶部")
    }

    /// 副屏原点不在 (0,0)，刘海矩形必须落在该屏自己的坐标里。
    func testNotchRectUsesScreenOriginNotGlobalZero() {
        let screen = CGRect(x: -1728, y: 300, width: 1728, height: 1117)

        let notch = ScreenGeometry.physicalNotchRect(
            screenFrame: screen,
            safeAreaTop: 38,
            auxiliaryLeftWidth: 754,
            auxiliaryRightWidth: 754
        )

        XCTAssertEqual(notch?.width, 220)
        XCTAssertEqual(notch?.minX, screen.midX - 110)
        XCTAssertEqual(notch?.minY, screen.maxY - 38)
    }

    /// 左右可用区域不对称时（理论上不该发生）仍按居中处理，宽度取差值。
    func testHandlesAsymmetricAuxiliaryAreas() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

        let notch = ScreenGeometry.physicalNotchRect(
            screenFrame: screen,
            safeAreaTop: 30,
            auxiliaryLeftWidth: 400,
            auxiliaryRightWidth: 500
        )

        XCTAssertEqual(notch?.width, 100)
        XCTAssertEqual(notch?.midX, 500)
    }

    // MARK: - 判定为「无物理刘海」的情况

    /// 没有安全区就没有刘海，外接显示器走这条路。
    func testReturnsNilWithoutSafeArea() {
        XCTAssertNil(ScreenGeometry.physicalNotchRect(
            screenFrame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            safeAreaTop: 0,
            auxiliaryLeftWidth: 1280,
            auxiliaryRightWidth: 1280
        ))
    }

    /// 负的安全区是异常值，同样按无刘海处理。
    func testReturnsNilForNegativeSafeArea() {
        XCTAssertNil(ScreenGeometry.physicalNotchRect(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaTop: -10,
            auxiliaryLeftWidth: 631,
            auxiliaryRightWidth: 631
        ))
    }

    /// 左右区域加起来铺满整屏时，反推宽度为 0，不能当成一个零宽刘海。
    func testReturnsNilWhenDerivedWidthIsDegenerate() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

        XCTAssertNil(ScreenGeometry.physicalNotchRect(
            screenFrame: screen, safeAreaTop: 30,
            auxiliaryLeftWidth: 500, auxiliaryRightWidth: 500
        ), "宽度 0 应判定为无刘海")

        XCTAssertNil(ScreenGeometry.physicalNotchRect(
            screenFrame: screen, safeAreaTop: 30,
            auxiliaryLeftWidth: 500, auxiliaryRightWidth: 499.5
        ), "宽度 0.5（≤1）应判定为无刘海")

        XCTAssertNil(ScreenGeometry.physicalNotchRect(
            screenFrame: screen, safeAreaTop: 30,
            auxiliaryLeftWidth: 600, auxiliaryRightWidth: 600
        ), "宽度为负应判定为无刘海")
    }

    // MARK: - 模拟岛

    /// 常规外接屏：宽度取 200pt 上限，高度等于菜单栏高度，顶部居中。
    func testSimulatedRectIsCenteredAtTop() {
        let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)

        let rect = ScreenGeometry.simulatedNotchRect(screenFrame: screen, menuBarHeight: 25)

        XCTAssertEqual(rect.width, ScreenGeometry.simulatedNotchWidth)
        XCTAssertEqual(rect.height, 25)
        XCTAssertEqual(rect.midX, screen.midX)
        XCTAssertEqual(rect.maxY, screen.maxY)
    }

    /// 窄屏上宽度被压到屏幕宽度的 40%，不会超出 200pt 的默认值。
    func testSimulatedWidthIsClampedOnNarrowScreens() {
        let screen = CGRect(x: 0, y: 0, width: 400, height: 300)

        let rect = ScreenGeometry.simulatedNotchRect(screenFrame: screen, menuBarHeight: 24)

        XCTAssertEqual(rect.width, 160, "400 × 0.4 = 160，小于 200pt 上限")
        XCTAssertEqual(rect.midX, screen.midX)
    }

    /// 菜单栏高度异常偏小时兜底到最小高度，否则岛会薄到点不到。
    func testSimulatedHeightHasFloor() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        let rect = ScreenGeometry.simulatedNotchRect(screenFrame: screen, menuBarHeight: 0)

        XCTAssertEqual(rect.height, ScreenGeometry.minimumNotchHeight)
        XCTAssertEqual(rect.maxY, screen.maxY)
    }

    /// 菜单栏比兜底值高时按实际高度走。
    func testSimulatedHeightFollowsMenuBarWhenTaller() {
        let rect = ScreenGeometry.simulatedNotchRect(
            screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            menuBarHeight: 37
        )

        XCTAssertEqual(rect.height, 37)
    }

    /// 副屏坐标下模拟岛也要落在该屏内。
    func testSimulatedRectRespectsScreenOrigin() {
        let screen = CGRect(x: 1512, y: -200, width: 1920, height: 1080)

        let rect = ScreenGeometry.simulatedNotchRect(screenFrame: screen, menuBarHeight: 25)

        XCTAssertEqual(rect.maxY, screen.maxY)
        XCTAssertTrue(screen.contains(rect), "模拟岛应完全落在所属屏幕内")
    }
}
