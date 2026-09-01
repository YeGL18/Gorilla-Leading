import ActivityKit
import SwiftUI

// MARK: - Activity State

/// The four live states shown in the Dynamic Island & Lock Screen.
/// Mirrors the app's visitStatus: 已停留 / 已泊車 / 已開車 / 已逗留(非開車).
enum GorillaActivityState: String, Codable, Hashable {
    case stationary          // 停留中（開車期間靜止）— yellow, pause icon
    case parking             // 泊車中（開車到達）— teal, P icon
    case driving             // 開車中 — blue, car icon
    case nonAutomotiveParking // 逗留中（非開車到達）— orange, mappin icon

    var label: String {
        switch self {
        case .stationary:          return "停留中"
        case .parking:             return "泊車中"
        case .driving:             return "開車中"
        case .nonAutomotiveParking: return "逗留中"
        }
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
        // Driving context (開車中) — road/eta also reused by 停留中
        var speedKmh: Int?      // 2
        var road: String?       // Sai Sha Rd 599
        var etaMinutes: Int?    // 39
        // Stationary context (停留中)
        var destinationName: String?  // 家
        var distanceText: String?     // 46.1 km
        /// Foreground-refresh nonce: guarantees the update payload differs from
        /// the archived render so the system re-renders with the latest widget
        /// binary (otherwise iOS can keep showing a stale render forever).
        /// Optional → old archived payloads decode fine (decodeIfPresent).
        var renderNonce: Int? = nil
    }
}
