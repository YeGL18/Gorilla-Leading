import XCTest

final class ParkingRecognitionUITests: XCTestCase {
    func testDialogDarkAndLightActions() {
        for light in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = light ? ["--light"] : []
            app.launch()
            let edit = app.alerts.buttons["編輯"].firstMatch
            XCTAssertTrue(edit.waitForExistence(timeout: 8))
            XCTAssertEqual(app.alerts.count, 1, "Parking information must use a native system alert")
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = light ? "Light parking information" : "Dark parking information"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            edit.tap()
            XCTAssertEqual(app.staticTexts["result"].label, "edit")
            XCTAssertTrue(app.alerts.firstMatch.waitForNonExistence(timeout: 5))
            app.buttons["Reopen"].tap()
            app.alerts.buttons["清除車位"].firstMatch.tap()
            XCTAssertEqual(app.staticTexts["result"].label, "clear")
            XCTAssertTrue(app.alerts.firstMatch.waitForNonExistence(timeout: 5))
            app.buttons["Reopen"].tap()
            app.alerts.buttons["確定"].firstMatch.tap()
            XCTAssertEqual(app.staticTexts["result"].label, "confirm")
            app.terminate()
        }
    }
}
