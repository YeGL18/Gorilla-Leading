import Foundation
enum LanguageManager {
    private final class Selection: @unchecked Sendable {
        private let lock = NSLock()
        private var code: String?

        func read() -> String? {
            lock.lock()
            defer { lock.unlock() }
            return code
        }

        func update(_ value: String) {
            lock.lock()
            defer { lock.unlock() }
            code = value
        }
    }

    private static let selection = Selection()
    private static let localizedBundles = NSCache<NSString, Bundle>()

    static func resolveLanguage(appLanguages: [String]?, preferredLanguages: [String],
                                localizations: [String]) -> String {
        let supported = localizations.filter { $0 != "Base" }
        let preferences: [String]
        if let appLanguages, !appLanguages.isEmpty { preferences = appLanguages }
        else { preferences = preferredLanguages }
        return Bundle.preferredLocalizations(from: supported, forPreferences: preferences).first ?? "en"
    }

    static var languageCode: String {
        if let cached = selection.read() { return cached }
        return readLanguageCode()
    }

    private static func readLanguageCode() -> String {
        let defaults = UserDefaults.standard
        let domain = Bundle.main.bundleIdentifier.flatMap { defaults.persistentDomain(forName: $0) }
        return resolveLanguage(appLanguages: domain?["AppleLanguages"] as? [String],
                               preferredLanguages: defaults.stringArray(forKey: "AppleLanguages") ?? Locale.preferredLanguages,
                               localizations: Bundle.main.localizations)
    }

    /// Call only after protected preferences become available, and on returning from Settings.
    static func refresh() {
        selection.update(readLanguageCode())
    }

    static var locale: Locale { Locale(identifier: languageCode) }

    static var bundle: Bundle {
        let code = languageCode
        if let cached = localizedBundles.object(forKey: code as NSString) { return cached }
        // Select an explicit lproj instead of relying on the main bundle's launch-time language cache.
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let localized = Bundle(path: path) else { return .main }
        localizedBundles.setObject(localized, forKey: code as NSString)
        return localized
    }

    @discardableResult
    static func syncSharedLanguage() -> Bool {
        guard let defaults = UserDefaults(suiteName: "group.com.gorilla.translate") else { return false }
        let code = languageCode
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

extension String {
    init(localized value: String.LocalizationValue) {
        self.init(localized: value, bundle: LanguageManager.bundle, locale: LanguageManager.locale)
    }
}
