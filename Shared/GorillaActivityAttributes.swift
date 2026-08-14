import ActivityKit
import SwiftUI

// MARK: - Activity State

/// The three live states shown in the Dynamic Island & Lock Screen.
/// Mirrors the app's visitStatus: 已停留 / 已泊車 / 已開車.
enum GorillaActivityState: String, Codable, Hashable {
    case stationary   // 停留中 — yellow, pause icon
    case parking      // 泊車中 — teal, P icon
    case driving      // 開車中 — blue, car icon

    var label: String {
        switch self {
        case .stationary: return "停留中"
        case .parking:    return "泊車中"
        case .driving:    return "開車中"
        }
    }

    var color: Color {
        switch self {
        case .stationary: return Color(red: 1.0,   green: 0.84,  blue: 0.04)  // #FFD60A
        case .parking:    return Color(red: 0.275, green: 0.678, blue: 0.722) // #46ADB8
        case .driving:    return Color(red: 0.0,   green: 0.596, blue: 1.0)   // #0098FF
        }
    }

    var symbol: String {
        switch self {
        case .stationary: return "pause.fill"
        case .parking:    return "parkingsign"
        case .driving:    return "car.fill"
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
