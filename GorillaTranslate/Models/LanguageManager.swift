import Foundation
enum LanguageManager {
    @discardableResult
    static func syncSharedLanguage() -> Bool {
        guard let defaults = UserDefaults(suiteName: "group.com.gorilla.translate") else { return false }
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        guard defaults.string(forKey: GorillaActivityLocalization.sharedLanguageKey) != code else { return false }
        defaults.set(code, forKey: GorillaActivityLocalization.sharedLanguageKey)
        return true
    }

    static func migrateLegacyOverride(defaults: UserDefaults = .standard) {
        // AppleLanguages belongs to iOS's per-app language picker. Matching the old
        // preference does not prove it is ours, so never delete or rewrite it.
        defaults.removeObject(forKey: "appLanguage")
    }
}
