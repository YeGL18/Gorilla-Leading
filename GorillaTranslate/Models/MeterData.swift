import Foundation
import CoreLocation

enum MeterVehicle: String, CaseIterable, Identifiable {
    case unset, privateCar, taxi, lightGoods, mediumHeavyGoods, coach
    var id: String { rawValue }
    var title: String {
        switch self {
        case .unset: return "請選擇車型"
        case .privateCar: return "私家車"
        case .taxi: return "的士"
        case .lightGoods: return "輕型貨車"
        case .mediumHeavyGoods: return "中／重型貨車"
        case .coach: return "巴士／旅遊巴"
        }
    }
}

enum MeterBayType: String, CaseIterable {
    case general = "A", goods = "G", coach = "C", unknown = "?"
    var title: String {
        switch self {
        case .general: return "一般車輛"
        case .goods: return "貨車"
        case .coach: return "巴士／旅遊巴"
        case .unknown: return "車型未提供"
        }
    }
    var symbol: String {
        switch self {
        case .general: return "car.fill"
        case .goods: return "truck.box.fill"
        case .coach: return "bus.fill"
        case .unknown: return "questionmark"
        }
    }
    var detail: String {
        self == .general ? "不包括中／重型貨車、巴士、電單車及單車" : title
    }
    func accepts(_ vehicle: MeterVehicle) -> Bool {
        switch self {
        case .general: return [.privateCar, .taxi, .lightGoods].contains(vehicle)
        case .goods: return [.lightGoods, .mediumHeavyGoods].contains(vehicle)
        case .coach: return vehicle == .coach
        case .unknown: return false
        }
    }
}

struct ParkingMeter: Identifiable, Hashable {
    let id: String
    let poleId: String
    let district: String
    let street: String
    let streetKey: String
    let latitude: Double
    let longitude: Double
    let bayType: MeterBayType
    let lpp: Int?
    let operatingPeriod: String
    let paymentUnit: Double?
    let timeUnit: Int?
    var isTest: Bool { (Int(poleId) ?? 0) > 90000 }
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var location: CLLocation { .init(latitude: latitude, longitude: longitude) }
    var feeText: String {
        guard let timeUnit, timeUnit > 0, let paymentUnit, paymentUnit >= 0 else { return "收費暫無資料" }
        return "\(timeUnit) 分鐘 / HK$\(String(format: "%.2f", paymentUnit))"
    }
    var limitText: String {
        guard let lpp, lpp > 0 else { return "泊車時限暫無資料" }
        return lpp % 60 == 0 ? "每次最長可購買 \(lpp / 60) 小時" : "每次最長可購買 \(lpp) 分鐘"
    }
    var hoursText: String {
        let code = operatingPeriod.filter { !$0.isNumber }
        let values = [
            "A": "星期一至六 08:00–24:00（公眾假期除外）",
            "B": "星期一至六 08:00–20:00（公眾假期除外）",
            "D": "星期一至六 08:00–24:00；星期日及公眾假期 10:00–22:00",
            "E": "每日 07:00–20:00", "F": "每日 08:00–21:00", "G": "每日 07:00–19:00",
            "H": "每日 08:00–20:00", "J": "每日 08:00–24:00", "N": "每日 19:00–24:00",
            "P": "星期一至六 08:00–20:00；星期日禁止泊車",
            "Q": "星期一至六 08:00–20:00；星期日及公眾假期 10:00–22:00",
            "S": "星期一至五 17:00–24:00（08:00–17:00 禁止泊車）；星期六 08:00–24:00；星期日及公眾假期 10:00–22:00",
            "T": "星期一至五 17:30–24:00；星期六 08:00–24:00；星期日及公眾假期 10:00–24:00"
        ]
        return values[code] ?? "收費時段暫無資料（\(operatingPeriod)）"
    }
}

struct MeterStatus: Equatable {
    let isOperating: Bool
    let occupancy: String
    let changedAt: String
}

