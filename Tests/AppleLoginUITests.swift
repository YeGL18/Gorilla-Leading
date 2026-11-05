import XCTest

final class AppleLoginUITests: XCTestCase {
    func testNativeAppleButtonInBothThemesAndUnauthenticatedLinkIsDisabled() {
        for arguments in [[], ["--dark"], ["--link"]] as [[String]] {
            let app = XCUIApplication()
            app.launchArguments = arguments
            app.launch()
            let button = app.buttons["community.apple.signIn"]
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            if arguments.contains("--link") {
                XCTAssertFalse(button.isEnabled)
                XCTAssertFalse(app.textFields["電郵地址"].exists)
                XCTAssertTrue(app.staticTexts["連結後可用 Apple 登入目前帳戶，保留已綁定車牌及對話。"].exists)
            } else {
                XCTAssertTrue(button.isEnabled)
                XCTAssertTrue(app.textFields["電郵地址"].exists)
            }
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = arguments.contains("--link") ? "Link existing account" : arguments.contains("--dark") ? "Apple login dark" : "Apple login light"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.terminate()
        }
    }
}
