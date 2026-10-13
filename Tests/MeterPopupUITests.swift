import XCTest

final class MeterPopupUITests: XCTestCase {
    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    private func launch(_ arguments: [String], orientation: UIDeviceOrientation = .portrait) -> XCUIApplication {
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication()
        app.launchArguments = arguments + ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        XCTAssertTrue(app.buttons["経路案内"].waitForExistence(timeout: 10))
        if orientation == .landscapeLeft {
            XCTAssertGreaterThan(app.windows.firstMatch.frame.width, app.windows.firstMatch.frame.height)
        }
        return app
    }

    private func checkBounds(_ app: XCUIApplication, left: Bool = false, upper: Bool = false) {
        let navigation = app.buttons["経路案内"]
        let screen = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(navigation.frame.minX, screen.minX)
        XCTAssertLessThanOrEqual(navigation.frame.maxX, left ? screen.midX : screen.maxX)
        XCTAssertLessThanOrEqual(navigation.frame.maxY, upper ? screen.midY : screen.maxY)
        XCTAssertGreaterThanOrEqual(navigation.frame.height, 44)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
        navigation.tap()
        XCTAssertTrue(app.staticTexts["Actions: 1"].waitForExistence(timeout: 3))
    }

    func testLightPortrait() { checkBounds(launch([])) }
    func testDarkGlassOnLightAppearance() { checkBounds(launch(["--glass-dark"])) }
    func testDarkLandscape() { checkBounds(launch(["--dark"], orientation: .landscapeLeft)) }
    func testHingeUpperHalf() { checkBounds(launch(["--upper", "--glass-dark"]), upper: true) }
    func testHingeLeftHalf() { checkBounds(launch(["--left", "--glass-dark"], orientation: .landscapeLeft), left: true) }
    func testNearbyNotice() { checkBounds(launch(["--notice", "--dark"])) }
}
