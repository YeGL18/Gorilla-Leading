import XCTest

final class TripSummaryUITests: XCTestCase {
    func testNarrowAndWideSummaries() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Width 220"].waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Unclassified")).count, 3)
        for element in app.staticTexts.allElementsBoundByIndex where element.label.contains("Unclassified") {
            XCTAssertGreaterThan(element.frame.width, 0)
            XCTAssertLessThanOrEqual(element.frame.maxX, app.frame.maxX)
        }
        let portrait = XCTAttachment(screenshot: app.screenshot())
        portrait.name = "Trip summaries portrait"
        portrait.lifetime = .keepAlways
        add(portrait)
        XCUIDevice.shared.orientation = .landscapeLeft
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.width > app.frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 10), .completed)
        XCTAssertTrue(app.staticTexts["Width 220"].waitForExistence(timeout: 5))
        app.staticTexts["Width 220"].tap()
        let landscape = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        landscape.name = "Trip summaries landscape"
        landscape.lifetime = .keepAlways
        add(landscape)
        XCUIDevice.shared.orientation = .portrait
    }
}
