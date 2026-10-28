import XCTest

final class ColorGroupUITests: XCTestCase {
    func testOriginalLaunchToggleRemainsWithoutTheRemovedDotStyle() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-launchAnimationStyle", "1"]
        app.launch()
        let toggle = app.switches["launchAnimationEnabled"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        if toggle.value as? String == "0" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        }
        XCTAssertFalse(app.buttons["launchAnimationStyle"].exists)
        XCTAssertFalse(app.buttons["previewLaunchAnimation"].exists)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertEqual(toggle.value as? String, "0")
        XCTAssertFalse(app.buttons["launchAnimationStyle"].exists)
    }

    func testTimelineIsAFirstClassVisualTheme() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetColorGroup", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let picker = app.buttons["colorGroupMode"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        picker.tap()
        app.buttons["Timeline"].tap()
        app.buttons["orbEffectsSettings"].tap()
        XCTAssertTrue(app.staticTexts["Preview Time"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Background Effect"].exists)
        XCTAssertFalse(app.buttons["orbCanvasDitherEnabled"].exists)
        app.terminate()
        app.launchArguments.removeAll { $0 == "-resetColorGroup" }
        app.launch()
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        XCTAssertTrue(picker.label.contains("Timeline"))
        picker.tap()
        app.buttons["Orbs"].tap()
        app.buttons["orbEffectsSettings"].tap()
        XCTAssertTrue(app.buttons["orbCanvasDitherEnabled"].waitForExistence(timeout: 5))
    }

    func testM3OrbControlsAreUserControlled() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetColorGroup", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["colorGroupMode"].waitForExistence(timeout: 10))
        app.buttons["colorGroupMode"].tap()
        app.buttons["M3 Concept"].tap()
        app.buttons["orbEffectsSettings"].tap()
        let master = app.switches["orbMasterEnabled"]
        XCTAssertTrue(master.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["orbCanvasDitherEnabled"].exists)
        XCTAssertFalse(app.staticTexts["Orb Color Scheme"].exists)
        master.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        let off = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '0'"), object: master)
        XCTAssertEqual(XCTWaiter.wait(for: [off], timeout: 5), .completed)
        XCTAssertFalse(app.buttons["orbCanvasDitherEnabled"].exists)
        capture("M3 orb effects disabled")
        master.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["orbCanvasDitherEnabled"].waitForExistence(timeout: 5))
    }

    func testM3HomeOrbsInBothRenderers() {
        for native in [true, false] {
            XCUIDevice.shared.orientation = .portrait
            let app = XCUIApplication()
            app.launchArguments = ["-homeM3"] + (native ? ["-nativeOrbs"] : [])
            app.launch()
            XCTAssertTrue(app.staticTexts["Gorilla"].waitForExistence(timeout: 10))
            let rendered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let image = app.screenshot().image
                let region = app.frame.insetBy(dx: app.frame.width * 0.05, dy: app.frame.height * 0.15)
                return self.warmPixels(in: image, frame: region, screen: app.frame) > 500
                    && self.warmPixels(in: image, frame: region, screen: app.frame, yellow: true) > 500
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [rendered], timeout: 10), .completed)
            capture("M3 home orbs portrait \(native ? "native" : "canvas")")
            XCUIDevice.shared.orientation = .landscapeLeft
            let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                app.frame.width > app.frame.height
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 10), .completed)
            capture("M3 home orbs landscape \(native ? "native" : "canvas")")
            app.terminate()
        }
        XCUIDevice.shared.orientation = .portrait
    }

    func testSelectionPersistenceAndRenderedDots() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-resetColorGroup", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let picker = app.buttons["colorGroupMode"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["orbControls"].exists)
        picker.tap()
        app.buttons["M3 Concept"].tap()
        XCTAssertTrue(app.staticTexts["orbControls"].exists)
        XCTAssertEqual(app.staticTexts["dotColor"].label, "#EF363B")
        let canvas = app.webViews.firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        let rendered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.warmPixels(in: app.screenshot().image, frame: canvas.frame, screen: app.frame) > 200
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rendered], timeout: 10), .completed)
        capture("M3 Concept rendered dots portrait")
        app.terminate()
        app.launchArguments.removeAll { $0 == "-resetColorGroup" }
        app.launch()
        XCTAssertTrue(app.staticTexts["dotColor"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["dotColor"].label, "#EF363B")
        picker.tap()
        app.buttons["Dark Knight Mode"].tap()
        XCTAssertFalse(app.staticTexts["orbControls"].exists)
        XCTAssertNotEqual(app.staticTexts["dotColor"].label, "#EF363B")
        picker.tap()
        app.buttons["Normal Mode"].tap()
        XCTAssertTrue(app.staticTexts["orbControls"].exists)
        XCTAssertEqual(app.staticTexts["dotColor"].label, "#ffd700")
        picker.tap()
        app.buttons["M3 Concept"].tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.width > app.frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 10), .completed)
        app.swipeUp()
        capture("M3 Concept rendered dots landscape")
        XCUIDevice.shared.orientation = .portrait
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func warmPixels(in image: UIImage, frame: CGRect, screen: CGRect, yellow: Bool = false) -> Int {
        guard let source = image.cgImage else { return 0 }
        let width = source.width, height = source.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return 0 }
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        let sx = CGFloat(width) / screen.width, sy = CGFloat(height) / screen.height
        let left = max(0, Int(frame.minX * sx)), right = min(width, Int(frame.maxX * sx))
        let top = max(0, Int(frame.minY * sy)), bottom = min(height, Int(frame.maxY * sy))
        guard right > left, bottom > top else { return 0 }
        var count = 0
        for y in stride(from: top, to: bottom, by: 2) {
            for x in stride(from: left, to: right, by: 2) {
                let i = (y * width + x) * 4
                let r = Double(bytes[i]), g = Double(bytes[i + 1]), b = Double(bytes[i + 2])
                if yellow {
                    if r > 45 && g > 45 && min(r, g) > b * 2 && abs(r - g) < 55 { count += 1 }
                } else if r > 100 && r > g * 1.8 && r > b * 1.8 { count += 1 }
            }
        }
        return count
    }
}
