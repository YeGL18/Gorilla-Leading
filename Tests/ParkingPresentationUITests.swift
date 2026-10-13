import XCTest

final class ParkingPresentationUITests: XCTestCase {
    func testParkingDragRejectsMeterSelectionThroughReleaseAndAllowsNextTouch() {
        let app = XCUIApplication()
        app.launchArguments = ["--drag-selection", "-AppleLanguages", "(en)"]
        app.launch()
        let result = app.staticTexts["dragSelectionResult"]
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        let passed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'PASS'"), object: result)
        XCTAssertEqual(XCTWaiter.wait(for: [passed], timeout: 10), .completed, result.label)
    }

    func testBoundaryCameraAndToolbar() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)"]
        app.launch()
        let result = app.staticTexts["boundaryCameraResult"]
        let passed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'PASS'"), object: result)
        XCTAssertEqual(XCTWaiter.wait(for: [passed], timeout: 15), .completed)
        app.buttons["Draw Boundary"].tap()
        XCTAssertTrue(app.buttons["boundaryDrawCancel"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["boundaryDrawCancel"].isEnabled)
        XCTAssertFalse(app.buttons["boundaryDrawUndo"].isEnabled)
        XCTAssertFalse(app.buttons["boundaryDrawAdd"].isEnabled)
        XCTAssertFalse(app.buttons["boundaryDrawConfirm"].isEnabled)
        app.buttons["Finish Camera Flight"].tap()
        XCTAssertTrue(app.buttons["boundaryDrawUndo"].isEnabled)
        XCTAssertTrue(app.buttons["boundaryDrawAdd"].isEnabled)
        XCTAssertTrue(app.buttons["boundaryDrawConfirm"].isEnabled)
        XCTAssertTrue(app.buttons["boundaryDrawConfirm"].isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Boundary toolbar using the address capsule glass"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["boundaryDrawCancel"].tap()
        XCTAssertTrue(app.staticTexts["Address"].waitForExistence(timeout: 5))
    }

    func testEntryCameraContinuesAfterLayoutPermissionReset() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)"]
        app.launch()
        let result = app.staticTexts["entryCameraResult"]
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        let passed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'PASS'"), object: result)
        XCTAssertEqual(XCTWaiter.wait(for: [passed], timeout: 15), .completed, result.label)
    }

    func testDrivingGPSCannotMoveCameraBeforeInitialFlight() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)"]
        app.launch()
        let result = app.staticTexts["initialDrivingCameraResult"]
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        let passed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'PASS'"), object: result)
        XCTAssertEqual(XCTWaiter.wait(for: [passed], timeout: 15), .completed, "\(result.label) \(result.value ?? "")")
    }

    func testPortraitButtonsClearDrawingCapsuleAndInvalidHint() {
        let app = XCUIApplication()
        app.launchArguments = ["--toolbar-clearance", "-AppleLanguages", "(en)"]
        app.launch()
        let mapButton = app.buttons["previewMapMode"]
        XCTAssertTrue(mapButton.waitForExistence(timeout: 10))
        let originalY = mapButton.frame.minY
        app.buttons["Draw Boundary"].tap()
        let capsule = app.otherElements["previewCapsule"]
        XCTAssertTrue(app.buttons["boundaryDrawCancel"].waitForExistence(timeout: 5))
        XCTAssertTrue(capsule.exists, app.debugDescription)
        XCTAssertLessThan(mapButton.frame.minY, originalY - 10)
        XCTAssertLessThanOrEqual(mapButton.frame.maxY, capsule.frame.minY)
        for id in ["previewHeading", "previewSearch", "previewMapMode"] { XCTAssertTrue(app.buttons[id].isHittable) }
        app.buttons["Show Invalid Boundary"].tap()
        XCTAssertTrue(app.staticTexts["Invalid boundary"].waitForExistence(timeout: 5))
        XCTAssertLessThan(mapButton.frame.minY, originalY - 35)
        XCTAssertLessThanOrEqual(mapButton.frame.maxY, capsule.frame.minY)
        app.buttons["boundaryDrawCancel"].tap()
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in abs(mapButton.frame.minY - originalY) < 2 }, object: mapButton)
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 5), .completed)
    }

    func testMergeColorsAndSelection() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)"]
        app.launch()
        app.buttons["Merge Areas"].tap()
        let target = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'mergeLot-'" )).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Merge sheet neutral text and secondary details"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        target.tap()
        let confirm = app.alerts.buttons["Merge"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
        confirm.tap()
        let merged = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == '1'"), object: app.staticTexts["presentationLotCount"])
        XCTAssertEqual(XCTWaiter.wait(for: [merged], timeout: 5), .completed)
    }
}
