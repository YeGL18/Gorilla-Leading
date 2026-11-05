import XCTest

final class CameraSpeechUITests: XCTestCase {
    func testEnglishLanguageSelectionAndVoiceGuide() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let language = app.buttons["cameraSpeechLanguage"]
        XCTAssertTrue(language.waitForExistence(timeout: 10))
        XCTAssertTrue(language.label.contains("Follow app language"))
        language.tap()
        app.buttons["日本語"].tap()
        XCTAssertTrue(language.label.contains("日本語"))
        app.buttons["Voices & Downloads"].tap()
        XCTAssertTrue(app.staticTexts["Automatic voice"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["cameraVoiceLanguage"].firstMatch.value as? String, "日本語")
        attach("Automatic Japanese voice and system fallback", app: app)
        app.terminate()
        app.launch()
        language.tap()
        app.buttons["Follow system language"].tap()
        XCTAssertTrue(language.label.contains("Follow system language"))
        let format = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Spoken Alert")).firstMatch
        format.tap()
        app.buttons["Two beeps only"].tap()
        XCTAssertFalse(language.exists)
        attach("Beeps only hides speech-only settings", app: app)
    }

    func testTraditionalChineseAndCantoneseInDarkMode() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_HK", "--dark"]
        app.launch()
        let language = app.buttons["cameraSpeechLanguage"]
        XCTAssertTrue(language.waitForExistence(timeout: 10))
        XCTAssertTrue(language.label.contains("跟隨 App 語言"))
        language.tap()
        app.buttons["粵語"].tap()
        XCTAssertTrue(language.label.contains("粵語"))
        app.buttons["聲線與下載"].tap()
        XCTAssertTrue(app.staticTexts["自動聲線"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["cameraVoiceLanguage"].firstMatch.value as? String, "粵語")
        attach("Cantonese voice guide in Traditional Chinese dark appearance", app: app)
    }

    func testLocalizedSettingsAcrossScripts() throws {
        struct LanguageExpectation: Decodable { let language: String; let title: String; let automatic: String }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "LanguageExpectations", withExtension: "json"))
        let rows = try JSONDecoder().decode([LanguageExpectation].self, from: Data(contentsOf: url))
        XCTAssertEqual(rows.count, 20)
        for row in rows where ["de", "fr", "ru", "th", "ko", "yue"].contains(row.language) {
            let app = XCUIApplication()
            app.launchArguments = ["-AppleLanguages", "(\(row.language))", "-AppleLocale", row.language]
            app.launch()
            XCTAssertTrue(app.staticTexts[row.title].firstMatch.waitForExistence(timeout: 10), row.language)
            XCTAssertTrue(app.buttons["cameraSpeechLanguage"].exists, row.language)
            attach("Localized camera settings: " + row.language, app: app)
            app.buttons["cameraVoiceHelp"].tap()
            XCTAssertTrue(app.staticTexts[row.automatic].firstMatch.waitForExistence(timeout: 5), row.language)
            attach("Automatic voice guide: " + row.language, app: app)
            app.terminate()
        }
    }

    private func attach(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
