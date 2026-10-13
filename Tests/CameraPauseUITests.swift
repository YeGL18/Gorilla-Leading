import XCTest

final class CameraPauseUITests: XCTestCase {
    func testPauseKeepsOneFrameAndResumeCanPauseAgain() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 10))
        let road = app.staticTexts["CENTERED ADDRESS"]
        XCTAssertTrue(road.exists)
        XCTAssertEqual(road.frame.midX, app.frame.midX, accuracy: 2)
        app.buttons["Pause"].tap()
        let counter = app.staticTexts["freezeCount"]
        let first = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == '1'"), object: counter)
        XCTAssertEqual(XCTWaiter.wait(for: [first], timeout: 5), .completed)
        XCTAssertTrue(app.images["pausedCameraFrame"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Frozen preview, transparent camera glass and centered activity address"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Resume"].tap()
        app.buttons["Pause"].tap()
        let second = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == '2'"), object: counter)
        XCTAssertEqual(XCTWaiter.wait(for: [second], timeout: 5), .completed)
    }
}
