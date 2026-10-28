import XCTest

final class ACTelemetryUITests: XCTestCase {
    func testLightTransparentStandardMapAndSatelliteText() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--light", "--transparent"]
        app.launch()
        XCTAssertTrue(app.staticTexts["speedDigits"].waitForExistence(timeout: 10))
        let toggle = app.buttons["speedMapPresentationSwitch"]
        toggle.tap()
        let map = app.descendants(matching: .any)["fixtureSpeedMap"].firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 5))
        XCTAssertEqual(map.value as? String, "standard")
        assertCards(app, horizontal: false)
        capture(app, "Light Transparent Standard Map Gray Text")
        toggle.tap()
        XCTAssertEqual(map.value as? String, "satellite")
        assertCards(app, horizontal: false)
        capture(app, "Light Transparent Satellite Unchanged Text")
    }

    func testGlassVariantsAcrossAppearances() {
        XCUIDevice.shared.orientation = .portrait
        for arguments in [["--transparent", "--light"], ["--transparent"], ["--light"], []] {
            let app = XCUIApplication()
            app.launchArguments = arguments
            app.launch()
            XCTAssertTrue(app.staticTexts["speedDigits"].waitForExistence(timeout: 10))
            assertCards(app, horizontal: false)
            let appearance = arguments.contains("--light") ? "Light" : "Dark"
            let glass = arguments.contains("--transparent") ? "Transparent" : "Dark Glass"
            capture(app, "\(appearance) Appearance \(glass) Cards")
            app.terminate()
        }
    }

    func testRecentGForcePeakSurvivesLowerForcesAndResetsAfterQuiet() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--recent-peak-trace"]
        app.launch()
        XCTAssertTrue(app.buttons["computerTelemetrySwitch"].waitForExistence(timeout: 10))
        app.buttons["computerTelemetrySwitch"].tap()
        app.buttons["Start Mock"].tap()
        let peak = app.staticTexts["gForceRecentPeak"]
        let firstPeak = expectation(for: NSPredicate { _, _ in peak.label == "0.50 G" }, evaluatedWith: app)
        wait(for: [firstPeak], timeout: 8)
        let force = app.staticTexts["gForceMagnitude"]
        let lowerForce = expectation(for: NSPredicate { _, _ in force.label == "0.20 G" }, evaluatedWith: app)
        wait(for: [lowerForce], timeout: 6)
        XCTAssertEqual(peak.label, "0.50 G")
        let reset = expectation(for: NSPredicate { _, _ in peak.label == "0.00 G" }, evaluatedWith: app)
        wait(for: [reset], timeout: 16)
        XCTAssertEqual(force.label, "0.01 G")
        capture(app, "Recent G-force peak reset after ten quiet seconds")
    }

    func testGForceTrailWithMovingTelemetry() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--trail-trace"]
        app.launch()
        XCTAssertTrue(app.buttons["computerTelemetrySwitch"].waitForExistence(timeout: 10))
        app.buttons["computerTelemetrySwitch"].tap()
        app.buttons["Start Mock"].tap()
        let force = app.staticTexts["gForceMagnitude"]
        let receiving = expectation(for: NSPredicate { _, _ in force.label == "0.70 G" }, evaluatedWith: app)
        wait(for: [receiving], timeout: 10)
        Thread.sleep(forTimeInterval: 1.5)
        capture(app, "G-force fading curved trail")
        XCTAssertTrue(app.descendants(matching: .any)["gForcePlot"].firstMatch.exists)
        app.buttons["computerTelemetrySwitch"].tap()
        XCTAssertEqual(app.staticTexts["speedDigits"].label, "42")
    }

    func testRestoredGForceParallaxFitsCards() {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["--gforce"]
        app.launch()
        XCTAssertTrue(app.buttons["computerTelemetrySwitch"].waitForExistence(timeout: 5))
        app.buttons["computerTelemetrySwitch"].tap()
        app.buttons["Start Mock"].tap()
        XCTAssertTrue(app.staticTexts["加速中"].waitForExistence(timeout: 10))
        for landscape in [false, true] {
            if landscape {
                XCUIDevice.shared.orientation = .landscapeLeft
                waitForLandscape(app)
            }
            assertCards(app, horizontal: landscape, centeredSpeed: false)
            let digits = app.staticTexts["speedDigits"]
            let unit = app.staticTexts["speedUnit"]
            let card = app.descendants(matching: .any)["speedCenterCard"].firstMatch
            XCTAssertEqual(digits.label, "123")
            XCTAssertTrue(card.frame.contains(digits.frame))
            XCTAssertLessThanOrEqual(digits.frame.maxY, unit.frame.minY)
            XCTAssertGreaterThan(abs(digits.frame.midX - unit.frame.midX), 5)
            XCTAssertLessThan(abs(digits.frame.midX - unit.frame.midX), 40)
            capture(app, landscape ? "Restored G Parallax Landscape" : "Restored G Parallax Portrait")
        }
        XCUIDevice.shared.orientation = .portrait
    }

    func testSpeedUnitSettingConvertsGPSAndGameAndPersists() {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["--units"]
        app.launch()
        XCTAssertTrue(app.staticTexts["speedDigits"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["speedDigits"].label, "42")
        XCTAssertEqual(app.staticTexts["speedUnit"].label, "km/h")
        app.buttons["Units"].tap()
        app.buttons["speedUnitPicker"].tap()
        app.buttons["mph"].tap()
        app.buttons["closeUnitSettings"].tap()
        XCTAssertEqual(app.staticTexts["speedDigits"].label, "26")
        XCTAssertEqual(app.staticTexts["speedUnit"].label, "mph")
        capture(app, "GPS mph")
        app.buttons["computerTelemetrySwitch"].tap()
        app.buttons["Start Mock"].tap()
        let game = expectation(for: NSPredicate { _, _ in
            app.staticTexts["speedDigits"].label == "76"
        }, evaluatedWith: app)
        wait(for: [game], timeout: 10)
        XCTAssertEqual(app.staticTexts["speedUnit"].label, "mph")
        capture(app, "AC mph")
        app.terminate()
        app.launchArguments = ["--units", "--preserve-units", "--rolling"]
        app.launch()
        XCTAssertTrue(app.staticTexts["speedDigits"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["speedDigits"].label, "26")
        XCTAssertEqual(app.staticTexts["speedUnit"].label, "mph")
        app.buttons["Units"].tap()
        app.buttons["speedUnitPicker"].tap()
        app.buttons["km/h"].tap()
        app.buttons["closeUnitSettings"].tap()
        XCTAssertEqual(app.staticTexts["speedDigits"].label, "42")
        XCTAssertEqual(app.staticTexts["speedUnit"].label, "km/h")
    }

    func testPredictionCardDoesNotExpandToScreenHeight() {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["--prediction"]
        app.launch()
        let card = app.descendants(matching: .any)["tripPredictionCard"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertLessThan(card.frame.height, app.frame.height * 0.85)
        XCTAssertGreaterThan(card.frame.minY, 40)
        XCTAssertLessThanOrEqual(card.frame.width, 560)
        XCTAssertTrue(app.buttons["暫未出發"].exists)
        capture(app, "Prediction Card Without Extra Blue Frame")
    }

    func testLiveActivitySpeedUnitsDecodeOlderPayloads() throws {
        let data = Data(#"{"state":"driving","startDate":0,"speedKmh":97}"#.utf8)
        var state = try JSONDecoder().decode(GorillaActivityAttributes.ContentState.self, from: data)
        XCTAssertEqual(state.speedUnitSymbol, "km/h")
        XCTAssertEqual(state.speedDisplay, "97")
        state.speedUnitRaw = "mph"
        XCTAssertEqual(state.speedDisplay, "60")
        state.speedKmh = 96
        state.speedKmhExact = 96.6
        XCTAssertEqual(state.speedDisplay, "60")
        let restored = try JSONDecoder().decode(GorillaActivityAttributes.ContentState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(restored, state)
        state.speedUnitRaw = "invalid"
        XCTAssertEqual(state.speedUnitSymbol, "km/h")
    }

    func testThreeCardsAndAutomaticTelemetry() {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["--reference"]
        app.launch()
        XCTAssertTrue(app.staticTexts["speedDigits"].waitForExistence(timeout: 5))
        assertCards(app, horizontal: false)
        XCTAssertEqual(app.staticTexts["speedDigits"].label, "42")
        XCTAssertFalse(app.scrollViews.firstMatch.exists)
        let mapSwitch = app.buttons["speedMapPresentationSwitch"]
        let computer = app.buttons["computerTelemetrySwitch"]
        XCTAssertEqual(mapSwitch.frame.width, computer.frame.width, accuracy: 1)
        let reference = app.buttons["homeControlReference"]
        XCTAssertEqual(mapSwitch.frame.width, reference.frame.width, accuracy: 1)
        XCTAssertEqual(mapSwitch.frame.height, reference.frame.height, accuracy: 1)
        reference.tap()
        capture(app, "Three Cards Portrait GPS")
        let lastCard = app.descendants(matching: .any)["gForceCircleCard"].firstMatch
        XCTAssertGreaterThan(lastCard.frame.maxY, computer.frame.minY)
        mapSwitch.tap()
        let map = app.descendants(matching: .any)["fixtureSpeedMap"].firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 5))
        XCTAssertEqual(map.value as? String, "standard")
        mapSwitch.tap()
        XCTAssertEqual(map.value as? String, "satellite")
        capture(app, "Speed Satellite Map")
        mapSwitch.tap()
        XCTAssertFalse(map.exists)
        // Card taps do not hide instruments. Only the surrounding blank area does.
        app.staticTexts["currentActionForce"].tap()
        XCTAssertTrue(lastCard.exists)
        let gap = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: lastCard.frame.midX, dy: lastCard.frame.minY - 6))
        gap.tap()
        XCTAssertFalse(lastCard.exists)
        XCTAssertFalse(computer.exists)
        XCTAssertTrue(app.staticTexts["speedDigits"].exists)
        XCTAssertTrue(app.staticTexts["speedUnit"].exists)
        capture(app, "Speed Only")
        gap.tap()
        XCTAssertTrue(lastCard.waitForExistence(timeout: 5))
        app.buttons["computerTelemetrySwitch"].tap()
        app.buttons["Start Mock"].tap()
        let force = app.staticTexts["currentActionForce"]
        XCTAssertTrue(force.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["加速中"].waitForExistence(timeout: 10))
        XCTAssertEqual(force.label, "0.40")
        XCTAssertEqual(app.staticTexts["currentActionPeak"].label, "0.40")
        XCTAssertEqual(app.staticTexts["currentActionStatus"].label, "進行中")
        XCTAssertFalse(app.staticTexts["currentActionScore"].exists)
        XCTAssertEqual(app.staticTexts["gForceMagnitude"].label, "0.49 G")
        XCTAssertEqual(app.staticTexts["speedDigits"].label, "123")
        XCTAssertTrue(app.webViews.firstMatch.exists)
        capture(app, "Three Cards Portrait AC")
        app.buttons["acTelemetryDetails"].tap()
        XCTAssertTrue(app.staticTexts["6500"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["65%"].exists)
        XCTAssertTrue(app.staticTexts["20%"].exists)
        app.buttons["關閉"].tap()
        app.buttons["computerTelemetrySwitch"].press(forDuration: 0.6)
        XCTAssertTrue(app.textFields["acHost"].waitForExistence(timeout: 5))
        app.buttons["關閉"].tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForLandscape(app)
        assertCards(app, horizontal: true)
        capture(app, "Three Cards Landscape AC")
        app.buttons["Stop Mock"].tap()
        let fallback = expectation(for: NSPredicate { _, _ in
            app.staticTexts["speedDigits"].label == "42"
        }, evaluatedWith: app)
        wait(for: [fallback], timeout: 10)
        XCTAssertNotEqual(app.staticTexts["currentActionForce"].label, "0.40")
        app.buttons["Start Mock"].tap()
        XCTAssertTrue(app.staticTexts["加速中"].waitForExistence(timeout: 10))
        app.buttons["computerTelemetrySwitch"].tap()
        XCTAssertEqual(app.staticTexts["speedDigits"].label, "42")
        XCUIDevice.shared.orientation = .portrait
    }

    func testCompletedActionsAndScoresRemainInCard() {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["--action-trace"]
        app.launch()
        XCTAssertTrue(app.buttons["computerTelemetrySwitch"].waitForExistence(timeout: 5))
        app.buttons["computerTelemetrySwitch"].tap()
        app.buttons["Start Mock"].tap()
        let score = app.staticTexts["currentActionScore"]
        for (ongoing, completed, peak) in [("加速中", "加速", "0.22"), ("煞車中", "煞車", "0.30"), ("左轉中", "左轉", "0.26")] {
            XCTAssertTrue(app.staticTexts[ongoing].waitForExistence(timeout: 10))
            XCTAssertEqual(app.staticTexts["currentActionStatus"].label, "進行中")
            XCTAssertEqual(app.staticTexts["currentActionDurationLabel"].label, "已持續")
            XCTAssertFalse(score.exists)
            XCTAssertEqual(app.staticTexts["currentActionPeak"].label, peak)
            capture(app, "Ongoing \(completed)")
            XCTAssertTrue(app.staticTexts[completed].waitForExistence(timeout: 10))
            XCTAssertEqual(app.staticTexts["currentActionStatus"].label, "已完成")
            XCTAssertEqual(app.staticTexts["currentActionDurationLabel"].label, "持續時間")
            XCTAssertEqual(app.staticTexts["currentActionScoreTitle"].label, "評分")
            XCTAssertFalse(app.staticTexts["平順評分"].exists)
            XCTAssertTrue(score.waitForExistence(timeout: 2))
            XCTAssertTrue((0...100).contains(Int(score.label) ?? -1))
            let duration = app.staticTexts["currentActionDuration"].label
            Thread.sleep(forTimeInterval: 0.5)
            XCTAssertEqual(app.staticTexts["currentActionDuration"].label, duration)
            XCTAssertEqual(app.staticTexts["currentActionPeak"].label, peak)
            XCTAssertTrue(app.descendants(matching: .any)["currentActionCard"].firstMatch.exists)
            XCTAssertEqual(app.sheets.count, 0)
            capture(app, "Completed \(completed) Score")
        }
    }

    func testLightAndDuoHalfLayouts() {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["--light"]
        app.launch()
        XCTAssertTrue(app.staticTexts["speedDigits"].waitForExistence(timeout: 5))
        assertCards(app, horizontal: false)
        capture(app, "Three Cards Light")
        app.terminate()
        app.launchArguments = ["--duo", "--half"]
        app.launch()
        let deck = app.descendants(matching: .any)["speedInstrumentDeck"].firstMatch
        XCTAssertTrue(deck.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(deck.frame.height, app.frame.height * 0.55)
        capture(app, "Duo Upper Half")
        XCTAssertFalse(app.scrollViews.firstMatch.exists)
        let lastCard = app.descendants(matching: .any)["gForceCircleCard"].firstMatch
        let computer = app.buttons["computerTelemetrySwitch"]
        XCTAssertGreaterThan(lastCard.frame.maxY, computer.frame.minY)
        capture(app, "Duo Upper Half Fixed")
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForLandscape(app)
        XCTAssertLessThanOrEqual(deck.frame.width, app.frame.width * 0.55)
        capture(app, "Duo Leading Half")
        XCUIDevice.shared.orientation = .portrait
    }

    private func assertCards(_ app: XCUIApplication, horizontal: Bool, centeredSpeed: Bool = true) {
        let cards = ["currentActionCard", "speedCenterCard", "gForceCircleCard"].map {
            app.descendants(matching: .any)[$0].firstMatch
        }
        for card in cards {
            XCTAssertTrue(card.waitForExistence(timeout: 5))
            XCTAssertGreaterThan(card.frame.width, 100)
            XCTAssertGreaterThan(card.frame.height, 100)
            XCTAssertGreaterThanOrEqual(card.frame.minX, app.frame.minX - 1)
            XCTAssertLessThanOrEqual(card.frame.maxX, app.frame.maxX + 1)
            XCTAssertLessThanOrEqual(card.frame.maxY, app.frame.maxY + 1)
        }
        if horizontal {
            XCTAssertLessThan(cards[0].frame.midX, cards[1].frame.midX)
            XCTAssertLessThan(cards[1].frame.midX, cards[2].frame.midX)
        } else {
            XCTAssertLessThan(cards[0].frame.midY, cards[1].frame.midY)
            XCTAssertLessThan(cards[1].frame.midY, cards[2].frame.midY)
        }
        XCTAssertFalse(cards[0].frame.intersects(cards[1].frame))
        XCTAssertFalse(cards[1].frame.intersects(cards[2].frame))
        let speed = app.staticTexts["speedDigits"].frame
        let unit = app.staticTexts["speedUnit"].frame
        if centeredSpeed {
            XCTAssertEqual(speed.midX, cards[1].frame.midX, accuracy: 4)
            XCTAssertEqual(speed.midX, unit.midX, accuracy: 4)
        }
        XCTAssertEqual(unit.midX, cards[1].frame.midX, accuracy: 4)
        XCTAssertGreaterThanOrEqual(unit.minY, speed.maxY - 1)
    }

    private func waitForLandscape(_ app: XCUIApplication) {
        let rotated = expectation(for: NSPredicate { _, _ in
            app.frame.width > app.frame.height
        }, evaluatedWith: app)
        wait(for: [rotated], timeout: 5)
        Thread.sleep(forTimeInterval: 1)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