enum MeterDisplayState: String, CaseIterable {
    case vacant, incompatible, occupied, unknown
    var title: String {
        switch self {
        case .vacant: return "空置"
        case .incompatible: return "空置 · 不適用所選車型"
        case .occupied: return "被佔用"
        case .unknown: return "未知"
        }
    }
    static func resolve(meter: ParkingMeter, status: MeterStatus?, vehicle: MeterVehicle,
                        fetchedAt: Date?, now: Date = Date()) -> Self {
        guard !meter.isTest, let fetchedAt, now.timeIntervalSince(fetchedAt) <= 180,
              let status, status.isOperating else { return .unknown }
        if status.occupancy == "O" { return .occupied }
        guard status.occupancy == "V" else { return .unknown }
        if vehicle == .unset { return .vacant }
        guard meter.bayType != .unknown else { return .unknown }
        return meter.bayType.accepts(vehicle) ? .vacant : .incompatible
    }
    static func cluster(_ states: [Self]) -> Self {
        if states.contains(.vacant) { return .vacant }
        if states.contains(.incompatible) { return .incompatible }
        if !states.isEmpty && states.allSatisfy({ $0 == .occupied }) { return .occupied }
        return .unknown
    }
}

enum MeterCSV {
    enum ParseError: Error { case missingHeader, emptyDataset, malformedQuotes }

    // The provider includes a date and blank record before the location header.
    // Parse quoted fields before locating the header, rather than assuming row offsets.
    static func rows(_ text: String) throws -> [[String]] {
        let chars = Array(text.replacingOccurrences(of: "\u{FEFF}", with: ""))
        var result: [[String]] = [], row: [String] = []
        var field = "", quoted = false, i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                if quoted && i + 1 < chars.count && chars[i + 1] == "\"" {
                    field.append("\""); i += 1
                } else { quoted.toggle() }
            } else if c == "," && !quoted {
                row.append(field.trimmingCharacters(in: .whitespaces)); field = ""
            } else if (c == "\n" || c == "\r" || c == "\r\n") && !quoted {
                row.append(field.trimmingCharacters(in: .whitespaces)); field = ""
                if row.contains(where: { !$0.isEmpty }) { result.append(row) }
                row = []
                if c == "\r" && i + 1 < chars.count && chars[i + 1] == "\n" { i += 1 }
            } else { field.append(c) }
            i += 1
        }
        guard !quoted else { throw ParseError.malformedQuotes }
        row.append(field.trimmingCharacters(in: .whitespaces))
        if row.contains(where: { !$0.isEmpty }) { result.append(row) }
        return result
    }

    static func records(_ text: String, required: [String]) throws -> [[String: String]] {
        let rows = try rows(text)
        guard let index = rows.firstIndex(where: { Set(required).isSubset(of: Set($0)) }) else {
            throw ParseError.missingHeader
        }
        let header = rows[index]
        guard Set(header).count == header.count else { throw ParseError.missingHeader }
        return rows.dropFirst(index + 1).compactMap { row in
            guard row.count == header.count else { return nil }
            return Dictionary(uniqueKeysWithValues: zip(header, row))
        }
    }

    static func spaces(_ text: String) throws -> [ParkingMeter] {
        let records = try records(text, required: ["PoleId", "ParkingSpaceId", "Latitude", "Longitude", "VehicleType", "Street"])
        var unique: [String: ParkingMeter] = [:]
        for row in records {
            guard let id = row["ParkingSpaceId"], !id.isEmpty,
                  let lat = Double(row["Latitude"] ?? ""), let lon = Double(row["Longitude"] ?? ""),
                  (22...23).contains(lat), (113.5...115).contains(lon) else { continue }
            let district = row["District_tc"].flatMap { $0.isEmpty ? nil : $0 } ?? row["District"] ?? ""
            let street = row["Street_tc"].flatMap { $0.isEmpty ? nil : $0 } ?? row["Street"] ?? ""
            let key = [row["Region"] ?? "", row["District"] ?? "", row["Street"] ?? ""].joined(separator: "|")
            unique[id] = ParkingMeter(id: id, poleId: row["PoleId"] ?? "", district: district, street: street,
                                     streetKey: street.isEmpty ? id : key, latitude: lat, longitude: lon,
                                     bayType: MeterBayType(rawValue: (row["VehicleType"] ?? "").uppercased()) ?? .unknown,
                                     lpp: Int(row["LPP"] ?? ""), operatingPeriod: row["OperatingPeriod"] ?? "",
                                     paymentUnit: Double(row["PaymentUnit"] ?? ""), timeUnit: Int(row["TimeUnit"] ?? ""))
        }
        guard !unique.isEmpty else { throw ParseError.emptyDataset }
        return unique.values.sorted { $0.id < $1.id }
    }

    static func statuses(_ text: String) throws -> [String: MeterStatus] {
        let records = try records(text, required: ["ParkingSpaceId", "ParkingMeterStatus", "OccupancyStatus"])
        var result: [String: MeterStatus] = [:]
        for row in records {
            guard let id = row["ParkingSpaceId"], !id.isEmpty else { continue }
            result[id] = MeterStatus(isOperating: row["ParkingMeterStatus"]?.uppercased() == "N",
                                     occupancy: (row["OccupancyStatus"] ?? "").uppercased(), changedAt: row["OccupancyDateChanged"] ?? "")
        }
        guard !result.isEmpty else { throw ParseError.emptyDataset }
        return result
    }
}

