import XCTest

final class DuoSettingsMapUITests: XCTestCase {
    func testProductionMapSurvivesSettingsRoundTrips() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication(bundleIdentifier: "com.gorilla.translation")
        app.launchArguments = ["--map-camera-checks", "-AppleLanguages", "(en)", "-AppleLocale", "en_HK"]
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .portrait
        XCUIDevice.shared.orientation = .landscapeRight
        let mode = app.buttons["Switch Map Mode"].firstMatch
        XCTAssertTrue(mode.waitForExistence(timeout: 15))
        // Duo's AX app frame remains in physical display coordinates after rotation.
        // This native tab exists only in the production inner-landscape layout.
        XCTAssertTrue(app.buttons["Gorilla"].firstMatch.waitForExistence(timeout: 10))
        mode.tap()
        let map = app.descendants(matching: .any)["mapCameraChecks"].firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 20))
        let settled = NSPredicate(format: "value CONTAINS 'flying=0' AND value CONTAINS 'renderer='")
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: settled, evaluatedWith: map)], timeout: 25), .completed)
        let initial = try XCTUnwrap(map.value as? String)
        let renderer = try XCTUnwrap(initial.components(separatedBy: "renderer=").last)
        for index in 0..<3 {
            app.buttons["Settings"].firstMatch.tap()
            let settingsBar = app.navigationBars["Settings"].firstMatch
            XCTAssertTrue(settingsBar.waitForExistence(timeout: 10))
            XCTAssertTrue(map.exists)
            XCTAssertTrue((map.value as? String ?? "").contains("renderer=\(renderer)"))
            XCTAssertTrue((map.value as? String ?? "").contains("flying=0"))
            app.buttons["Home"].firstMatch.tap()
            XCTAssertTrue(mode.waitForExistence(timeout: 10))
            XCTAssertTrue(mode.isHittable)
            XCTAssertTrue((map.value as? String ?? "").contains("renderer=\(renderer)"))
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "Native Home bars after Settings \(index)"
            shot.lifetime = .keepAlways
            add(shot)
        }
        print("Duo AX app frame: \(app.frame); map frame: \(map.frame)")
        let start = map.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.40))
        let end = map.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.50))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.5)
        let manual = NSPredicate(format: "value CONTAINS 'manual=1'")
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: manual, evaluatedWith: map)], timeout: 2), .completed,
                       "Single-finger map control survives the handoff")
    }
}
