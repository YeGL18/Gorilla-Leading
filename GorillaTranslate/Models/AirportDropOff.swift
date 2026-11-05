import Foundation

/// Local guidance, not a live flight/terminal lookup. Data is supplied by the maintained airline table.
struct AirportDropOffCatalog: Decodable, Sendable {
    struct Airline: Decodable, Identifiable, Sendable {
        let iata: String
        let nameChinese: String
        let nameEnglish: String
        let terminal: String
        let checkInAisles: [String]
        let dropOffZones: [Int]
        var brandColorHex: String? = nil
        var id: String { iata + terminal + checkInAisles.joined(separator: ",") }

        func name(language: String) -> String {
            (language.hasPrefix("zh") || language.hasPrefix("yue")) ? nameChinese : nameEnglish
        }
        var isValid: Bool {
            iata.range(of: "^(?![0-9]{2})[A-Z0-9]{2}$", options: .regularExpression) != nil
                && !nameChinese.isEmpty && !nameEnglish.isEmpty
                && ["T1", "T2"].contains(terminal)
                && !checkInAisles.isEmpty
                && dropOffZones.allSatisfy { (terminal == "T1" ? [1, 2, 3, 4, 5] : [6, 7, 8, 9]).contains($0) }
                && (brandColorHex == nil || brandColorHex?.range(of: "^[A-Fa-f0-9]{6}$", options: .regularExpression) != nil)
        }
    }
    struct Zone: Decodable, Sendable {
        let terminal: String
        let number: Int
        let latitude: Double
        let longitude: Double
        let sourceURL: String
        var approximate: Bool? = nil
        var isApproximate: Bool { approximate == true }
        var isValid: Bool {
            ["T1", "T2"].contains(terminal)
                && (terminal == "T1" ? 1...5 : 6...9).contains(number)
                && (22.30...22.325).contains(latitude) && (113.923...113.95).contains(longitude)
                && URL(string: sourceURL)?.scheme == "https"
        }
    }
    var zones: [Zone]? = nil

    let updatedAt: String?
    let airlines: [Airline]
    static let empty = Self(updatedAt: nil, airlines: [])
    static let bundled = load()

    static func load(bundle: Bundle = .main) -> Self {
        guard let url = bundle.url(forResource: "airport_drop_off", withExtension: "json"),
              let data = try? Data(contentsOf: url), let catalog = try? decode(data) else { return .empty }
        return catalog
    }
    static func decode(_ data: Data) throws -> Self {
        let catalog = try JSONDecoder().decode(Self.self, from: data)
        guard (catalog.zones ?? []).allSatisfy(\.isValid), catalog.airlines.allSatisfy(\.isValid),
              Set(catalog.airlines.map(\.id)).count == catalog.airlines.count else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return catalog
    }
    static func airlineCode(from input: String) -> String? {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized.range(of: "^(?![0-9]{2})[A-Z0-9]{2}(?:\\s*[0-9]{1,4}[A-Z]?)?$", options: .regularExpression) != nil else { return nil }
        return String(normalized.prefix(2))
    }
    func lookup(_ input: String) -> [Airline] {
        guard let code = Self.airlineCode(from: input) else { return [] }
        return airlines.filter { $0.iata == code }
    }

    static func formattedDistance(_ meters: Double) -> String? {
        guard meters.isFinite, meters >= 0 else { return nil }
        if meters < 1000 { return "\(Int(meters)) m" }
        return String(format: "%.1f km", meters / 1000)
    }
}
