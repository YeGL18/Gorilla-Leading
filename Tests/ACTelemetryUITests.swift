import XCTest

final class ACTelemetryUITests: XCTestCase {
    func testDirectUDPAndDashboard() {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.staticTexts["42"].waitForExistence(timeout: 5))
        app.buttons["computerTelemetrySwitch"].tap()
        XCTAssertTrue(app.staticTexts["GPS · 等待電腦遙測"].waitForExistence(timeout: 5))
        app.buttons["Start Mock"].tap()
        XCTAssertTrue(app.staticTexts["123"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["BMW M3 E30 · Monza · GP"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["6500"].exists)
        XCTAssertTrue(app.staticTexts["3"].exists)
        XCTAssertTrue(app.staticTexts["1:23.456"].exists)
        XCTAssertTrue(app.staticTexts["65%"].exists)
        XCTAssertTrue(app.staticTexts["20%"].exists)
        XCTAssertLessThan(app.staticTexts["20%"].frame.midX, app.staticTexts["65%"].frame.midX)
        XCTAssertFalse(app.staticTexts["speedDigits"].frame.intersects(app.staticTexts["65%"].frame))
        XCTAssertTrue(app.staticTexts["0 – 30,000 RPM"].exists)
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 5))
        app.buttons["computerTelemetrySwitch"].press(forDuration: 0.6)
        XCTAssertTrue(app.textFields["acHost"].waitForExistence(timeout: 5))
        app.buttons["關閉"].tap()
        XCTAssertTrue(app.staticTexts["123"].waitForExistence(timeout: 5))
        capture(app, "AC Portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        let rotated = expectation(for: NSPredicate { _, _ in
            app.frame.width > app.frame.height
        }, evaluatedWith: app)
        wait(for: [rotated], timeout: 5)
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(app.staticTexts["123"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.frame.contains(app.staticTexts["6500"].frame))
        XCTAssertTrue(app.frame.contains(app.staticTexts["65%"].frame))
        XCTAssertLessThan(app.staticTexts["20%"].frame.midX, app.staticTexts["65%"].frame.midX)
        XCTAssertFalse(app.staticTexts["speedDigits"].frame.intersects(app.staticTexts["6500"].frame))
        XCTAssertFalse(app.staticTexts["speedDigits"].frame.intersects(app.staticTexts["65%"].frame))
        capture(app, "AC Landscape")
        app.buttons["Stop Mock"].tap()
        XCTAssertTrue(app.staticTexts["GPS · 等待電腦遙測"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["42"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["123"].exists)
        XCTAssertFalse(app.staticTexts["6500"].exists)
        capture(app, "AC Disconnected")
        app.buttons["Start Mock"].tap()
        XCTAssertTrue(app.staticTexts["123"].waitForExistence(timeout: 10))
        app.buttons["computerTelemetrySwitch"].tap()
        XCTAssertTrue(app.staticTexts["42"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["GPS · 等待電腦遙測"].exists)
        XCUIDevice.shared.orientation = .portrait
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
