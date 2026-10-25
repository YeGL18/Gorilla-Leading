import XCTest

final class MapGestureUITests: XCTestCase {
    func testMarkerRequiresHoldBeforeDraggingAndRestoresScale() {
        let app = XCUIApplication(bundleIdentifier: "com.gorilla.map-interaction-checks")
        app.launchArguments = ["--hold"]
        app.launch()
        let marker = app.otherElements["holdMarker"]
        let status = app.staticTexts["holdStatus"]
        XCTAssertTrue(marker.waitForExistence(timeout: 10))
        let destination = app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        marker.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1, thenDragTo: destination)
        XCTAssertTrue(status.label.contains("unlocks=0"), status.label)
        XCTAssertTrue(status.label.contains("scale=1.00"), status.label)
        marker.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.8, thenDragTo: destination)
        XCTAssertTrue(status.label.contains("unlocks=1 releases=1 scale=1.00"), status.label)
    }

    @MainActor
    func testParkingAndMeterBodiesRemainVisibleDuringNativePan() {
        let app = XCUIApplication(bundleIdentifier: "com.gorilla.map-interaction-checks")
        app.launchArguments = ["--marker-native-pan"]
        app.launch()
        let status = app.staticTexts["markerMotionStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 15))
        expectation(for: NSPredicate { _, _ in self.number("base", from: status.label) > 100 }, evaluatedWith: status)
        waitForExpectations(timeout: 10)
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.20, dy: 0.65))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.62))
        start.press(forDuration: 1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 1)
        end.press(forDuration: 0.05, thenDragTo: start, withVelocity: .slow, thenHoldForDuration: 1)
        expectation(for: NSPredicate { _, _ in status.label.contains("done=1") }, evaluatedWith: status)
        waitForExpectations(timeout: 20)
        XCTAssertGreaterThan(number("meterBase", from: status.label), 100, status.label)
        XCTAssertGreaterThanOrEqual(number("ratio", from: status.label), 85, status.label)
        XCTAssertGreaterThanOrEqual(number("meterRatio", from: status.label), 85, status.label)
        print("Native pan marker pixels: \(status.label)")
    }

    @MainActor
    func testMarkerBodyRemainsVisibleDuringCoordinateAndCameraMotion() {
        let app = XCUIApplication(bundleIdentifier: "com.gorilla.map-interaction-checks")
        app.launchArguments = ["--marker-motion"]
        app.launch()
        let status = app.staticTexts["markerMotionStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 15))
        expectation(for: NSPredicate { _, _ in status.label.contains("done=1") }, evaluatedWith: status)
        waitForExpectations(timeout: 25)
        XCTAssertGreaterThan(number("base", from: status.label), 100, status.label)
        XCTAssertGreaterThanOrEqual(number("ratio", from: status.label), 85, status.label)
        print(status.label)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    @MainActor
    func testMarkerScaleDoesNotAccumulateDuringNativeTransformWrites() {
        let app = XCUIApplication(bundleIdentifier: "com.gorilla.map-interaction-checks")
        app.launchArguments = ["--scale"]
        app.launch()
        let status = app.staticTexts["markerCheckStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertTrue(status.label.hasPrefix("PASS:"))
    }

    func testPaddedCameraFitPreservesStartAndFramesBothPoints() {
        let app = XCUIApplication(bundleIdentifier: "com.gorilla.map-interaction-checks")
        app.launchArguments = ["--fits"]
        app.launch()
        let status = app.staticTexts["fitStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 15))
        XCTAssertEqual(status.label, "PASS: 34 padded camera checks")
        print(status.label)
    }

    @MainActor
    func testAnnotationFadesForClustersRemovalAndReuse() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.gorilla.map-interaction-checks")
        app.launchArguments = ["--fades"]
        app.launch()
        let status = app.staticTexts["fadeStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 15))
        func waitFor(_ field: String, above value: Int) {
            let expected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.number(field, from: status.label) > value }, object: status)
            let result = XCTWaiter.wait(for: [expected], timeout: 10)
            print("After \(field): \(status.label)")
            XCTAssertEqual(result, .completed, status.label)
        }
        app.buttons["Add"].tap()
        waitFor("single", above: 0)
        app.buttons["Cluster"].tap()
        waitFor("cluster", above: 0)
        waitFor("snapshots", above: 0)
        waitFor("images", above: 0)
        let previous = number("single", from: status.label)
        app.buttons["Separate"].tap()
        waitFor("single", above: previous)
        app.buttons["Remove"].tap()
        let cleaned = NSPredicate { _, _ in self.number("active", from: status.label) == 0 }
        expectation(for: cleaned, evaluatedWith: status)
        waitForExpectations(timeout: 5)
        app.buttons["Add"].tap()
        waitFor("reused", above: 0)
        waitFor("opaque", above: 1)
        XCTAssertEqual(number("invalid", from: status.label), 0, status.label)
        print("Annotation fade and reuse: \(status.label)")
    }

    @MainActor
    func testDisappearingMarkersFollowCameraMotion() {
        let app = XCUIApplication(bundleIdentifier: "com.gorilla.map-interaction-checks")
        app.launchArguments = ["--fades"]
        app.launch()
        let status = app.staticTexts["fadeStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 15))
        app.buttons["Add"].tap()
        expectation(for: NSPredicate { _, _ in self.number("opaque", from: status.label) == 2 }, evaluatedWith: status)
        waitForExpectations(timeout: 10)
        app.buttons["Move Fade"].tap()
        expectation(for: NSPredicate { _, _ in self.number("motion", from: status.label) >= 3 }, evaluatedWith: status)
        waitForExpectations(timeout: 10)
        XCTAssertGreaterThan(number("travel", from: status.label), 20, status.label)
        XCTAssertLessThanOrEqual(number("error", from: status.label), 2, status.label)
        XCTAssertEqual(number("invalid", from: status.label), 0, status.label)
        expectation(for: NSPredicate { _, _ in self.number("active", from: status.label) == 0 }, evaluatedWith: status)
        waitForExpectations(timeout: 5)
        print("World-anchored fade during pan/zoom/heading/pitch: \(status.label)")
    }

    @MainActor
    func testFirstSingleFingerDragDuringTracking() {
        let app = XCUIApplication(bundleIdentifier: "com.gorilla.map-interaction-checks")
        app.launchArguments = ["--gestures"]
        app.launch()
        let status = app.staticTexts["cameraStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: 0.55))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.60, dy: 0.65))
        start.press(forDuration: 0.05, thenDragTo: end)
        let moved = NSPredicate { _, _ in self.number("distance", from: status.label) > 30 }
        expectation(for: moved, evaluatedWith: status)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(number("begins", from: status.label), 1, status.label)
        XCTAssertEqual(number("ends", from: status.label), 1, status.label)
        print("Native one-finger drag: \(status.label)")
    }

    @MainActor
    func testFirstNativePinchDuringTracking() {
        let app = XCUIApplication(bundleIdentifier: "com.gorilla.map-interaction-checks")
        app.launchArguments = ["--gestures"]
        app.launch()
        let status = app.staticTexts["cameraStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        map.pinch(withScale: 2, velocity: 1)
        let zoomed = NSPredicate { _, _ in self.number("zoom", from: status.label) < 1100 }
        expectation(for: zoomed, evaluatedWith: status)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(number("begins", from: status.label), 1, status.label)
        XCTAssertEqual(number("ends", from: status.label), 1, status.label)
        print("Native two-finger pinch: \(status.label)")
    }

    @MainActor
    func testLongHoldThenDragAndRepeat() {
        let app = XCUIApplication(bundleIdentifier: "com.gorilla.map-interaction-checks")
        app.launchArguments = ["--gestures"]
        app.launch()
        let status = app.staticTexts["cameraStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: 0.55))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.60, dy: 0.65))
        start.press(forDuration: 6, thenDragTo: end)
        XCTAssertGreaterThan(number("distance", from: status.label), 30, status.label)
        XCTAssertGreaterThan(number("heldMs", from: status.label), 5800, status.label)
        XCTAssertEqual(number("ends", from: status.label), 1, status.label)
        end.press(forDuration: 0.05, thenDragTo: start)
        XCTAssertEqual(number("begins", from: status.label), 2, status.label)
        XCTAssertEqual(number("ends", from: status.label), 2, status.label)
        print("Long hold and repeated drag: \(status.label)")
    }

    @MainActor
    func testFirstNativeRotationDuringTracking() {
        let app = XCUIApplication(bundleIdentifier: "com.gorilla.map-interaction-checks")
        app.launchArguments = ["--gestures"]
        app.launch()
        let status = app.staticTexts["cameraStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        map.rotate(.pi / 4, withVelocity: .pi / 2)
        let heading = number("heading", from: status.label)
        XCTAssertGreaterThan(min(heading, 360 - heading), 15, status.label)
        XCTAssertEqual(number("begins", from: status.label), 1, status.label)
        XCTAssertEqual(number("ends", from: status.label), 1, status.label)
        print("Native rotation: \(status.label)")
    }

    @MainActor
    func testGorillaAppFirstSingleFingerDrag() {
        let app = XCUIApplication(bundleIdentifier: "com.gorilla.translation")
        app.launchArguments = ["--map-camera-checks"]
        app.launch()
        let toggle = app.buttons.matching(NSPredicate(format: "label IN %@", ["切换地图模式", "切換地圖模式", "Switch Map Mode", "地図モードを変更"])).firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 15), app.debugDescription)
        let canvas = app.otherElements["mapCameraChecks"]
        if !canvas.exists { toggle.tap() }
        XCTAssertTrue(canvas.waitForExistence(timeout: 15), app.debugDescription)
        let settled = NSPredicate { _, _ in
            let value = canvas.value as? String ?? ""
            return self.number("flying", from: value) == 0 && self.decimal("zoom", from: value) < 20000
        }
        expectation(for: settled, evaluatedWith: canvas)
        waitForExpectations(timeout: 15)
        let before = canvas.value as? String ?? ""
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.35))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.45)))
        let moved = NSPredicate { _, _ in
            let after = canvas.value as? String ?? ""
            return abs(self.decimal("latitude", from: after) - self.decimal("latitude", from: before)) +
                abs(self.decimal("longitude", from: after) - self.decimal("longitude", from: before)) > 0.0001
        }
        expectation(for: moved, evaluatedWith: canvas)
        waitForExpectations(timeout: 2)
        let after = canvas.value as? String ?? ""
        XCTAssertEqual(number("manual", from: after), 1, after)
        XCTAssertEqual(number("held", from: after), 0, after)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
        print("Gorilla app first drag: camera changed from \(before) to \(after)")
    }

    private func number(_ name: String, from status: String) -> Int {
        for field in status.split(separator: " ") {
            let parts = field.split(separator: "=")
            if parts.count == 2, parts[0] == name { return Int(parts[1]) ?? -1 }
        }
        return -1
    }

    private func decimal(_ name: String, from status: String) -> Double {
        for field in status.split(separator: " ") {
            let parts = field.split(separator: "=")
            if parts.count == 2, parts[0] == name { return Double(parts[1]) ?? .nan }
        }
        return .nan
    }
}