struct MeterSpatialIndex {
    private var cells: [String: [ParkingMeter]] = [:]
    init(_ meters: [ParkingMeter]) {
        for meter in meters where !meter.isTest {
            cells[Self.key(Int(floor(meter.latitude * 100)), Int(floor(meter.longitude * 100))), default: []].append(meter)
        }
    }
    private static func key(_ lat: Int, _ lon: Int) -> String { "\(lat):\(lon)" }
    func nearby(_ location: CLLocation, radius: Double) -> [ParkingMeter] {
        let delta = radius / 100_000 + 0.001
        let lat = location.coordinate.latitude, lon = location.coordinate.longitude
        guard lat.isFinite, lon.isFinite, (21...24).contains(lat), (112...116).contains(lon) else { return [] }
        var result: [ParkingMeter] = []
        for x in Int(floor((lat - delta) * 100))...Int(floor((lat + delta) * 100)) {
            for y in Int(floor((lon - delta) * 100))...Int(floor((lon + delta) * 100)) {
                result += (cells[Self.key(x, y)] ?? []).filter { $0.location.distance(from: location) <= radius }
            }
        }
        return result
    }
}

struct MeterVisibility {
    private(set) var speedAllowsDisplay = true
    private var speedTransitionAt: Date?
    private var lastStreetSeen: [String: Date] = [:]
    mutating func reset() { self = Self() }
    mutating func update(candidates: [ParkingMeter], location: CLLocation, speed: Double, radius: Double, now: Date) -> [ParkingMeter] {
        let requested = speed >= 0 && speed <= 50
        if requested == speedAllowsDisplay { speedTransitionAt = nil }
        else {
            if speedTransitionAt == nil { speedTransitionAt = now }
            if now.timeIntervalSince(speedTransitionAt!) >= (requested ? 3 : 5) {
                speedAllowsDisplay = requested; speedTransitionAt = nil
            }
        }
        for meter in candidates where !meter.isTest && meter.location.distance(from: location) <= radius {
            lastStreetSeen[meter.streetKey] = now
        }
        lastStreetSeen = lastStreetSeen.filter { now.timeIntervalSince($0.value) < 5 }
        guard speedAllowsDisplay else { return [] }
        return candidates.filter {
            !$0.isTest && lastStreetSeen[$0.streetKey] != nil && $0.location.distance(from: location) <= 2 * radius
        }.sorted { $0.id < $1.id }
    }
}
