import XCTest

final class ParkingPresentationUITests: XCTestCase {
    func testLongPressEdgeInsertsAndDragsNewVertexIncludingClosingEdge() {
        for closing in [false, true] {
            let app = XCUIApplication(bundleIdentifier: "com.gorilla.parking-presentation-checks")
            app.launchArguments = ["--edge-insert"]
            app.launch()
            let status = app.staticTexts["vertexDragResult"]
            XCTAssertTrue(status.waitForExistence(timeout: 10))
            expectation(for: NSPredicate(format: "label == 'READY'"), evaluatedWith: status)
            waitForExpectations(timeout: 10)
            let canvas = app.otherElements["vertexDragSurface"]
            let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: closing ? 0.25 : 0.5, dy: closing ? 0.5 : 0.3))
            start.tap()
            XCTAssertEqual(status.label, "READY", "A tap must not insert a vertex")
            let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
            start.press(forDuration: 0.7, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
            XCTAssertEqual(status.label, "insert=\(closing ? 4 : 1) count=5 moved=true others=true camera=true restored=true dragBegan=true")
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = closing ? "Closing edge split" : "New vertex inserted and dragged"
            shot.lifetime = .keepAlways
            add(shot)
        }
    }

    func testCancellingEdgeInsertionRestoresOriginalPolygon() {
        let app = XCUIApplication(bundleIdentifier: "com.gorilla.parking-presentation-checks")
        app.launchArguments = ["--edge-cancel"]
        app.launch()
        let status = app.staticTexts["vertexDragResult"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "label == 'READY'"), evaluatedWith: status)
        waitForExpectations(timeout: 10)
        let canvas = app.otherElements["vertexDragSurface"]
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).press(forDuration: 1)
        XCTAssertEqual(status.label, "cancelled count=4 uncommitted=true restored=true dragBegan=true")
    }
    func testToolbarActuallyShrinksDuringHoldAndQuickTap() {
        let app = XCUIApplication(bundleIdentifier: "com.gorilla.parking-presentation-checks")
        app.launchArguments = ["--toolbar-feedback"]
        app.launch()
        let status = app.staticTexts["toolbarFeedbackResult"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "label == 'READY'"), evaluatedWith: status)
        waitForExpectations(timeout: 10)
        app.buttons["boundaryDrawConfirm"].press(forDuration: 0.6)
        expectation(for: NSPredicate(format: "label BEGINSWITH 'READY2'"), evaluatedWith: status)
        waitForExpectations(timeout: 10)
        app.buttons["boundaryDrawConfirm"].tap()
        expectation(for: NSPredicate(format: "label BEGINSWITH 'count=2'"), evaluatedWith: status)
        waitForExpectations(timeout: 10)
        XCTAssertEqual(status.label, "count=2 holdPASS=true tapPASS=true")
    }
    func testBoundaryVertexDragDoesNotPanMapAndOtherTouchesStillPan() {
        let app = XCUIApplication(bundleIdentifier: "com.gorilla.parking-presentation-checks")
        app.launchArguments = ["--vertex-drag"]
        app.launch()
        let status = app.staticTexts["vertexDragResult"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "label == 'READY'"), evaluatedWith: status)
        waitForExpectations(timeout: 10)
        let canvas = app.otherElements["vertexDragSurface"]
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.3))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.4))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertTrue(status.label.contains("moves=1 moved=true others=true camera=true restored=true"), status.label)
        XCTAssertTrue(status.label.contains("dragBegan=true"), status.label)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Draggable boundary corners with white exterior arcs"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
            .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65)))
        expectation(for: NSPredicate(format: "label CONTAINS 'mapPan=true'"), evaluatedWith: status)
        waitForExpectations(timeout: 10)
    }
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
        app.buttons["Simulate Vertex Drag"].tap()
        XCTAssertFalse(app.buttons["boundaryDrawConfirm"].isEnabled)
        XCTAssertFalse(app.buttons["boundaryDrawUndo"].isEnabled)
        XCTAssertFalse(app.buttons["boundaryDrawAdd"].isEnabled)
        XCTAssertTrue(app.buttons["boundaryDrawCancel"].isEnabled)
        app.buttons["Finish Camera Flight"].tap()
        XCTAssertTrue(app.buttons["boundaryDrawConfirm"].isEnabled)
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
