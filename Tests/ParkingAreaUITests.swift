import XCTest

final class ParkingAreaUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_HK"]
        app.launch()
        return app
    }

    func testSingleTapAndLongPressDrag() {
        let app = launch()
        let marker = app.descendants(matching: .any)["parkingMarker"].firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 10))
        let from = marker.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let to = from.withOffset(CGVector(dx: 55, dy: 35))
        from.press(forDuration: 0.5, thenDragTo: to)
        XCTAssertEqual(app.staticTexts["openCount"].label, "0", "Holding and dragging must not open a capsule")
        XCTAssertEqual(app.staticTexts["moveCount"].label, "1")
        marker.tap()
        XCTAssertEqual(app.staticTexts["openCount"].label, "1", "A single tap must still open a capsule")
    }

    func testBoundaryVerticesSaveAndReset() {
        let app = launch()
        app.buttons["Boundary"].tap()
        XCTAssertTrue(app.buttons["boundaryAdd"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["boundaryCount"].label, "4 Vertices")
        app.buttons["boundaryAdd"].tap()
        XCTAssertEqual(app.staticTexts["boundaryCount"].label, "5 Vertices")
        app.buttons["boundaryRemove"].tap()
        XCTAssertEqual(app.staticTexts["boundaryCount"].label, "4 Vertices")
        let handles = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'boundaryVertex-'"))
        XCTAssertTrue(handles.firstMatch.waitForExistence(timeout: 5))
        let handle = handles.firstMatch
        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.6, thenDragTo: start.withOffset(CGVector(dx: 12, dy: 10)))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Rounded editable parking boundary"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Save"].tap()
        XCTAssertEqual(app.staticTexts["savedVertexCount"].label, "4")
        app.buttons["Boundary"].tap()
        app.buttons["Restore Automatic Circle"].tap()
        let restore = app.buttons["Restore"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        restore.tap()
        let reset = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == '0'"),
                                              object: app.staticTexts["savedVertexCount"])
        XCTAssertEqual(XCTWaiter.wait(for: [reset], timeout: 5), .completed)
    }

    func testManualMerge() {
        let app = launch()
        app.buttons["Merge Areas"].tap()
        let target = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'mergeLot-'" )).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        target.tap()
        app.alerts.buttons["Merge"].tap()
        let merged = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == '1'"), object: app.staticTexts["lotCount"])
        XCTAssertEqual(XCTWaiter.wait(for: [merged], timeout: 5), .completed)
    }
}
