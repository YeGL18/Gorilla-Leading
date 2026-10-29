import XCTest

final class ParkingRecordUITests: XCTestCase {
    func testSwipeSeparatesRecordAndMakesIndependentMarker() {
        let app = launch()
        let row = app.buttons["parkingRecord-00000000-0000-0000-0000-000000000001"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.swipeLeft()
        XCTAssertTrue(app.buttons["separateParkingRecord"].waitForExistence(timeout: 5))
        app.buttons["separateParkingRecord"].tap()
        XCTAssertTrue(app.buttons["History"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["groupCount"].label, "2")
        XCTAssertEqual(app.staticTexts["recordCount"].label, "50")
    }

    func testSwipeDeletesOnlySelectedRecord() {
        let app = launch()
        let row = app.buttons["parkingRecord-00000000-0000-0000-0000-000000000001"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.swipeLeft()
        app.buttons["deleteParkingRecord"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.firstMatch.buttons.matching(NSPredicate(format: "label IN %@", ["Delete", "刪除"])).firstMatch.tap()
        app.buttons["Close"].tap()
        XCTAssertEqual(app.staticTexts["recordCount"].label, "49")
    }

    func testTimeAdjustmentRepeatsAndStopsOnRelease() {
        let app = XCUIApplication()
        app.launchArguments = ["--repeat-control"]
        app.launch()
        let plus = app.buttons["repeatPlus"]
        XCTAssertTrue(plus.waitForExistence(timeout: 10))
        plus.tap()
        XCTAssertEqual(app.staticTexts["repeatValue"].label, "1")
        plus.press(forDuration: 3.5)
        let heldValue = Int(app.staticTexts["repeatValue"].label)!
        XCTAssertGreaterThan(heldValue, 10)
        XCTAssertEqual(app.staticTexts["repeatSaves"].label, "2")
        app.buttons["repeatMinus"].tap()
        XCTAssertEqual(Int(app.staticTexts["repeatValue"].label), heldValue - 1)
        XCTAssertEqual(app.staticTexts["repeatSaves"].label, "3")
    }
    private func launch(language: String = "en", landscape: Bool = false) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", "en_HK"]
        app.launch()
        XCTAssertTrue(app.buttons["History"].waitForExistence(timeout: 10))
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        let orientation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = app.frame
            return landscape ? frame.width > frame.height : frame.height > frame.width
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [orientation], timeout: 5), .completed)
        app.buttons["History"].tap()
        return app
    }

    private func longList(landscape: Bool) {
        let app = launch(landscape: landscape)
        let lastID = "parkingRecord-00000000-0000-0000-0000-000000000050"
        let last = app.buttons[lastID]
        guard app.buttons["parkingRecord-00000000-0000-0000-0000-000000000001"].waitForExistence(timeout: 10) else {
            XCTFail("History did not open after the orientation change")
            return
        }
        let lists = app.collectionViews
        guard lists.count > 0 else { XCTFail("History list is missing"); return }
        let list = lists.element(boundBy: lists.count - 1)
        for _ in 0..<30 {
            if last.isHittable { break }
            list.swipeUp()
        }
        XCTAssertTrue(last.isHittable)
        list.swipeUp()
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = landscape ? "Landscape parking history" : "Portrait parking history"
        shot.lifetime = .keepAlways
        add(shot)
        last.tap()
        XCTAssertTrue(app.buttons["History"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["selectedRecord"].label, "00000000-0000-0000-0000-000000000050")
    }

    func testPortraitHistory() { longList(landscape: false) }
    func testLandscapeHistory() { longList(landscape: true) }

    func testBatchFloorCorrection() {
        let app = launch()
        XCTAssertTrue(app.buttons["selectParkingRecords"].waitForExistence(timeout: 10))
        app.buttons["selectParkingRecords"].tap()
        for number in 1...2 {
            let id = String(format: "parkingRecord-00000000-0000-0000-0000-%012d", number)
            app.descendants(matching: .any).matching(identifier: id).firstMatch.tap()
        }
        app.buttons["correctSelectedFloors"].tap()
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 10))
        app.pickerWheels.firstMatch.adjust(toPickerWheelValue: "B2")
        XCTAssertEqual(app.pickerWheels.firstMatch.value as? String, "B2")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Confirm Correction"].waitForExistence(timeout: 5))
        app.buttons["Confirm Correction"].tap()
        app.buttons["Close"].tap()
        XCTAssertEqual(app.staticTexts["groupCount"].label, "2")
        XCTAssertEqual(app.staticTexts["confirmedCount"].label, "2")
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }
}
