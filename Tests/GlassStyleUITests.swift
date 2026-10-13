import XCTest

final class GlassStyleUITests: XCTestCase {
    private func launch(reset: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_HK"]
        if reset { app.launchArguments.append("reset-glass") }
        app.launch()
        XCTAssertTrue(app.staticTexts["glassMode"].waitForExistence(timeout: 10))
        return app
    }

    private func select(_ style: String, in app: XCUIApplication) {
        app.descendants(matching: .any)["Settings"].firstMatch.tap()
        app.buttons["glassStylePicker"].tap()
        app.buttons[style].firstMatch.tap()
        app.descendants(matching: .any)["Home"].firstMatch.tap()
    }

    private func setDarkKnight(_ enabled: Bool, in app: XCUIApplication) {
        app.descendants(matching: .any)["Settings"].firstMatch.tap()
        let toggle = app.switches["darkKnightToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if (toggle.value as? String == "1") != enabled {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        }
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", enabled ? "1" : "0"), object: toggle
        )
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, app.debugDescription)
        XCTAssertEqual(app.buttons["glassStylePicker"].isEnabled, !enabled)
        app.descendants(matching: .any)["Home"].firstMatch.tap()
    }

    private func screenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func checkLiveBarTint(_ expected: String, in app: XCUIApplication) {
        let audit = app.staticTexts["actualTabBarAppearance"]
        let match = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: audit)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: 5), .completed, "Actual live tint: \(audit.label)")
    }

    private func controlFrames(in app: XCUIApplication) -> [String: CGRect] {
        Dictionary(uniqueKeysWithValues: ["headingControl", "searchControl", "mapControl"].map {
            ($0, app.buttons[$0].frame)
        })
    }

    private func checkControlSizes(in app: XCUIApplication, baseline: [String: CGRect]) {
        for identifier in ["headingControl", "searchControl", "mapControl"] {
            let control = app.buttons[identifier]
            XCTAssertTrue(control.exists)
            guard let original = baseline[identifier] else {
                XCTFail("Missing original native size for \(identifier)")
                continue
            }
            XCTAssertEqual(control.frame.width, original.width, accuracy: 0.5)
            XCTAssertEqual(control.frame.height, original.height, accuracy: 0.5)
        }
        app.buttons["searchControl"].tap()
        XCTAssertTrue(app.buttons["Destination"].waitForExistence(timeout: 5))
        app.buttons["Destination"].tap()
    }

    func testClearAndDarkSwitchWithoutResettingControls() {
        let app = launch()
        XCTAssertEqual(app.staticTexts["glassMode"].label, "Dark")
        checkLiveBarTint("0.55/0.55", in: app)
        let baseline = controlFrames(in: app)
        app.buttons["headingControl"].tap()
        select("Clear", in: app)
        XCTAssertEqual(app.staticTexts["glassMode"].label, "Clear")
        checkLiveBarTint("0.00/0.00", in: app)
        XCTAssertEqual(app.staticTexts["controlTaps"].label, "Taps: 1")
        checkControlSizes(in: app, baseline: baseline)
        screenshot("Clear glass capsules, controls and tab bar", app: app)
        select("Dark Glass", in: app)
        XCTAssertEqual(app.staticTexts["glassMode"].label, "Dark")
        checkLiveBarTint("0.55/0.55", in: app)
        XCTAssertEqual(app.staticTexts["controlTaps"].label, "Taps: 1")
        checkControlSizes(in: app, baseline: baseline)
        screenshot("Dark glass capsules, controls and tab bar", app: app)
    }

    func testClearPreferenceSurvivesRelaunch() {
        var app = launch()
        select("Clear", in: app)
        app.terminate()
        app = launch(reset: false)
        XCTAssertEqual(app.staticTexts["glassMode"].label, "Clear")
        checkLiveBarTint("0.00/0.00", in: app)
    }

    func testSettingsColorsAreIndependentOfGlassStyle() {
        let app = launch()
        for darkAppearance in [false, true] {
            for darkGlass in [true, false] {
                app.descendants(matching: .any)["Settings"].firstMatch.tap()
                app.buttons["settingsAppearancePicker"].tap()
                app.buttons[darkAppearance ? "Dark" : "Light"].firstMatch.tap()
                app.buttons["glassStylePicker"].tap()
                app.buttons[darkGlass ? "Dark Glass" : "Clear"].firstMatch.tap()
                let baseline = app.staticTexts["normalSettingsColors"]
                XCTAssertTrue(baseline.waitForExistence(timeout: 5))
                let scheme = darkAppearance ? "dark/1.00/" : "light/0.00/"
                let baselineReady = XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "label BEGINSWITH %@", scheme), object: baseline
                )
                XCTAssertEqual(XCTWaiter.wait(for: [baselineReady], timeout: 5), .completed, baseline.label)
                let expected = baseline.label
                let audit = app.staticTexts["settingsColorAudit"]
                let match = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: audit)
                XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: 5), .completed, audit.label)
                XCTAssertTrue(app.buttons["settingsPreview"].isHittable)
                screenshot("Settings \(darkAppearance ? "dark" : "light") with \(darkGlass ? "dark" : "clear") glass", app: app)
                app.descendants(matching: .any)["Home"].firstMatch.tap()
            }
        }
    }

    func testNativeCompassFollowsGlassStyle() {
        let app = launch()
        let audit = app.staticTexts["actualCompassAppearance"]
        func check(_ expected: String) {
            let match = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: audit)
            XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: 5), .completed, audit.label)
        }
        check("2/matched/44/44")
        select("Clear", in: app)
        check("0/matched/44/44")
        select("Dark Glass", in: app)
        check("2/matched/44/44")
        app.terminate()
        let restored = launch(reset: false)
        let restoredAudit = restored.staticTexts["actualCompassAppearance"]
        let match = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "2/matched/44/44"), object: restoredAudit)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: 5), .completed, restoredAudit.label)
    }

    func testDarkKnightRestoresClearGlassAfterRelaunch() {
        var app = launch()
        select("Clear", in: app)
        let baseline = controlFrames(in: app)
        setDarkKnight(true, in: app)
        XCTAssertEqual(app.staticTexts["glassMode"].label, "Dark")
        XCTAssertEqual(app.staticTexts["glassPreference"].label, "Clear")
        checkLiveBarTint("0.55/0.55", in: app)
        app.terminate()
        app = launch(reset: false)
        XCTAssertEqual(app.staticTexts["glassMode"].label, "Dark")
        XCTAssertEqual(app.staticTexts["glassPreference"].label, "Clear")
        checkLiveBarTint("0.55/0.55", in: app)
        setDarkKnight(false, in: app)
        XCTAssertEqual(app.staticTexts["glassMode"].label, "Clear")
        XCTAssertEqual(app.staticTexts["glassPreference"].label, "Clear")
        checkLiveBarTint("0.00/0.00", in: app)
        checkControlSizes(in: app, baseline: baseline)
    }

    func testDarkKnightPreservesExistingDarkPreference() {
        let app = launch()
        setDarkKnight(true, in: app)
        XCTAssertEqual(app.staticTexts["glassPreference"].label, "Dark")
        checkLiveBarTint("0.55/0.55", in: app)
        setDarkKnight(false, in: app)
        XCTAssertEqual(app.staticTexts["glassMode"].label, "Dark")
        XCTAssertEqual(app.staticTexts["glassPreference"].label, "Dark")
        checkLiveBarTint("0.55/0.55", in: app)
    }

    func testInstalledAppNativeToolbarSearchGlass() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "com.gorilla.translation")
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_HK",
                               "-capsuleDarkGlassEnabled", "YES", "-launchAnimationEnabled", "NO"]
        app.launch()
        let mapButton = app.buttons["Switch Map Mode"].firstMatch
        XCTAssertTrue(mapButton.waitForExistence(timeout: 10))
        mapButton.tap()
        screenshot("Installed Duo app native dark toolbar", app: app)
        let search = app.buttons["Search Destinations"].firstMatch
        if !search.exists {
            let overflow = app.buttons["More"].firstMatch
            XCTAssertTrue(overflow.waitForExistence(timeout: 5), app.debugDescription)
            overflow.tap()
        }
        XCTAssertTrue(search.waitForExistence(timeout: 5), app.debugDescription)
        search.tap()
        XCTAssertTrue(app.buttons["Add Destination"].waitForExistence(timeout: 5))
        app.terminate()
    }
}
