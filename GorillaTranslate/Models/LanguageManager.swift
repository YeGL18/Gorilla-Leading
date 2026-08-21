import Foundation
import SwiftUI

@MainActor
class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    @AppStorage("appLanguage") var currentLanguage: String = ""

    private init() {}

    func applyLanguage() {
        if currentLanguage.isEmpty {
            // 跟隨系統：移除 override
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([currentLanguage], forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()
    }

    var currentAppLanguage: AppLanguage {
        AppLanguage(rawValue: currentLanguage) ?? .system
    }
}
