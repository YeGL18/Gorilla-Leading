import Foundation

@main struct AirportDropOffChecks {
    static func main() throws {
        for (input, expected) in [("CX639", "CX"), (" cx 639 ", "CX"), ("CX", "CX"), ("5J639", "5J"), ("D7639", "D7"), ("Z2639", "Z2"), ("3K639", "3K"), ("ab1234A", "AB")] {
            precondition(AirportDropOffCatalog.airlineCode(from: input) == expected)
        }
        for input in ["", "C", "123", "CATHAY639", "CX639123", "🙂CX639", "CX-639"] {
            precondition(AirportDropOffCatalog.airlineCode(from: input) == nil)
        }
        // Fictional records exercise matching; they are not bundled airport guidance.
        let fixture = Data(#"{"updatedAt":"2026-11-04","airlines":[{"iata":"ZZ","nameChinese":"測試航空","nameEnglish":"Test Air","terminal":"T1","checkInAisles":["A","B"],"dropOffZones":[1,2]}]}"#.utf8)
        let catalog = try AirportDropOffCatalog.decode(fixture)
        precondition(catalog.lookup("ZZ639").first?.name(language: "zh-Hant") == "測試航空")
        precondition(catalog.lookup("ZZ639").first?.name(language: "en") == "Test Air")
        precondition(catalog.lookup("YY639").isEmpty)
        precondition(AirportDropOffCatalog.empty.lookup("ZZ639").isEmpty)
        let invalid = Data(String(decoding: fixture, as: UTF8.self).replacingOccurrences(of: "[1,2]", with: "[9]").utf8)
        do { _ = try AirportDropOffCatalog.decode(invalid); preconditionFailure("T1 cannot recommend a T2 zone") }
        catch {}
        let bundled = try AirportDropOffCatalog.decode(Data(contentsOf: URL(fileURLWithPath: "GorillaTranslate/Resources/airport_drop_off.json")))
        precondition(bundled.airlines.count == 95)
        precondition(bundled.lookup("5J639").first?.terminal == "T2")
        precondition(bundled.lookup("AC639").first?.checkInAisles == ["H"])
        precondition(bundled.lookup("KA639").isEmpty && bundled.lookup("I5639").isEmpty)
        precondition(bundled.lookup("CX639").first?.dropOffZones == [1])
        precondition(bundled.lookup("AC639").first?.dropOffZones == [4])
        precondition(bundled.lookup("HX639").first?.dropOffZones == [6])
        precondition(bundled.lookup("UO639").first?.dropOffZones == [8])
        precondition(bundled.lookup("AK639").first?.dropOffZones == [9])
        precondition(bundled.airlines.filter { $0.dropOffZones.isEmpty }.map(\.iata).sorted() == ["5J", "7C", "PG"])
        let zones = bundled.zones ?? []
        precondition(zones.count == 9 && zones.allSatisfy { $0.isValid && $0.isApproximate })
        precondition(Set(zones.map { "\($0.terminal)-\($0.number)" }).count == 9)
        let t1 = zones.filter { $0.terminal == "T1" }.sorted { $0.number < $1.number }
        let t2 = zones.filter { $0.terminal == "T2" }.sorted { $0.number < $1.number }
        precondition(t1.map(\.number) == [1,2,3,4,5] && t2.map(\.number) == [6,7,8,9])
        precondition(zip(t1,t1.dropFirst()).allSatisfy { $0.latitude < $1.latitude }, "T1 runs south to north")
        precondition(zip(t2,t2.dropFirst()).allSatisfy { $0.latitude > $1.latitude }, "T2 runs north to south")
        precondition(t1.allSatisfy { $0.longitude < 113.9366 } && t2.allSatisfy { $0.longitude > 113.9369 },
            "Terminal recommendations stay on the separate departure roads")
        precondition(bundled.airlines.allSatisfy { $0.brandColorHex != nil })
        precondition(bundled.lookup("CX639").first?.brandColorHex == "005D63")
        for (meters, expected) in [(0.0, "0 m"), (250.0, "250 m"), (999.9, "999 m"),
                                   (1000.0, "1.0 km"), (1530.0, "1.5 km"), (25400.0, "25.4 km")] {
            precondition(AirportDropOffCatalog.formattedDistance(meters) == expected)
        }
        precondition(AirportDropOffCatalog.formattedDistance(-1) == nil)
        precondition(AirportDropOffCatalog.formattedDistance(.infinity) == nil)
        precondition(AirportDropOffCatalog.formattedDistance(.nan) == nil)
        let badPoint = AirportDropOffCatalog.Zone(terminal: "T1", number: 1, latitude: 22.24823,
            longitude: 113.91872, sourceURL: "https://example.invalid/test")
        precondition(!badPoint.isValid, "Original off-airport points must never become navigation targets")
        print("Airport drop-off parser, matching, localization and terminal/zone validation passed")
    }
}
