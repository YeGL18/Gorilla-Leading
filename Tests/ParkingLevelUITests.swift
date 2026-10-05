import XCTest

final class ParkingLevelUITests: XCTestCase {
    func testNativeFloorGroupingAndNaming() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_HK"]
        app.launch()
        let ground = app.staticTexts["parkingFloorGroup-0"]
        XCTAssertTrue(ground.waitForExistence(timeout: 10))
        ground.tap()
        let name = app.buttons["Name This Floor"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Drop-off")
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.staticTexts["Drop-off"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["parkingFloorGroup--1"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Named ground floor and separate basement levels"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testNativeFacilityScopeAndPointDetails() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_HK"]
        app.launch()
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Residence'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Facility Floors"].waitForExistence(timeout: 5))
        let point = app.buttons.matching(NSPredicate(format: "label CONTAINS 'B3'")).firstMatch
        if !point.isHittable { app.swipeUp() }
        point.tap()
        XCTAssertTrue(app.staticTexts["Starting Floor"].waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Native parking point detail"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
