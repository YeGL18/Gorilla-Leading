import XCTest
import CoreLocation
import SwiftUI

final class TripReplayUITests: XCTestCase {
    func testProductionDuoParkingAndReplayScreenshots() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.gorilla.translation")
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_HK", "-capsuleDarkGlassEnabled", "YES", "--duo-landscape-screenshot"]
        app.launch()
        // Device Hub rotates the active inner display. XCUIDevice orientation
        // currently targets Duo's outer display, so don't override it here.
        let close = app.buttons.matching(NSPredicate(format: "label == 'Close' OR label == '關閉'")).firstMatch
        if close.waitForExistence(timeout: 4) { close.tap() }
        let home = app.buttons["Home"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 15), app.debugDescription)
        home.tap()
        XCTAssertGreaterThan(app.frame.width, 800, "Open the Duo inner display before running this check")
        XCTAssertGreaterThan(app.frame.height, 560)
        let mapToggle = app.buttons.matching(NSPredicate(format: "label == 'Switch Map Mode' OR label == '切換地圖模式' OR label == 'Show Map'")).firstMatch
        if mapToggle.exists { mapToggle.tap() }
        capture(app, "Duo Production Home")
        if close.exists { close.tap() }
        let parking = app.buttons.matching(NSPredicate(format: "label == 'Park' OR label == 'Parking memory' OR label == 'Parking Memory' OR label == '泊車記憶'")).firstMatch
        if !parking.exists {
            let address = app.descendants(matching: .any)["homeAddressCapsule"].firstMatch
            XCTAssertTrue(address.waitForExistence(timeout: 5), app.debugDescription)
            let compactCenter = address.frame.midX
            let source = address.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            source.press(forDuration: 0.1, thenDragTo: source.withOffset(CGVector(dx: 0, dy: -110)))
            Thread.sleep(forTimeInterval: 1)
            XCTAssertEqual(address.frame.midX, compactCenter, accuracy: 2, "Address expansion must preserve its centre")
        }
        XCTAssertTrue(parking.waitForExistence(timeout: 5), app.debugDescription)
        let expandedAddress = app.descendants(matching: .any)["homeAddressCapsule"].firstMatch.frame
        parking.tap()
        Thread.sleep(forTimeInterval: 1)
        capture(app, "Duo Production Parking Memory")
        let expandedParking = app.descendants(matching: .any)["homeAddressCapsule"].firstMatch.frame
        XCTAssertEqual(expandedParking.maxX, expandedAddress.maxX, accuracy: 2, "Expansion must preserve the right edge")
        XCTAssertEqual(expandedParking.maxY, expandedAddress.maxY, accuracy: 2, "Expansion must preserve the bottom edge")
        print("PARKING_LAYOUT\n" + app.debugDescription)
        app.buttons["homeTripReplay"].tap()
        if !app.buttons["replayTripRow"].firstMatch.waitForExistence(timeout: 3) {
            let calendar = app.descendants(matching: .any)["replayCalendar"].firstMatch
            let demoDay = calendar.buttons.matching(NSPredicate(format: "label CONTAINS 'November 3' OR label CONTAINS '11月3日'")).firstMatch
            XCTAssertTrue(demoDay.waitForExistence(timeout: 3), app.debugDescription)
            demoDay.tap()
        }
        XCTAssertTrue(app.buttons["replayTripRow"].firstMatch.waitForExistence(timeout: 10))
        capture(app, "Duo Production Replay Library")
        app.buttons["replayTripRow"].firstMatch.tap()
        XCTAssertTrue(app.buttons["replayOverview"].waitForExistence(timeout: 10))
        capture(app, "Duo Production Replay Detail")
        app.buttons["replayFollowPosition"].tap()
        Thread.sleep(forTimeInterval: 6)
        let dot = app.descendants(matching: .any)["replayPositionDot"].firstMatch
        XCTAssertTrue(dot.exists)
        var positions: [CGPoint] = []
        for _ in 0..<10 {
            positions.append(CGPoint(x: dot.frame.midX, y: dot.frame.midY))
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertLessThan(positions.map(\.x).max()! - positions.map(\.x).min()!, 3)
        XCTAssertLessThan(positions.map(\.y).max()! - positions.map(\.y).min()!, 3)
        app.terminate()
        app.launch()
        if close.waitForExistence(timeout: 3) { close.tap() }
        app.buttons["Speed"].firstMatch.tap()
        capture(app, "Duo Production Speed")
    }
    func testNativeRenameEnablesConfirmationAndSavesInBothThemes() {
        for theme in ["--dark", "--light"] {
            let app = XCUIApplication()
            app.launchArguments = ["--rename-place", theme, "-AppleLanguages", "(zh-Hant)"]
            app.launch()
            app.buttons["Rename Place"].tap()
            let alert = app.alerts.firstMatch
            XCTAssertTrue(alert.waitForExistence(timeout: 5))
            let confirm = alert.buttons.matching(NSPredicate(format: "label IN %@", ["確定", "OK", "Confirm"])).firstMatch
            XCTAssertFalse(confirm.isEnabled)
            alert.textFields.firstMatch.tap()
            alert.textFields.firstMatch.typeText("New Place")
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            // Duo moves native alerts when the keyboard enters; tap after that layout settles.
            Thread.sleep(forTimeInterval: 1.2)
            XCTAssertTrue(confirm.isEnabled)
            capture(app, "Native Rename \(theme)")
            confirm.tap()
            XCTAssertTrue(app.staticTexts["renameResult"].waitForExistence(timeout: 3))
            XCTAssertEqual(app.staticTexts["renameResult"].label, "New Place")
            app.terminate()
        }
    }

    func testSeparateFollowAndOverviewAndLiveData() {
        let app = XCUIApplication()
        app.launchArguments = ["--dark", "-AppleLanguages", "(en)"]
        app.launch()
        let row = app.buttons["replayTripRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let follow = app.buttons["replayFollowPosition"]
        XCTAssertTrue(follow.waitForExistence(timeout: 10))
        follow.tap()
        XCTAssertEqual(follow.value as? String, "Enable")
        app.buttons["replayOverview"].tap()
        XCTAssertEqual(follow.value as? String, "Close")
        XCTAssertTrue(app.descendants(matching: .any)["tripReplayPanel"].firstMatch.exists)
        capture(app, "Separate Replay Camera Controls")
        app.terminate()
        checkFixedDashboard(app)
    }

    func testFixedPhoneDashboardLayout() { checkFixedDashboard(XCUIApplication()) }

    private func checkFixedDashboard(_ app: XCUIApplication) {
        app.launchArguments = ["--live-data", "-AppleLanguages", "(en)"]
        app.launch()
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            Thread.sleep(forTimeInterval: 1)
            let dashboard = app.descendants(matching: .any)["fixedSpeedDashboard"].firstMatch
            XCTAssertTrue(dashboard.waitForExistence(timeout: 10))
            XCTAssertEqual(app.scrollViews.count, 0)
            let digits = app.descendants(matching: .any)["fixedDashboardSpeed"].firstMatch
            XCTAssertLessThan(abs(digits.frame.midY - dashboard.frame.midY), 8)
            XCTAssertFalse(digits.frame.intersects(app.descendants(matching: .any)["currentActionCard"].firstMatch.frame))
            XCTAssertFalse(digits.frame.intersects(app.descendants(matching: .any)["gForceCircleCard"].firstMatch.frame))
            XCTAssertEqual(app.sliders.count, 0)
            for key in ["speedCompactStatistics", "currentActionCard", "gForceCircleCard", "replaySpeedChart", "replayAltitudeChart", "speedLiveReadout"] {
                let item = app.descendants(matching: .any)[key].firstMatch
                XCTAssertTrue(item.exists, key)
                XCTAssertGreaterThanOrEqual(item.frame.minY, dashboard.frame.minY - 2, key)
                XCTAssertLessThanOrEqual(item.frame.maxY, dashboard.frame.maxY + 2, key)
            }
            capture(app, "Fixed Dashboard \(orientation.rawValue)")
        }
        XCUIDevice.shared.orientation = .portrait
        app.terminate()
    }

    func testDetailSectionsReorderAndPersist() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)"]
        app.launch()
        app.buttons["replayTripRow"].firstMatch.tap()
        XCTAssertTrue(app.buttons["replayOverview"].waitForExistence(timeout: 10))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)))
        let timeline = app.descendants(matching: .any)["replaySection-timeline"].firstMatch
        let stats = app.descendants(matching: .any)["replaySection-statistics"].firstMatch
        XCTAssertTrue(timeline.waitForExistence(timeout: 5))
        timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.1))
            .press(forDuration: 0.8, thenDragTo: stats.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)))
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertLessThan(timeline.frame.minY, stats.frame.minY)
        capture(app, "Reordered Detail Sections")
        app.terminate()
        app.launchArguments = ["--preserve", "-AppleLanguages", "(en)"]
        app.launch()
        app.buttons["replayTripRow"].firstMatch.tap()
        XCTAssertTrue(app.buttons["replayOverview"].waitForExistence(timeout: 10))
        XCTAssertLessThan(timeline.frame.minY, stats.frame.minY)
        app.terminate()
    }

    func testVLMAlertUsesScopedAppearanceAndRetainsActions() {
        let app = XCUIApplication()
        for mode in ["--dark", "--light"] {
            app.launchArguments = ["--vlm-prompt", mode, "-AppleLanguages", "(zh-Hant)"]
            app.launch()
            app.buttons["Show VLM"].tap()
            let alert = app.alerts.firstMatch
            XCTAssertTrue(alert.waitForExistence(timeout: 5))
            capture(app, "VLM Prompt \(mode)")
            alert.buttons["已準備好"].tap()
            XCTAssertTrue(app.staticTexts["Ready called"].waitForExistence(timeout: 5))
            app.buttons["Show VLM"].tap()
            alert.buttons["取消"].tap()
            XCTAssertTrue(app.staticTexts["Cancel called"].waitForExistence(timeout: 5))
        }
    }

    func testPlaybackContinuesWhileScrollingDetails() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)"]
        app.launch()
        let row = app.buttons["replayTripRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let panel = app.descendants(matching: .any)["tripReplayPanel"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        panel.swipeUp()
        let scrubber = app.descendants(matching: .any)["replayScrubber"].firstMatch
        let initial = scrubber.value as? String
        let play = app.buttons["replayPlayPause"]
        play.tap()
        for _ in 0..<2 {
            panel.swipeUp()
            panel.swipeDown()
        }
        XCTAssertEqual(play.label, "Pause")
        XCTAssertNotEqual(scrubber.value as? String, initial)
        capture(app, "Playback While Scrolling")
        play.tap()
        XCTAssertEqual(play.label, "Play")
    }

    @MainActor func testLongParkingHistoryContrastAndHapticPreference() {
        let now = Date()
        let home = CLLocationCoordinate2D(latitude: 22.425, longitude: 114.205)
        func session(hours: Double, daysAgo: Double = 1, automotive: Bool = true,
                     coordinate: CLLocationCoordinate2D? = nil) -> ParkingReminderPolicy.Session {
            let arrival = now.addingTimeInterval(-daysAgo * 86400)
            return .init(arrival: arrival, departure: arrival.addingTimeInterval(hours * 3600),
                         coordinate: coordinate ?? home, automotive: automotive)
        }
        func matches(_ sessions: [ParkingReminderPolicy.Session]) -> Bool {
            ParkingReminderPolicy.isLongStayPlace(at: home, before: now, sessions: sessions)
        }
        XCTAssertFalse(matches([]))
        XCTAssertTrue(matches([session(hours: 3.5)]))
        XCTAssertFalse(matches([session(hours: 3.49)]))
        XCTAssertFalse(matches([session(hours: 8, automotive: false)]))
        XCTAssertFalse(matches([session(hours: 8, coordinate: .init(latitude: 22.5, longitude: 114.3))]))
        XCTAssertFalse(matches([.init(arrival: now.addingTimeInterval(-86400), departure: nil, coordinate: home, automotive: true)]))
        XCTAssertFalse(matches([session(hours: 8, daysAgo: 0)]))
        XCTAssertFalse(matches([session(hours: 6), session(hours: 0.5, daysAgo: 2)]))
        XCTAssertTrue(matches([session(hours: 4), session(hours: 5, daysAgo: 2)]))
        XCTAssertTrue(ParkingReminderPolicy.schedule(entry: now, now: now, suppress: true).isEmpty)
        XCTAssertEqual(ParkingReminderPolicy.schedule(entry: now, now: now, suppress: false).map(\.minute), [25, 55, 85, 115, 145, 175])
        XCTAssertEqual(ParkingReminderPolicy.schedule(entry: now.addingTimeInterval(-3600), now: now, suppress: false).map(\.minute), [85, 115, 145, 175])

        XCTAssertLessThan(UIColor(Color.yellow.contrastingLabel(over: .white, opacity: 1, scheme: .light)).gorillaLuminance, 0.01)
        XCTAssertGreaterThan(UIColor(Color.black.contrastingLabel(over: .white, opacity: 1, scheme: .light)).gorillaLuminance, 0.99)
        XCTAssertLessThan(UIColor(Color.black.contrastingLabel(over: .white, opacity: 0, scheme: .light)).gorillaLuminance, 0.01)
        let luminance = UIColor(Color.yellow.readableAccent(in: .light)).gorillaLuminance
        XCTAssertGreaterThanOrEqual(1.05 / (luminance + 0.05), 4.5)
        let name = "haptic-check-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertTrue(AppHaptics.enabled(in: defaults))
        defaults.set(false, forKey: AppHaptics.preferenceKey)
        XCTAssertFalse(AppHaptics.enabled(in: defaults))
    }

    func testWholeTripRowOpensFromTitleAndThumbnail() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launch()
        let row = app.buttons["replayTripRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        for x in [0.15, 0.5] {
            row.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.5)).tap()
            XCTAssertTrue(app.descendants(matching: .any)["tripReplayPanel"].firstMatch.waitForExistence(timeout: 5))
            XCTAssertTrue(app.descendants(matching: .any)["replayPositionDot"].firstMatch.exists)
            app.buttons["replayBack"].tap()
            XCTAssertTrue(row.waitForExistence(timeout: 5))
        }
    }

    func testCurrentActionOnlyRecognizesWhileDriving() {
        let app = XCUIApplication()
        app.launchArguments = ["--action-gate", "-AppleLanguages", "(zh-Hant)"]
        app.launch()
        XCTAssertTrue(app.staticTexts["暫無動作"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["加速中"].exists)
        app.buttons["Toggle Driving"].tap()
        XCTAssertTrue(app.staticTexts["加速中"].waitForExistence(timeout: 5))
        app.buttons["Toggle Driving"].tap()
        XCTAssertTrue(app.staticTexts["暫無動作"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["加速中"].exists)
    }

    func testThreeTripsToOneTripToEmptyDay() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--multi-day", "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.buttons["replayTripRow"].firstMatch.waitForExistence(timeout: 10))
        let calendar = app.descendants(matching: .any)["replayCalendar"].firstMatch
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMMM d"
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        calendar.buttons.matching(NSPredicate(format: "label CONTAINS %@", formatter.string(from: yesterday))).firstMatch.tap()
        let multiple = expectation(for: NSPredicate { _, _ in
            app.buttons.matching(identifier: "replayTripRow").count > 1
        }, evaluatedWith: app)
        wait(for: [multiple], timeout: 5)
        capture(app, "Three Trips After Fade")
        app.buttons["replayCalendarMenu"].tap()
        app.buttons["Today"].tap()
        let single = expectation(for: NSPredicate { _, _ in
            app.buttons.matching(identifier: "replayTripRow").count == 1
        }, evaluatedWith: app)
        wait(for: [single], timeout: 5)
        capture(app, "One Trip After Fade")
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        calendar.buttons.matching(NSPredicate(format: "label CONTAINS %@", formatter.string(from: tomorrow))).firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["replayEmptyHistory"].firstMatch.waitForExistence(timeout: 5))
        capture(app, "Future Empty Day After Fade")
    }

    func testDateChangesFadeBetweenTripAndEmptyHistory() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.buttons["replayTripRow"].firstMatch.waitForExistence(timeout: 10))
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMMM d"
        let calendar = app.descendants(matching: .any)["replayCalendar"].firstMatch
        let date = calendar.buttons.matching(NSPredicate(format: "label CONTAINS %@", formatter.string(from: yesterday))).firstMatch
        XCTAssertTrue(date.waitForExistence(timeout: 5))
        date.tap()
        XCTAssertTrue(app.descendants(matching: .any)["replayEmptyHistory"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["replayTripRow"].firstMatch.exists)
        capture(app, "Calendar Empty Day After Fade")
        app.buttons["replayCalendarMenu"].tap()
        app.buttons["Today"].tap()
        XCTAssertTrue(app.buttons["replayTripRow"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["replayEmptyHistory"].firstMatch.exists)
    }

    func testDarkSwipeDeleteAppearance() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--dark", "-AppleLanguages", "(en)"]
        app.launch()
        let row = app.buttons["replayTripRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.swipeLeft()
        XCTAssertTrue(app.buttons["Delete"].firstMatch.waitForExistence(timeout: 5))
        capture(app, "Dark Red Swipe Delete")
    }

    func testSwipeDeleteKeepsRowUntilConfirmation() {
        let app = XCUIApplication()
        app.launchArguments = ["--dark", "-AppleLanguages", "(en)"]
        app.launch()
        let row = app.buttons["replayTripRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        let confirmation = app.buttons["replayConfirmDelete"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(row.exists)
        if cancel.exists {
            cancel.tap()
        } else {
            // Regular-width native confirmation popovers dismiss by tapping outside.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        }
        XCTAssertTrue(confirmation.waitForNonExistence(timeout: 5))
        XCTAssertTrue(row.exists)
        row.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.tap()
        XCTAssertTrue(app.descendants(matching: .any)["replayEmptyHistory"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(row.exists)
        app.terminate()
    }

    @MainActor func testDrivingDashboardStartsFreshAndClearsWithoutDeletingHistory() {
        let name = "com.gorilla.live-session-check-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".json")
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: url) }
        let store = TripReplayStore(defaults: defaults, storageURL: url)
        store.setContext(foreground: true, game: false)
        let now = Date()
        func record(_ t: Double) {
            let time = now.addingTimeInterval(t)
            let fix = CLLocation(coordinate: .init(latitude: 22.3 + t * 0.00005, longitude: 114.1),
                altitude: 20, horizontalAccuracy: 5, verticalAccuracy: 5, course: 0, speed: 10, timestamp: time)
            store.record(fix, automotive: true, pedestrian: false, now: time)
        }
        record(0)
        XCTAssertNil(store.drivingTrip)
        store.setDriving(true)
        let firstID = store.drivingTrip?.id
        for t in 1...5 { record(Double(t)) }
        XCTAssertEqual(store.drivingTrip?.points.count, 5)
        XCTAssertEqual(store.drivingTrip?.start, now.addingTimeInterval(1))
        store.setDriving(false)
        XCTAssertNil(store.drivingTrip)
        XCTAssertFalse(store.trips.isEmpty)
        store.setDriving(true)
        XCTAssertNotEqual(store.drivingTrip?.id, firstID)
        XCTAssertTrue(store.drivingTrip?.points.isEmpty == true)
        record(6)
        XCTAssertEqual(store.drivingTrip?.points.count, 1)
        store.setContext(foreground: true, game: true)
        XCTAssertNil(store.drivingTrip)
        store.setContext(foreground: true, game: false)
        store.setDriving(true)
        store.setEnabled(false)
        XCTAssertNil(store.drivingTrip)
    }

    func testBackRemovesDetailsWithMap() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--sheet-library", "-AppleLanguages", "(zh-Hant)"]
        app.launch()
        let row = app.buttons["replayTripRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let calendar = app.descendants(matching: .any)["replayCalendar"].firstMatch
        let originalCalendarTop = calendar.frame.minY
        let title = app.staticTexts["replayLibraryTitle"]
        let close = app.buttons["replayCloseLibrary"]
        // The portrait iPhone 16 Pro fixture has a 62-point sheet top and a 20-point header inset.
        XCTAssertEqual(close.frame.minY, 82, accuracy: 1)
        XCTAssertEqual(title.frame.midY, close.frame.midY, accuracy: 1)
        let originalTitleTop = title.frame.minY
        capture(app, "Library Header Before Transition")
        row.tap()
        let panel = app.descendants(matching: .any)["tripReplayPanel"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["replayCloseDetails"].exists)
        app.buttons["replayBack"].tap()
        let snapshot = XCTAttachment(string: app.debugDescription)
        snapshot.name = "After Floating Back Hierarchy"
        snapshot.lifetime = .keepAlways
        add(snapshot)
        capture(app, "After Floating Back")
        let returned = expectation(for: NSPredicate { _, _ in
            row.isHittable && !panel.exists
        }, evaluatedWith: app)
        wait(for: [returned], timeout: 5)
        XCTAssertTrue(app.staticTexts["replayLibraryTitle"].exists)
        XCTAssertEqual(calendar.frame.minY, originalCalendarTop, accuracy: 1)
        XCTAssertEqual(title.frame.minY, originalTitleTop, accuracy: 1)
    }

    func testAdaptiveScrubberSettlesAtDraggedTime() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.buttons["replayTripRow"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["replayTripRow"].firstMatch.tap()
        let scrubber = app.descendants(matching: .any)["replayScrubber"].firstMatch
        XCTAssertTrue(scrubber.waitForExistence(timeout: 10))
        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
        let settled = expectation(for: NSPredicate { _, _ in
            let components = (scrubber.value as? String ?? "").split(separator: ":").compactMap { Double($0) }
            return components.count == 2 && abs(components[0] * 60 + components[1] - 480) < 12
        }, evaluatedWith: app)
        wait(for: [settled], timeout: 5)
        capture(app, "Adaptive Scrubber After Fast Drag")
        let before = scrubber.value as? String
        app.buttons["replayPlayPause"].tap()
        let advanced = expectation(for: NSPredicate { _, _ in (scrubber.value as? String) != before }, evaluatedWith: app)
        wait(for: [advanced], timeout: 5)
        app.buttons["replayPlayPause"].tap()
    }

    func testDarkControlsAndOverviewKeepSheetForBothGlassStyles() {
        for darkGlass in ["YES", "NO"] {
            XCUIDevice.shared.orientation = .portrait
            let app = XCUIApplication()
            app.launchArguments = ["--dark", "-capsuleDarkGlassEnabled", darkGlass, "-AppleLanguages", "(en)"]
            app.launch()
            XCTAssertTrue(app.buttons["replayTripRow"].firstMatch.waitForExistence(timeout: 10))
            app.buttons["replayTripRow"].firstMatch.tap()
            let panel = app.descendants(matching: .any)["tripReplayPanel"].firstMatch
            XCTAssertTrue(panel.waitForExistence(timeout: 10))
            let overview = app.buttons["replayOverview"]
            XCTAssertTrue(overview.isHittable)
            capture(app, "Dark \(darkGlass) Half Sheet")
            overview.tap()
            Thread.sleep(forTimeInterval: 1)
            XCTAssertTrue(panel.exists)
            XCTAssertFalse(app.buttons["replayCloseDetails"].exists)
            XCTAssertTrue(app.staticTexts["replayEndpoints"].exists)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)))
            let expand = app.buttons["replayExpandStatistics"]
            XCTAssertTrue(expand.waitForExistence(timeout: 5))
            app.buttons["replayNextEvent"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["replayCurrentEvent"].firstMatch.waitForExistence(timeout: 5))
            capture(app, "Dark \(darkGlass) Expanded Sheet And Orange Acceleration")
            checkFloatingControls(app)
            app.terminate()
        }
    }

    func testCalendarReplayAltitudeAndPlayback() {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.buttons["replayRecordingSettings"].waitForExistence(timeout: 5))
        let row = app.buttons["replayTripRow"].firstMatch
        for _ in 0..<3 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        capture(app, "Replay Calendar")
        row.tap()
        let panel = app.descendants(matching: .any)["tripReplayPanel"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 10))
        let play = app.buttons["replayPlayPause"]
        XCTAssertTrue(play.isHittable)
        checkFloatingControls(app)
        XCTAssertFalse(app.descendants(matching: .any)["replayHighestAltitude"].firstMatch.exists)
        XCTAssertFalse(app.buttons["replayEvent"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["replayEventTimeline"].firstMatch.exists)
        let scrubber = app.descendants(matching: .any)["replayScrubber"].firstMatch
        let initialTime = scrubber.value as? String
        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).tap()
        XCTAssertNotEqual(scrubber.value as? String, initialTime)
        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).tap()
        let selected = app.staticTexts["replaySelectedTime"]
        panel.swipeUp()
        panel.swipeDown()
        // Raise the sheet to expose statistics rather than obscuring the map with another page.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)))
        let expand = app.buttons["replayExpandStatistics"]
        for _ in 0..<3 where !expand.isHittable { panel.swipeDown() }
        XCTAssertTrue(expand.isHittable)
        expand.tap()
        let highest = app.descendants(matching: .any)["replayHighestAltitude"].firstMatch
        XCTAssertTrue(highest.waitForExistence(timeout: 5))
        let count = app.descendants(matching: .any)["replayEventCount"].firstMatch
        let lowest = app.descendants(matching: .any)["replayLowestAltitude"].firstMatch
        XCTAssertLessThan(count.frame.midX, lowest.frame.midX)
        capture(app, "Replay Altitude Statistics")
        app.buttons["replayNextEvent"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["replayCurrentEvent"].firstMatch.waitForExistence(timeout: 5))
        let before = selected.label
        play.tap()
        let advanced = expectation(for: NSPredicate { _, _ in selected.label != before && !selected.label.isEmpty }, evaluatedWith: app)
        wait(for: [advanced], timeout: 8)
        play.tap()
        let altitude = app.descendants(matching: .any)["replayAltitudeChart"].firstMatch
        XCTAssertTrue(altitude.waitForExistence(timeout: 5))
        for _ in 0..<6 {
            if altitude.frame.minY >= panel.frame.minY + 10 && altitude.frame.maxY < play.frame.minY { break }
            if altitude.frame.minY < panel.frame.minY + 10 { panel.swipeDown() }
            else { panel.swipeUp() }
        }
        XCTAssertGreaterThanOrEqual(altitude.frame.minY, panel.frame.minY)
        XCTAssertLessThan(altitude.frame.maxY, play.frame.minY)
        capture(app, "Replay Speed And Altitude Charts")
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = expectation(for: NSPredicate { _, _ in app.frame.width > app.frame.height }, evaluatedWith: app)
        wait(for: [landscape], timeout: 10)
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(play.isHittable)
        checkFloatingControls(app)
        capture(app, "Replay Landscape")
        let overview = app.buttons["replayOverview"]
        for _ in 0..<6 where !overview.isHittable { panel.swipeDown() }
        XCTAssertTrue(overview.isHittable)
        overview.tap()
        XCTAssertTrue(app.descendants(matching: .any)["tripReplayMap"].firstMatch.exists)
        XCTAssertTrue(panel.exists)
        XCTAssertFalse(app.buttons["replayCloseDetails"].exists)
        capture(app, "Replay Full Route Overview")
        XCUIDevice.shared.orientation = .portrait
    }

    private func checkFloatingControls(_ app: XCUIApplication) {
        let ids = ["replayPlayPause", "replayScrubber", "replayPreviousEvent", "replayNextEvent"]
        let controls = ids.map { app.descendants(matching: .any)[$0].firstMatch }
        for control in controls {
            XCTAssertTrue(control.exists)
            XCTAssertGreaterThanOrEqual(control.frame.width, 44)
            XCTAssertGreaterThanOrEqual(control.frame.minX, app.frame.minX)
            XCTAssertLessThanOrEqual(control.frame.maxX, app.frame.maxX)
            XCTAssertLessThanOrEqual(control.frame.maxY, app.frame.maxY)
        }
        for index in 1..<controls.count {
            XCTAssertLessThanOrEqual(controls[index - 1].frame.maxX, controls[index].frame.minX)
        }
    }

    func testDeleteReplayFromDetails() {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-AppleLanguages", "(en)"]
        app.launch()
        let row = app.buttons["replayTripRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let panel = app.descendants(matching: .any)["tripReplayPanel"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        let delete = app.buttons["Delete Trip"]
        for _ in 0..<8 where !delete.isHittable { panel.swipeUp() }
        XCTAssertTrue(delete.isHittable)
        delete.tap()
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(app.buttons["replayRecordingSettings"].waitForExistence(timeout: 5))
        XCTAssertFalse(row.exists)
    }

    func testEmptyHistoryAndRecordingPreferencePersists() {
        let app = XCUIApplication()
        app.launchArguments = ["--empty", "-AppleLanguages", "(en)"]
        app.launch()
        app.buttons["replayRecordingSettings"].tap()
        let toggle = app.switches["replayRecordingToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let off = expectation(for: NSPredicate { _, _ in toggle.value as? String == "0" }, evaluatedWith: app)
        wait(for: [off], timeout: 5)
        app.terminate()
        app.launchArguments = ["--preserve", "-AppleLanguages", "(en)"]
        app.launch()
        app.buttons["replayRecordingSettings"].tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0")
        XCTAssertFalse(app.buttons["replayTripRow"].firstMatch.exists)
    }

    @MainActor func testRealStoreForegroundGameGatingAndPersistence() throws {
        let name = "com.gorilla.replay-store-check-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".json")
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: url) }
        let store = TripReplayStore(defaults: defaults, storageURL: url)
        let now = Date()
        func fix(_ t: Double) -> CLLocation {
            CLLocation(coordinate: .init(latitude: 22.3 + t * 0.00005, longitude: 114.1), altitude: 20,
                       horizontalAccuracy: 5, verticalAccuracy: 5, course: 0, speed: 10, timestamp: now.addingTimeInterval(t))
        }
        for t in 0...3 { store.record(fix(Double(t)), automotive: true, pedestrian: false, now: now.addingTimeInterval(Double(t))) }
        XCTAssertTrue(store.trips.isEmpty)
        store.setContext(foreground: true, game: true)
        for t in 0...3 { store.record(fix(Double(t)), automotive: true, pedestrian: false, now: now.addingTimeInterval(Double(t))) }
        XCTAssertTrue(store.trips.isEmpty)
        store.setContext(foreground: true, game: false)
        for t in 0...5 { store.record(fix(Double(t)), automotive: true, pedestrian: false, now: now.addingTimeInterval(Double(t))) }
        XCTAssertEqual(store.trips.count, 1)
        let count = store.trips[0].points.count
        store.setContext(foreground: false, game: false)
        store.record(fix(6), automotive: true, pedestrian: false, now: now.addingTimeInterval(6))
        XCTAssertEqual(store.trips[0].points.count, count)
        store.setContext(foreground: true, game: false)
        store.record(fix(40), automotive: true, pedestrian: false, now: now.addingTimeInterval(40))
        XCTAssertTrue(store.trips[0].hasGaps)
        XCTAssertTrue(store.flush())
        store.prepareForRestore()
        let reloaded = TripReplayStore(defaults: defaults, storageURL: url)
        XCTAssertEqual(reloaded.trips[0].points.count, count + 1)
        reloaded.setEnabled(false)
        XCTAssertFalse(reloaded.enabled)
        XCTAssertFalse(TripReplayStore(defaults: defaults, storageURL: url).enabled)
        reloaded.deleteAll()
        let empty = TripReplayStore(defaults: defaults, storageURL: url)
        XCTAssertTrue(empty.trips.isEmpty)
        try Data("broken".utf8).write(to: url)
        let broken = TripReplayStore(defaults: defaults, storageURL: url)
        XCTAssertNotNil(broken.storageError)
        XCTAssertFalse(broken.flush())
        XCTAssertEqual(try Data(contentsOf: url), Data("broken".utf8))
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if name.hasPrefix("Duo Production") { Thread.sleep(forTimeInterval: 12) }
    }
}
