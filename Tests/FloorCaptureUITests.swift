import XCTest

final class FloorCaptureUITests: XCTestCase {
    @MainActor
    func testParkingQuestionDefersWhileSamplingAndRequiresExplicitConfirmation() {
        let app = XCUIApplication(bundleIdentifier: "com.gorilla.floor-capture-checks")
        app.launchArguments = ["--parking-stop"]
        app.launch()
        XCTAssertTrue(app.buttons["continueAltitudeSampling"].waitForExistence(timeout: 10))
        app.buttons["continueAltitudeSampling"].tap()
        XCTAssertFalse(app.buttons["confirmVehicleParked"].exists)
        let sampling = app.staticTexts["samplingStatus"]
        XCTAssertTrue(sampling.label.hasPrefix("true|"))
        XCTAssertTrue(app.buttons["confirmVehicleParked"].waitForExistence(timeout: 13),
                      "Not parked must ask again without stopping sampling")
        XCTAssertTrue(sampling.label.hasPrefix("true|"))
        app.buttons["confirmVehicleParked"].tap()
        XCTAssertTrue(sampling.label.hasPrefix("false|"))
    }

    @MainActor
    func testAdjustmentSavesBeforeTickAndTickIsReachable() {
        let app = XCUIApplication(bundleIdentifier: "com.gorilla.floor-capture-checks")
        app.launch()
        let status = app.staticTexts["captureStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        app.buttons["captureFloorUp"].tap()
        XCTAssertEqual(status.label, "-2|true|false")
        app.buttons["captureFloorDown"].tap()
        XCTAssertEqual(status.label, "-3|true|false")
        app.buttons["confirmCaptureFloor"].tap()
        XCTAssertEqual(status.label, "-3|true|true")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    func testAutomaticTickDoesNotBecomeHumanTraining() {
        let app = XCUIApplication(bundleIdentifier: "com.gorilla.floor-capture-checks")
        app.launch()
        let status = app.staticTexts["captureStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "label == %@", "-3|false|true"), evaluatedWith: status)
        waitForExpectations(timeout: 18)
        XCTAssertFalse(app.buttons["captureFloorUp"].isEnabled)
    }

    @MainActor
    func testSwipeAdjustsAndRestartsIdleCountdown() {
        let app = XCUIApplication(bundleIdentifier: "com.gorilla.floor-capture-checks")
        app.launch()
        XCTAssertTrue(app.staticTexts["captureStatus"].waitForExistence(timeout: 10))
        let floor = app.staticTexts["captureFloor"]
        let center = floor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.press(forDuration: 0.15, thenDragTo: center.withOffset(CGVector(dx: 0, dy: -30)))
        XCTAssertEqual(app.staticTexts["captureStatus"].label, "-2|true|false")
        app.buttons["confirmCaptureFloor"].tap()
        XCTAssertEqual(app.staticTexts["captureStatus"].label, "-2|true|true")
    }
}
