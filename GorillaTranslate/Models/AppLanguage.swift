import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system = ""
    case english = "en"
    case traditionalChinese = "zh-Hant"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "跟隨系統"
        case .english: return "English"
        case .traditionalChinese: return "繁體中文"
        }
    }

    var flag: String {
        switch self {
        case .system: return "🌐"
        case .english: return "🇺🇸"
        case .traditionalChinese: return "🇹🇼"
        }
    }
}
