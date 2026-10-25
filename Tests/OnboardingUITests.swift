import XCTest

final class OnboardingUITests: XCTestCase {
    @MainActor func testSupportLinksOnlyInsideAbout() {
        let app = XCUIApplication()
        app.launchArguments = ["--settings-about", "--parking-color=DD406C"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.staticTexts["關於 Gorilla"].waitForExistence(timeout: 5))
        for title in ["Gorilla", "關於 Gorilla Leading"] {
            XCTAssertTrue(app.staticTexts[title].exists, title)
            XCTAssertEqual(app.cells.containing(.staticText, identifier: title).count, 1, title)
        }
        for title in ["為 Gorilla Leading 評分", "幫助", "私隱政策", "使用條款"] {
            XCTAssertFalse(app.staticTexts[title].exists, title)
        }
        XCTAssertFalse(app.staticTexts["支援與條款"].exists)
        capture("settings-about")
        app.cells.containing(.staticText, identifier: "關於 Gorilla Leading").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["咪錶探測"].waitForExistence(timeout: 5))
        capture("about-custom-parking-color")
        for _ in 0..<4 {
            if app.staticTexts["使用條款"].exists { break }
            app.swipeUp()
        }
        for title in ["為 Gorilla Leading 評分", "幫助", "私隱政策", "使用條款"] {
            XCTAssertTrue(app.staticTexts[title].exists, title)
        }
        capture("about-support-links")
    }

    @MainActor func testJourneyStopsAtDestination() {
        let app = XCUIApplication()
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        app.buttons["繼續"].tap()
        let speed = app.staticTexts["tourJourneySpeed"]
        XCTAssertTrue(speed.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "label != '0'"), evaluatedWith: speed)
        waitForExpectations(timeout: 5)
        expectation(for: NSPredicate(format: "label == '0'"), evaluatedWith: speed)
        waitForExpectations(timeout: 120)
        capture("journey-stopped")
        XCTAssertEqual(speed.label, "0")
    }

    func testMotionSlowsForTurnsAndStops() {
        let motion = LeadingJourneyMotion(distance: 600, turns: [.init(distance: 450, angle: 90)])
        var previous = motion.sample(at: 0)
        var firstPeak = 0.0, trough = 100.0, secondPeak = 0.0, turning = 100.0
        for time in stride(from: 0.05, through: motion.duration, by: 0.05) {
            let sample = motion.sample(at: time)
            XCTAssertGreaterThanOrEqual(sample.distance, previous.distance)
            XCTAssertLessThanOrEqual(sample.speedKmh, 62.001)
            let measured = (sample.distance - previous.distance) / 0.05 * 3.6
            XCTAssertEqual(measured, (sample.speedKmh + previous.speedKmh) / 2, accuracy: 0.15)
            if (100...130).contains(sample.distance) { firstPeak = max(firstPeak, sample.speedKmh) }
            if (210...250).contains(sample.distance) { trough = min(trough, sample.speedKmh) }
            if (330...370).contains(sample.distance) { secondPeak = max(secondPeak, sample.speedKmh) }
            if (448...452).contains(sample.distance) { turning = min(turning, sample.speedKmh) }
            previous = sample
        }
        XCTAssertGreaterThan(firstPeak, 61)
        XCTAssertEqual(trough, 48, accuracy: 0.2)
        XCTAssertGreaterThan(secondPeak, 61)
        XCTAssertLessThan(turning, 24)
        XCTAssertLessThan(motion.duration, 50)
        XCTAssertEqual(motion.sample(at: motion.duration).distance, 600, accuracy: 0.001)
        XCTAssertEqual(motion.sample(at: motion.duration + 5).speedKmh, 0)
        XCTAssertEqual(motion.sample(at: motion.duration + 5).distance, 600, accuracy: 0.001)
        XCTAssertEqual(motion.sample(at: -1).speedKmh, 0)
    }

    @MainActor func testTourPagesAndLandscape() throws {
        let app = XCUIApplication()
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.staticTexts["歡迎使用 Gorilla Leading"].waitForExistence(timeout: 8))
        app.buttons["繼續"].tap()
        XCTAssertTrue(app.staticTexts["路況在變，畫面跟住你走"].waitForExistence(timeout: 5))
        let speed = app.staticTexts["tourJourneySpeed"]
        expectation(for: NSPredicate(format: "label != '0'"), evaluatedWith: speed)
        waitForExpectations(timeout: 5)
        capture("journey-portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        capture("journey-landscape")
        XCUIDevice.shared.orientation = .portrait
        app.buttons["繼續"].tap()
        XCTAssertTrue(app.staticTexts["中環 · 紅棉路"].waitForExistence(timeout: 5))
        capture("meters")
        app.buttons["繼續"].tap()
        XCTAssertTrue(app.staticTexts["昂船洲大橋觀景點"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["已泊車"].exists)
        XCTAssertFalse(app.staticTexts["B1 · 中環中心"].exists)
        capture("parking-memory")
        app.buttons["繼續"].tap()
        XCTAssertTrue(app.staticTexts["由你決定 Gorilla 可以看見甚麼"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["開始使用"].exists)
        capture("privacy")
    }

    @MainActor private func capture(_ name: String) {
        let settled = expectation(description: "Layout settles before capture")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { settled.fulfill() }
        wait(for: [settled], timeout: 2)
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: "/private/tmp/onboarding-\(name).png"))
    }
}
