import Foundation
enum LanguageManager {
    static func migrateLegacyOverride() {
        let defaults = UserDefaults.standard
        // Only remove an override known to have come from the old in-app picker.
        // Otherwise AppleLanguages may contain the user's system-managed choice.
        if let legacy = defaults.string(forKey: "appLanguage"), !legacy.isEmpty,
           let languages = defaults.array(forKey: "AppleLanguages") as? [String],
           languages == [legacy] {
            defaults.removeObject(forKey: "AppleLanguages")
        }
        defaults.removeObject(forKey: "appLanguage")
    }
}
