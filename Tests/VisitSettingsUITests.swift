import XCTest

final class VisitSettingsUITests: XCTestCase {
    func testDefaultsAndMergeToggle() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Visit Recording"].waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(app.staticTexts.matching(identifier: "10 min").count, 2)
        XCTAssertTrue(app.staticTexts["15 min"].exists)
        XCTAssertTrue(app.staticTexts["100 m"].exists)
        XCTAssertTrue(app.staticTexts["Never"].exists)
        capture("Visit settings defaults portrait")
        let merge = app.switches["visitMergeConsecutive"]
        for _ in 0..<3 where !merge.isHittable { app.swipeUp() }
        XCTAssertTrue(merge.isHittable)
        XCTAssertEqual(merge.value as? String, "1")
        merge.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        let off = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '0'"), object: merge)
        XCTAssertEqual(XCTWaiter.wait(for: [off], timeout: 5), .completed)
        XCTAssertEqual(merge.value as? String, "0")
        merge.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        let on = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: merge)
        XCTAssertEqual(XCTWaiter.wait(for: [on], timeout: 5), .completed)
        XCTAssertEqual(merge.value as? String, "1")
        capture("Visit settings merge enabled")
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_Hant_HK"]
        app.launch()
        XCTAssertTrue(app.navigationBars["到訪記錄規則"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["15 分鐘"].exists)
        capture("Visit settings Traditional Chinese portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.width > app.frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 10), .completed)
        capture("Visit settings Traditional Chinese landscape")
        XCUIDevice.shared.orientation = .portrait
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
