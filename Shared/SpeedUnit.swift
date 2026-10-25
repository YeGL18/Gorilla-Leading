import Foundation

enum SpeedUnit: String, CaseIterable, Identifiable {
    case kilometresPerHour = "kmh"
    case milesPerHour = "mph"

    static let preferenceKey = "speedUnit"
    var id: String { rawValue }
    var symbol: String { self == .kilometresPerHour ? "km/h" : "mph" }

    static func resolve(_ raw: String?) -> Self {
        raw.flatMap(Self.init(rawValue:)) ?? .kilometresPerHour
    }

    func value(fromKmh speed: Double) -> Double {
        guard speed.isFinite else { return 0 }
        let kmh = max(0, speed)
        return self == .kilometresPerHour ? kmh : kmh / 1.609344
    }
}
