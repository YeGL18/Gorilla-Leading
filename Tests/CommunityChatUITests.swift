import XCTest

final class CommunityChatUITests: XCTestCase {
    func testIncomingAndOutgoingBubblesInBothAppearances() {
        for dark in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = dark ? ["--dark"] : []
            app.launch()
            let incoming = app.descendants(matching: .any).matching(identifier: "community.message.incoming")
            XCTAssertTrue(incoming.firstMatch.waitForExistence(timeout: 8))
            XCTAssertEqual(incoming.count, 2)
            XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "community.message.outgoing").count, 2)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = dark ? "Community chat dark" : "Community chat light"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.terminate()
        }
    }
}
