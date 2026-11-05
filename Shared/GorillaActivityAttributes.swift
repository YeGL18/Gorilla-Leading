import ActivityKit
import SwiftUI

enum ParkingEntryClock {
    static func ignoresVisit(arrival: Date, dismissedThrough: Date?) -> Bool {
        dismissedThrough.map { arrival <= $0 } ?? false
    }

    static func repeatInterval(heldFor elapsed: TimeInterval) -> TimeInterval {
        elapsed < 1.5 ? 0.3 : (elapsed < 3 ? 0.15 : 0.07)
    }
    static func restoredEntry(for arrival: Date, defaults: UserDefaults) -> Date {
        guard defaults.object(forKey: "parkingStartTime") as? Date == arrival,
              let entry = defaults.object(forKey: "parkingEntryTime") as? Date else { return arrival }
        return entry
    }

    static func adjustmentMinutes(entry: Date, arrival: Date) -> Int {
        Int((entry.timeIntervalSince(arrival) / 60).rounded())
    }

    static func save(arrival: Date, entry: Date, defaults: UserDefaults) {
        defaults.set(arrival, forKey: "parkingStartTime")
        defaults.set(entry, forKey: "parkingEntryTime")
    }
}

enum GorillaActivityLocalization {
    static let sharedLanguageKey = "gorillaAppLanguageCode"

    static var languageCode: String {
        UserDefaults(suiteName: "group.com.gorilla.translate")?.string(forKey: sharedLanguageKey)
            ?? Bundle.main.preferredLocalizations.first
            ?? "en"
    }

    static func string(_ key: String, languageCode: String? = nil) -> String {
        let requested = languageCode ?? self.languageCode
        let code = Bundle.preferredLocalizations(
            from: Bundle.main.localizations,
            forPreferences: [requested]
        ).first ?? "en"
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }
}

// MARK: - Activity State

/// The six live states shown in the Dynamic Island & Lock Screen.
/// Mirrors the app's visitStatus: 已停留 / 已泊車 / 已開車 / 已逗留 / 已步行 / 已騎車.
enum GorillaActivityState: String, Codable, Hashable {
    case stationary          // 停留中（開車期間靜止）— yellow, pause icon
    case parking             // 泊車中（開車到達）— teal, P icon
    case driving             // 開車中 — blue, car icon
    case nonAutomotiveParking // 逗留中（非開車到達）— orange, mappin icon
    case walking             // 步行中 — green, figure.walk icon
    case cycling             // 騎車中 — green, bicycle icon

    private var labelKey: String {
        switch self {
        case .stationary:          return "停留中"
        case .parking:             return "泊車中"
        case .driving:             return "開車中"
        case .nonAutomotiveParking: return "逗留中"
        case .walking:             return "步行中"
        case .cycling:             return "騎車中"
        }
    }

    var label: String { localizedLabel(languageCode: nil) }

    func localizedLabel(languageCode: String?) -> String {
        GorillaActivityLocalization.string(labelKey, languageCode: languageCode)
    }

    var color: Color {
        switch self {
        case .stationary: return Color(red: 1.0,   green: 0.84,  blue: 0.04)  // #FFD60A
        case .parking:
            // Read from App Group (shared between host app and widget extension)
            let defaults = UserDefaults(suiteName: "group.com.gorilla.translate") ?? .standard
            let hex = defaults.string(forKey: "parkingTimerColorHex") ?? "46ADB8"
            return Self.colorFromHex(hex) ?? Color(red: 0.275, green: 0.678, blue: 0.722)
        case .driving:             return Color(red: 0.0,   green: 0.596, blue: 1.0)   // #0098FF
        case .nonAutomotiveParking: return Color(red: 1.0,   green: 0.584, blue: 0.0)   // #FF9500
        case .walking:             return Color(red: 0.18,  green: 0.82,  blue: 0.35)   // #2ED177
        case .cycling:             return Color(red: 0.18,  green: 0.82,  blue: 0.35)   // #2ED177
        }
    }

    private static func colorFromHex(_ hex: String) -> Color? {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6 else { return nil }
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double(int >> 16) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }

    var symbol: String {
        switch self {
        case .stationary:          return "pause.fill"
        case .parking:             return "parkingsign"
        case .driving:             return "car.fill"
        case .nonAutomotiveParking: return "mappin.and.ellipse"
        case .walking:             return "figure.walk"
        case .cycling:             return "bicycle"
        }
    }
}

// MARK: - Activity Attributes

struct GorillaActivityAttributes: ActivityAttributes {
    /// Dynamic content that updates over the activity's lifetime.
    public struct ContentState: Codable, Hashable {
        var state: GorillaActivityState
        /// Anchor date for the live-updating timer.
        var startDate: Date
        // Parking context (泊車中 / 停留中)
        var location: String?   // 台北101
        var area: String?       // P1區域
        var floor: String?      // B2
        var spot: String?       // B1258
        // Legacy optional fields decode activities created by older builds.
        // New presentations and sync payloads no longer use speed, ETA or distance.
        var speedKmh: Int?      // 2
        var speedKmhExact: Double? = nil
        var speedUnitRaw: String? = nil
        var speedUnitSymbol: String { SpeedUnit.resolve(speedUnitRaw).symbol }
        var speedDisplay: String? {
            let kmh = speedKmhExact ?? speedKmh.map(Double.init)
            return kmh.map { String(Int(SpeedUnit.resolve(speedUnitRaw).value(fromKmh: $0))) }
        }
        var road: String?       // Sai Sha Rd 599
        var etaMinutes: Int?    // 39
        // Stationary context (停留中)
        var destinationName: String?  // 家
        var distanceText: String?     // 46.1 km
        /// The host app's selected language; optional for activities created by older builds.
        var languageCode: String? = nil
        /// Foreground-refresh nonce: guarantees the update payload differs from
        /// the archived render so the system re-renders with the latest widget
        /// binary (otherwise iOS can keep showing a stale render forever).
        /// Optional → old archived payloads decode fine (decodeIfPresent).
        var renderNonce: Int? = nil

        var stablePresentation: Self {
            var copy = self
            copy.speedKmh = nil
            copy.speedKmhExact = nil
            copy.speedUnitRaw = nil
            copy.etaMinutes = nil
            copy.distanceText = nil
            copy.road = nil
            return copy
        }
    }
}
