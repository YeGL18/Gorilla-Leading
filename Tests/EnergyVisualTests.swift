import XCTest

final class EnergyVisualTests: XCTestCase {
    func testTimelineEntranceFramesAndActualBlendedEndpoint() {
        let app = XCUIApplication()
        app.launchArguments = ["--time-entrance"]
        app.launch()
        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 10))
        for name in ["Start", "Middle", "End"] {
            app.buttons[name].tap()
            let frame = XCTAttachment(screenshot: app.screenshot())
            frame.name = "Timeline entrance \(name)"
            frame.lifetime = .keepAlways
            add(frame)
        }
        XCTAssertEqual(app.staticTexts["phaseProgress"].label, "0.600")
        app.buttons["Replay"].tap()
        let arrived = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == '0.600'"),
                                                object: app.staticTexts["phaseProgress"])
        XCTAssertEqual(XCTWaiter.wait(for: [arrived], timeout: 5), .completed)
        let final = XCTAttachment(screenshot: app.screenshot())
        final.name = "Timeline entrance completed without palette snap"
        final.lifetime = .keepAlways
        add(final)
    }

    func testSoftenedEdgesAndToggle() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["edgeToggle"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 4)
        let softened = XCTAttachment(screenshot: app.screenshot())
        softened.name = "Single-map softened edges"
        softened.lifetime = .keepAlways
        add(softened)
        // MapKit exposes its outer view as Other and its inner renderer as Map.
        let map = app.descendants(matching: .any).matching(identifier: "energy-map").firstMatch
        XCTAssertTrue(map.exists)
        let beforePan = map.value as? String
        map.swipeLeft()
        XCTAssertTrue(waitForMapChange(map, from: beforePan), "Soft edges cannot block one-finger panning")
        let beforeZoom = map.value as? String
        map.pinch(withScale: 1.5, velocity: 1)
        XCTAssertTrue(waitForMapChange(map, from: beforeZoom), "Soft edges cannot block native map gestures")
        app.buttons["edgeToggle"].tap()
        let original = XCTAttachment(screenshot: app.screenshot())
        original.name = "Same map without softening"
        original.lifetime = .keepAlways
        add(original)
        app.buttons["edgeToggle"].tap()
        XCTAssertTrue(app.buttons["edgeToggle"].exists)
    }

    private func waitForMapChange(_ map: XCUIElement, from oldValue: String?) -> Bool {
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (map.value as? String) != oldValue
        }, object: nil)
        return XCTWaiter.wait(for: [changed], timeout: 4) == .completed
    }
}
