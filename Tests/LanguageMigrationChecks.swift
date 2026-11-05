import Foundation

// Standalone harness for LanguageManager.swift, without the widget target.
enum GorillaActivityLocalization {
    static let sharedLanguageKey = "gorillaAppLanguageCode"
}

@main
enum LanguageMigrationChecks {
    static func main() {
        let suite = "gorilla-language-migration-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        for nativeLanguage in ["zh-Hant", "zh-Hans", "ja", "en"] {
            defaults.removePersistentDomain(forName: suite)
            defaults.set([nativeLanguage], forKey: "AppleLanguages")
            defaults.set(nativeLanguage, forKey: "appLanguage")
            let savedRecords = Data("saved destination snapshot".utf8)
            defaults.set(savedRecords, forKey: "saved_destinations")
            defaults.set("selected destination", forKey: "selected_destination_id")
            defaults.set(true, forKey: "hasCompletedLeadingOnboarding")

            LanguageManager.migrateLegacyOverride(defaults: defaults)
            precondition(defaults.array(forKey: "AppleLanguages") as? [String] == [nativeLanguage])
            precondition(defaults.object(forKey: "appLanguage") == nil)
            precondition(defaults.data(forKey: "saved_destinations") == savedRecords)
            precondition(defaults.string(forKey: "selected_destination_id") == "selected destination")
            precondition(defaults.bool(forKey: "hasCompletedLeadingOnboarding"))

            LanguageManager.migrateLegacyOverride(defaults: defaults)
            precondition(defaults.array(forKey: "AppleLanguages") as? [String] == [nativeLanguage])
        }

        defaults.set("en", forKey: "appLanguage")
        defaults.set(["zh-Hant", "en"], forKey: "AppleLanguages")
        LanguageManager.migrateLegacyOverride(defaults: defaults)
        precondition(defaults.array(forKey: "AppleLanguages") as? [String] == ["zh-Hant", "en"])
        let supported = ["en", "zh-Hant", "yue", "zh-Hans", "ja", "ko", "fr", "de", "es", "pt", "it", "nl", "pl", "tr", "ru", "uk", "id", "ms", "th", "vi", "Base"]
        for language in supported.filter({ $0 != "Base" }) {
            precondition(LanguageManager.resolveLanguage(appLanguages: [language],
                preferredLanguages: ["en"], localizations: supported) == language,
                "The native app override must win over the system language")
        }
        precondition(LanguageManager.resolveLanguage(appLanguages: ["yue-Hant-HK"],
            preferredLanguages: ["en"], localizations: supported) == "yue")
        precondition(LanguageManager.resolveLanguage(appLanguages: ["zh-Hant-HK"],
            preferredLanguages: ["en"], localizations: supported) == "zh-Hant")
        precondition(LanguageManager.resolveLanguage(appLanguages: nil,
            preferredLanguages: ["ja", "en"], localizations: supported) == "ja")
        precondition(LanguageManager.resolveLanguage(appLanguages: [],
            preferredLanguages: ["en"], localizations: supported) == "en")
        if Bundle.main.bundleIdentifier == "com.gorilla.language-regression" {
            defer { UserDefaults.standard.removePersistentDomain(forName: "com.gorilla.language-regression") }
            UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
            _ = Bundle.main.preferredLocalizations
            LanguageManager.refresh()
            precondition(String(localized: "語言") == "Language")
            UserDefaults.standard.set(["zh-Hant"], forKey: "AppleLanguages")
            LanguageManager.refresh()
            precondition(LanguageManager.languageCode == "zh-Hant")
            precondition(String(localized: "語言") == "語言",
                         "Localized strings must recover without restarting the process")
            UserDefaults.standard.set(["ja"], forKey: "AppleLanguages")
            LanguageManager.refresh()
            precondition(String(localized: "語言") == "言語")
            print("PASS: explicit translations switch after the main bundle language was already read")
        }
        print("PASS: native language choices survive migration, repeated launch and legacy mismatch; saved data is unchanged")
    }
}
