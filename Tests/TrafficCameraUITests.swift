import XCTest

final class TrafficCameraUITests: XCTestCase {
    func testCameraSpeechChoicesDiscloseRelevantOptions() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.tabBars.buttons["Settings"].tap()
        let format = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Spoken Alert")).firstMatch
        XCTAssertTrue(format.waitForExistence(timeout: 5))
        format.tap()
        app.buttons["Two beeps only"].tap()
        XCTAssertFalse(app.switches["Say a slowdown warning only when speeding"].exists)
        XCTAssertFalse(app.switches["Announce red-light cameras"].exists)
        format.tap()
        app.buttons["Beeps + 80"].tap()
        XCTAssertFalse(app.switches["Say a slowdown warning only when speeding"].exists)
        XCTAssertTrue(app.switches["Announce red-light cameras"].exists)
        format.tap()
        app.buttons["Beeps + Short speed limit"].tap()
        XCTAssertTrue(app.switches["Say a slowdown warning only when speeding"].exists)
        capture(app, "Configurable camera speech and overspeed-only warning")
        format.tap()
        app.buttons["Beeps + Speed limit and unit"].tap()
    }

    func testVoiceSettingsEntryExplainsDestination() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.tabBars.buttons["Settings"].tap()
        XCTAssertFalse(app.buttons["openCameraVoiceSettings"].exists)
        app.buttons["Voices & Downloads"].tap()
        XCTAssertTrue(app.staticTexts["Download voices"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["openCameraVoiceSettings"].exists)
        capture(app, "Voice download guide without misleading Settings shortcut")
    }

    func testGPSCarouselUsesDifferentTapCounts() {
        let app = XCUIApplication()
        app.launchArguments = ["--gps-carousel", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let gps = app.staticTexts["GPS"].firstMatch
        XCTAssertTrue(gps.waitForExistence(timeout: 5))
        gps.tap()
        XCTAssertFalse(app.staticTexts["Map browsing"].exists)
        Thread.sleep(forTimeInterval: 0.7) // End the single-tap recognition window before a separate double tap.
        gps.doubleTap()
        XCTAssertTrue(app.staticTexts["Map browsing"].waitForExistence(timeout: 5))
        app.buttons["Red-light and speed cameras"].tap()
        let details = app.staticTexts["Map Details"].firstMatch
        XCTAssertTrue(details.waitForExistence(timeout: 15))
        details.tap()
        XCTAssertTrue(app.staticTexts["Map browsing"].waitForExistence(timeout: 5))
        capture(app, "Map Details single tap anchored menu")
    }

    func testRedLightCameraHidesSpeedReference() {
        let app = XCUIApplication()
        app.launchArguments = ["--red-light", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Red-light camera"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Road speed reference"].exists)
        XCTAssertFalse(app.buttons["Speed limit source"].exists)
        capture(app, "Red-light camera without road speed reference")
    }

    func testDataSourcesAndTermsNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--dark"]
        app.launch()
        app.tabBars.buttons["Settings"].tap()
        let sources = app.buttons["Data sources and terms"]
        XCTAssertTrue(sources.waitForExistence(timeout: 5))
        sources.tap()
        XCTAssertTrue(app.staticTexts["Data attribution"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(app.buttons["Meter locations and occupancy data"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(app.buttons["Sunrise-Sunset.org"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(app.buttons["Government open data terms"].waitForExistence(timeout: 5))
        capture(app, "Data attribution and government terms")
    }

    func testParkingResetStaysAnchoredToPencil() {
        checkParkingReset(dark: false)
    }

    func testDarkParkingResetUsesSolidRedButton() {
        checkParkingReset(dark: true)
    }

    private func checkParkingReset(dark: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["--edit-point", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + (dark ? ["--dark"] : [])
        app.launch()
        let pencil = app.buttons["parkingPointEdit"]
        XCTAssertTrue(pencil.waitForExistence(timeout: 10))
        let anchor = pencil.frame
        pencil.tap()
        let option = app.buttons["Restore Automatic Circle"]
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
        let restore = app.buttons["Restore"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.5)
        let cancel = app.buttons["Cancel"]
        XCTAssertLessThan(abs(restore.frame.midX - cancel.frame.midX), 3)
        XCTAssertLessThan(abs(restore.frame.midY - anchor.midY), 240)
        XCTAssertLessThan(restore.frame.maxY, app.frame.height * 0.8)
        capture(app, dark ? "Dark parking reset solid red button" : "Parking reset confirmation anchored to pencil")
        app.buttons["Cancel"].tap()
        XCTAssertEqual(app.staticTexts["restoreCount"].label, "Restores 0")
        pencil.tap()
        option.tap()
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        restore.tap()
        XCTAssertEqual(app.staticTexts["restoreCount"].label, "Restores 1")
    }

    func testFullMeterInventoryRemainsResponsive() {
        let app = XCUIApplication()
        app.launchArguments = ["--meters"]
        app.launch()
        let bays = app.staticTexts["meterBays"]
        XCTAssertTrue(bays.waitForExistence(timeout: 10))
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Bays 24000'"), object: bays)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 10), .completed)
        let count = Int(app.staticTexts["meterAnnotations"].label.replacingOccurrences(of: "Annotations ", with: "")) ?? 24000
        XCTAssertGreaterThan(count, 0)
        XCTAssertLessThan(count, 500)
        app.buttons["Ping 0"].tap()
        XCTAssertTrue(app.buttons["Ping 1"].waitForExistence(timeout: 3))
        capture(app, "Full Hong Kong meter overview - bounded annotations")
        app.buttons["Zoom meters"].tap()
        let zoomed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in bays.label != "Bays 24000" && bays.label != "Bays 0" }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [zoomed], timeout: 5), .completed)
        app.buttons["Ping 1"].tap()
        XCTAssertTrue(app.buttons["Ping 2"].exists)
    }

    func testDarkAnchoredThreeOptionMenu() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--dark"]
        app.launch()
        let gps = app.staticTexts["GPS"]
        XCTAssertTrue(gps.waitForExistence(timeout: 10))
        gps.doubleTap()
        let heading = app.staticTexts["Map browsing"]
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Red-light and speed cameras"].exists)
        XCTAssertTrue(app.buttons["All Hong Kong parking meters"].exists)
        let landmarks = app.buttons["Hong Kong landmarks"]
        XCTAssertTrue(landmarks.exists)
        XCTAssertLessThan(heading.frame.midY, app.frame.midY)
        capture(app, "Dark GPS anchored three-option menu")
        landmarks.tap()
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Markers 0'"), object: app.staticTexts["cameraCount"])
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)
    }

    func testNearbyAndOverviewCameraLayers() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let count = app.staticTexts["cameraCount"]
        XCTAssertTrue(count.waitForExistence(timeout: 10))
        app.buttons["Nearby cameras"].tap()
        let nearby = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let value = Int(count.label.replacingOccurrences(of: "Markers ", with: "")) ?? -1
            return value > 0 && value < 394
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [nearby], timeout: 5), .completed)
        capture(app, "Nearby cameras within 2 km")
        app.buttons["Meter overview"].tap()
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Markers 0'"), object: count)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)
        app.buttons["All cameras"].tap()
        let all = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Markers 394'"), object: count)
        XCTAssertEqual(XCTWaiter.wait(for: [all], timeout: 5), .completed)
    }

    func testCameraDetailUnknownAndMatchedLimit() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let marker = app.descendants(matching: .any).matching(identifier: "trafficCamera.sec-1").firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 10))
        marker.tap()
        XCTAssertTrue(app.staticTexts["Road speed reference"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Close"].exists)
        XCTAssertFalse(app.buttons["關閉"].exists)
        capture(app, "Camera detail - compact card without close button")
        app.terminate()
        app.launchArguments.append("--unknown")
        app.launch()
        XCTAssertTrue(app.staticTexts["Default speed limit (road data not matched)"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["50"].exists)
        capture(app, "Camera detail - unresolved road")
        app.terminate()
        app.launchArguments.removeAll { $0 == "--unknown" }
        app.launchArguments.append("--matched")
        app.launch()
        XCTAssertTrue(app.staticTexts["Road speed reference"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Not confirmed"].exists)
        capture(app, "Camera detail - official road speed reference")
        XCUIDevice.shared.orientation = .landscapeLeft
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.frame.width > app.frame.height }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed)
        Thread.sleep(forTimeInterval: 1)
        capture(app, "Camera detail - landscape")
        XCUIDevice.shared.orientation = .portrait
    }

    func testOfficialMarkersAndSettingsToggle() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let count = app.staticTexts["cameraCount"]
        XCTAssertTrue(count.waitForExistence(timeout: 10))
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Markers 394'"), object: count)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 10), .completed)
        capture(app, "Official camera map markers")
        app.tabBars.buttons["Settings"].tap()
        let toggle = app.switches["Camera markers and approach alerts"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        capture(app, "Camera settings and attribution")
        app.buttons["Preview camera alert"].tap()
        toggle.coordinate(withNormalizedOffset: .init(dx: 0.92, dy: 0.5)).tap()
        app.tabBars.buttons["Map"].tap()
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Markers 0'"), object: count)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 5), .completed)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name.replacingOccurrences(of: " ", with: "_") + ".png")
        try? app.screenshot().pngRepresentation.write(to: url)
        print("CAMERA_SCREENSHOT: \(url.path)")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
