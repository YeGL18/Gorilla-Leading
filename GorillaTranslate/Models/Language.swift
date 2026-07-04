import Foundation
import NaturalLanguage

enum Language: String, CaseIterable, Identifiable {
    case english = "en"
    case chinese = "zh"
    case japanese = "ja"
    case korean = "ko"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case portuguese = "pt"
    case russian = "ru"
    case vietnamese = "vi"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "中文"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .spanish: return "Español"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .italian: return "Italiano"
        case .portuguese: return "Português"
        case .russian: return "Русский"
        case .vietnamese: return "Tiếng Việt"
        }
    }
    
    var flag: String {
        switch self {
        case .english: return "🇺🇸"
        case .chinese: return "🇨🇳"
        case .japanese: return "🇯🇵"
        case .korean: return "🇰🇷"
        case .spanish: return "🇪🇸"
        case .french: return "🇫🇷"
        case .german: return "🇩🇪"
        case .italian: return "🇮🇹"
        case .portuguese: return "🇧🇷"
        case .russian: return "🇷🇺"
        case .vietnamese: return "🇻🇳"
        }
    }
    
    var nlLanguage: NLLanguage {
        return NLLanguage(rawValue: rawValue)
    }
    
    var localeIdentifier: String {
        return rawValue
    }
    
    var speechLocale: Locale {
        switch self {
        case .english: return Locale(identifier: "en-US")
        case .chinese: return Locale(identifier: "zh-CN")
        case .japanese: return Locale(identifier: "ja-JP")
        case .korean: return Locale(identifier: "ko-KR")
        case .spanish: return Locale(identifier: "es-ES")
        case .french: return Locale(identifier: "fr-FR")
        case .german: return Locale(identifier: "de-DE")
        case .italian: return Locale(identifier: "it-IT")
        case .portuguese: return Locale(identifier: "pt-BR")
        case .russian: return Locale(identifier: "ru-RU")
        case .vietnamese: return Locale(identifier: "vi-VN")
        }
    }
}