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
        print("PASS: native language choices survive migration, repeated launch and legacy mismatch; saved data is unchanged")
    }
}
