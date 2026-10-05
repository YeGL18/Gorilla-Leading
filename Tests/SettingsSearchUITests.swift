import XCTest

final class SettingsSearchUITests: XCTestCase {
    private func launch(language: String = "en", landscape: Bool = false, setOrientation: Bool = true) -> XCUIApplication {
        if setOrientation { XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", "en_HK"]
        app.launch()
        if setOrientation { XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait }
        return app
    }

    private func checkLongList(landscape: Bool, verifyRotation: Bool = true) {
        let app = launch(landscape: landscape, setOrientation: verifyRotation)
        let orientation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = app.windows.firstMatch.frame
            return landscape ? frame.width > frame.height : frame.height > frame.width
        }, object: nil)
        if verifyRotation {
            XCTAssertEqual(XCTWaiter.wait(for: [orientation], timeout: 5), .completed,
                           "The app must actually rotate before verifying its layout")
        }
        app.buttons["Search Places"].tap()
        let category = app.descendants(matching: .any)["My Destinations (50)"].firstMatch
        XCTAssertTrue(category.waitForExistence(timeout: 5), app.debugDescription)
        category.tap()
        let last = app.buttons["Destination 50"]
        XCTAssertTrue(app.buttons["Destination 01"].waitForExistence(timeout: 8))
        let list = app.scrollViews.firstMatch
        for _ in 0..<25 {
            if last.isHittable { break }
            if list.exists {
                list.swipeUp()
            } else {
                let window = app.windows.firstMatch
                window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                    .press(forDuration: 0.01, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
            }
        }
        XCTAssertTrue(last.isHittable, "All fifty items must be reachable by scrolling")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = landscape ? "Landscape scroll reaches item 50" : "Portrait scroll reaches item 50"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        last.tap()
        XCTAssertTrue(app.staticTexts["selectionResult"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["selectionResult"].label, "50")
        XCUIDevice.shared.orientation = .portrait
    }

    func testPortraitLongList() { checkLongList(landscape: false) }
    func testLandscapeLongList() { checkLongList(landscape: true) }
    func testDuoLongList() { checkLongList(landscape: false, verifyRotation: false) }

    func testNestedMenuWithoutSheet() {
        let app = launch()
        app.buttons["Search Places"].tap()
        let category = app.descendants(matching: .any)["My Destinations (50)"].firstMatch
        XCTAssertTrue(category.waitForExistence(timeout: 5), app.debugDescription)
        category.tap()
        XCTAssertTrue(app.buttons["Destination 01"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Destinations"].exists)
        app.buttons["Destination 01"].tap()
        XCTAssertEqual(app.staticTexts["selectionResult"].label, "1")
    }

    func testJapaneseSoundSettings() {
        let app = launch(language: "ja")
        XCTAssertTrue(app.staticTexts["起動サウンド"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["滞在／運転サウンド"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Japanese native sound settings"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
