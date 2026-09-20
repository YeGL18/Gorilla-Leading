import Foundation
import CoreLocation
import Combine

// MARK: - Data Models

/// 單個咪錶泊車位
struct ParkingMeter: Identifiable, Hashable {
    /// ParkingSpaceId（一個咪錶杆有 A/B 兩個位）
    let id: String
    let poleId: String
    let region: String
    let district: String
    let street: String
    let latitude: Double
    let longitude: Double
    let vehicleType: Int
    /// 最長泊車時間（分鐘）
    let lpp: Int
    let operatingPeriodString: String
    /// 每單位收費（$）
    let paymentUnit: Double
    /// 每單位時間（分鐘），例如 15、30
    let timeUnit: Int

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}

/// 單個咪錶嘅即時佔用狀態
struct MeterStatus: Hashable {
    let parkingSpaceId: String
    let isOperating: Bool
    let isVacant: Bool
}

// MARK: - ParkingMeterManager

final class ParkingMeterManager: ObservableObject {
    nonisolated(unsafe) static let shared = ParkingMeterManager()

    // MARK: - Published State

    /// 全部咪錶位（keyed by ParkingSpaceId）
    @Published private(set) var allMeters: [String: ParkingMeter] = [:]
    /// 即時佔用狀態（keyed by ParkingSpaceId）
    @Published private(set) var occupancies: [String: MeterStatus] = [:]
    /// 500m 內嘅咪錶位（地圖標記用）
    @Published private(set) var visibleMeters: [ParkingMeter] = []
    /// 彈窗 flag（ContentView 讀取後重置）
    @Published var isPopupPresented: Bool = false
    /// 彈窗顯示嘅空置咪錶數量
    @Published private(set) var popupVacantCount: Int = 0
    /// 停車 10 秒觸發嘅彈窗 flag
    @Published var isStationaryPopupReady: Bool = false

    // MARK: - Settings

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "meterDetectionEnabled") as? Bool ?? true
    }

    var detectionDistance: Double {
        let val = UserDefaults.standard.integer(forKey: "meterDetectionDistance")
        return val >= 50 ? Double(val) : 100.0
    }

    // MARK: - Private State

    private let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    private var cachedSpacesFileURL: URL? {
        documentsURL?.appendingPathComponent("parking_meters_spaces.csv")
    }

    private static let spacesURL = URL(string: "https://resource.data.one.gov.hk/td/psiparkingspaces/spaceinfo/parkingspaces.csv")!
    private static let occupancyURL = URL(string: "https://resource.data.one.gov.hk/td/psiparkingspaces/occupancystatus/occupancystatus.csv")!

    private var cancellables = Set<AnyCancellable>()
    private var occupancyTimer: Timer?
    private var lastFetchDate: Date?

    /// 漸進式聚合嘅群組半徑（咪錶之間）
    private static let groupMergeRadius: Double = 5.0

    // 冷卻狀態
    private var globalSuppressUntil: Date?
    /// groupKey → 上次彈窗時間（3 分鐘冷卻）
    private var groupPopupCooldowns: [String: Date] = [:]
    /// groupKey → 手動關閉時間（1 分鐘冷卻）
    private var groupDismissals: [String: Date] = [:]

    // 停車 10 秒偵測
    private var stationaryStartTime: Date?
    private var stationaryTimer: Timer?
    private var hasDrivenAwaySinceLastStationaryPopup = true

    /// 當前最近嘅 group key（冷卻用）
    private var currentGroupKey: String?

    // MARK: - Initialization

    private init() {}

    // MARK: - Prepare

    /// 打開地圖時呼叫（後台加載，避免主線程卡頓）
    func prepare() {
        guard !isPrepared else { return }
        isPrepared = true
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            // 後台讀取 + 解析 CSV
            let cached = self.loadCachedSpacesInBackground()
            await MainActor.run {
                self.allMeters = cached
            }
            // 如果緩存過期（>7 日）或冇緩存，下載
            let lastFetch = UserDefaults.standard.object(forKey: "meterSpacesLastFetch") as? Date
            let needsFetch = lastFetch == nil || Date().timeIntervalSince(lastFetch!) > 7 * 24 * 3600
            if needsFetch || cached.isEmpty {
                await self.fetchParkingSpaces()
            }
        }
    }
    private var isPrepared = false

    // MARK: - Data Fetching

    @MainActor
    func fetchParkingSpaces() async {
        do {
            let (data, _) = try await URLSession.shared.data(from: Self.spacesURL)
            guard let text = String(data: data, encoding: .utf8) else { return }

            // 緩存到 Documents
            if let url = cachedSpacesFileURL {
                try? text.data(using: .utf8)?.write(to: url, options: .atomic)
            }
            UserDefaults.standard.set(Date(), forKey: "meterSpacesLastFetch")

            let meters = parseMeters(from: text)
            allMeters = meters
            print("[ParkingMeterManager] 加載 \(meters.count) 個咪錶位")
        } catch {
            print("[ParkingMeterManager] 下載坐標 CSV 失敗: \(error)")
        }
    }

    @MainActor
    func fetchOccupancy() async {
        do {
            let (data, _) = try await URLSession.shared.data(from: Self.occupancyURL)
            guard let text = String(data: data, encoding: .utf8) else { return }
            let statuses = parseOccupancies(from: text)
            occupancies = statuses
            lastFetchDate = Date()
        } catch {
            print("[ParkingMeterManager] 下載佔用狀態失敗: \(error)")
        }
    }

    // MARK: - CSV Parsing

    /// 後台安全：讀取 + 解析 CSV，返回結果（唔改 @Published）
    private func loadCachedSpacesInBackground() -> [String: ParkingMeter] {
        guard let url = cachedSpacesFileURL,
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return [:] }
        return parseMeters(from: text)
    }

    /// 基本 CSV 解析
    private func parseCSVLines(_ text: String) -> [[String]] {
        var cleaned = text
        if cleaned.hasPrefix("\u{FEFF}") { cleaned.removeFirst() }
        cleaned = cleaned.replacingOccurrences(of: "\r\n", with: "\n")
        cleaned = cleaned.replacingOccurrences(of: "\r", with: "\n")

        var rows: [[String]] = []
        let lines = cleaned.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let fields = line.components(separatedBy: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            rows.append(fields)
        }
        return rows
    }

    private func parseMeters(from csvText: String) -> [String: ParkingMeter] {
        let rows = parseCSVLines(csvText)
        guard rows.count > 3 else { return [:] }

        // CSV 格式：第 0 行=日期，第 1 行=空行，第 2 行=header，第 3 行起=data
        // 欄位：0=PoleId, 1=ParkingSpaceId, 2=Region, 5=District, 11=Street,
        //       17=Latitude, 18=Longitude, 19=VehicleType(A/B/C), 20=LPP, 21=OperatingPeriod, 23=PaymentUnit
        var result: [String: ParkingMeter] = [:]
        for i in 3..<rows.count {
            let row = rows[i]
            guard row.count >= 19 else { continue }

            let poleId = row[0].trimmingCharacters(in: .whitespaces)
            let spaceId = row[1].trimmingCharacters(in: .whitespaces)
            let region = row[2].trimmingCharacters(in: .whitespaces)
            let district = row[5].trimmingCharacters(in: .whitespaces)
            let street = row[11].trimmingCharacters(in: .whitespaces)
            let latStr = row[17].trimmingCharacters(in: .whitespaces)
            let lonStr = row[18].trimmingCharacters(in: .whitespaces)
            let vehicleStr = row[19].trimmingCharacters(in: .whitespaces)
            let lppStr = row[20].trimmingCharacters(in: .whitespaces)
            let opPeriod = row.count > 21 ? row[21].trimmingCharacters(in: .whitespaces) : ""
            let timeUnitStr = row.count > 22 ? row[22].trimmingCharacters(in: .whitespaces) : "15"
            let paymentStr = row.count > 23 ? row[23].trimmingCharacters(in: .whitespaces) : "0"

            guard let lat = Double(latStr), let lon = Double(lonStr), lat != 0, lon != 0 else { continue }

            // VehicleType: A=私家車, B=電單車, C=輕型貨車, D=重型貨車
            let vehicleType: Int
            switch vehicleStr.uppercased() {
            case "A": vehicleType = 1
            case "B": vehicleType = 2
            case "C": vehicleType = 3
            case "D": vehicleType = 4
            default: vehicleType = 0
            }
            let lpp = Int(lppStr) ?? 0
            let payment = Double(paymentStr) ?? 0.0
            let timeUnit = Int(timeUnitStr) ?? 15

            let meter = ParkingMeter(
                id: spaceId,
                poleId: poleId,
                region: region,
                district: district,
                street: street,
                latitude: lat,
                longitude: lon,
                vehicleType: vehicleType,
                lpp: lpp,
                operatingPeriodString: opPeriod,
                paymentUnit: payment,
                timeUnit: timeUnit
            )
            result[spaceId] = meter
        }
        return result
    }

    private func parseOccupancies(from csvText: String) -> [String: MeterStatus] {
        let rows = parseCSVLines(csvText)
        guard rows.count > 1 else { return [:] }

        var result: [String: MeterStatus] = [:]
        for i in 1..<rows.count {
            let row = rows[i]
            guard row.count >= 4 else { continue }

            let spaceId = row[0].trimmingCharacters(in: .whitespaces)
            let meterStatus = row[1].trimmingCharacters(in: .whitespaces)
            let occStatus = row[2].trimmingCharacters(in: .whitespaces)

            let status = MeterStatus(
                parkingSpaceId: spaceId,
                isOperating: meterStatus.uppercased() == "O" || meterStatus.uppercased() == "OPERATING",
                isVacant: occStatus.uppercased() == "V" || occStatus.uppercased() == "VACANT"
            )
            result[spaceId] = status
        }
        return result
    }

    // MARK: - Occupancy Polling

    private func startOccupancyPolling() {
        guard occupancyTimer == nil else { return }
        // 立即 fetch 一次
        Task { @MainActor in
            await fetchOccupancy()
        }
        occupancyTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.fetchOccupancy()
            }
        }
        print("[ParkingMeterManager] 佔用狀態 polling 啟動")
    }

    private func stopOccupancyPolling() {
        guard occupancyTimer != nil else { return }
        occupancyTimer?.invalidate()
        occupancyTimer = nil
        print("[ParkingMeterManager] 佔用狀態 polling 停止")
    }

    // MARK: - Core Scanning

    /// 由 ContentView 定時器每 2 秒呼叫一次
    @MainActor
    func scanNearbyMeters(userLocation: CLLocation, speed: Double) {
        guard isEnabled else {
            visibleMeters = []
            stopOccupancyPolling()
            return
        }

        guard speed < 50 else {
            visibleMeters = []
            stopOccupancyPolling()
            return
        }

        guard !allMeters.isEmpty else { return }

        let mapRadius: Double = max(500.0, detectionDistance)
        let popupRadius = detectionDistance

        var withinPopup: [ParkingMeter] = []
        var withinMap: [ParkingMeter] = []

        for (_, meter) in allMeters {
            let dist = meter.location.distance(from: userLocation)
            if dist <= mapRadius {
                withinMap.append(meter)
                if dist <= popupRadius {
                    withinPopup.append(meter)
                }
            }
        }

        visibleMeters = withinMap

        // 啟動佔用 polling（如果有咪錶位喺偵測範圍內）
        if !withinPopup.isEmpty {
            if occupancies.isEmpty || lastFetchDate == nil || Date().timeIntervalSince(lastFetchDate!) > 60 {
                startOccupancyPolling()
            }
        }

        // 彈窗評估
        if !withinPopup.isEmpty {
            evaluatePopup(nearbyMeters: withinPopup)

            // 停車偵測
            updateStationaryDetection(speed: speed, nearbyMeters: withinPopup)
        }
    }

    // MARK: - Grouping (Progressive Aggregation)

    /// 漸進式聚合：用 5m 半徑將附近嘅咪錶位歸為同一群組
    /// 返回各群組（陣列），每個群組嘅 key = 陣列中距離最近嗰個嘅 id
    private func groupMeters(_ meters: [ParkingMeter]) -> [[ParkingMeter]] {
        guard !meters.isEmpty else { return [] }

        var used = Set<String>()
        var groups: [[ParkingMeter]] = []

        for meter in meters {
            if used.contains(meter.id) { continue }
            // BFS：以呢個 meter 為起點，輻射式擴展
            var group: [ParkingMeter] = []
            var queue: [ParkingMeter] = [meter]
            used.insert(meter.id)

            while !queue.isEmpty {
                let current = queue.removeFirst()
                group.append(current)
                // 找 5m 內嘅其他未使用嘅 meter
                for other in meters {
                    if used.contains(other.id) { continue }
                    let dist = current.location.distance(from: other.location)
                    if dist <= Self.groupMergeRadius {
                        used.insert(other.id)
                        queue.append(other)
                    }
                }
            }
            groups.append(group)
        }
        return groups
    }

    /// 計算群組嘅 key（距離最近嘅 meter 嘅 id）
    private func groupKey(_ group: [ParkingMeter], userLocation: CLLocation) -> String {
        var best: ParkingMeter?
        var bestDist: Double = .greatestFiniteMagnitude
        for m in group {
            let d = m.location.distance(from: userLocation)
            if d < bestDist {
                bestDist = d
                best = m
            }
        }
        return best?.id ?? group[0].id
    }

    // MARK: - Popup Evaluation

    private func evaluatePopup(nearbyMeters: [ParkingMeter]) {
        let now = Date()

        // 全局冷卻
        if let suppress = globalSuppressUntil, now < suppress { return }

        guard let userLocation = nearbyMeters.first.map({ $0.location }) else { return }

        let groups = groupMeters(nearbyMeters)
        guard !groups.isEmpty else { return }

        // 搵最近嘅 group
        var bestGroup: [ParkingMeter]?
        var bestDist: Double = .greatestFiniteMagnitude
        for group in groups {
            let key = groupKey(group, userLocation: CLLocation(
                latitude: userLocation.coordinate.latitude,
                longitude: userLocation.coordinate.longitude
            ))
            // 計算 group 中心距離
            if let nearest = group.min(by: { $0.location.distance(from: userLocation) < $1.location.distance(from: userLocation) }) {
                let d = nearest.location.distance(from: userLocation)
                if d < bestDist {
                    bestDist = d
                    bestGroup = group
                }
            }
        }

        guard let group = bestGroup else { return }
        let key = groupKey(group, userLocation: CLLocation(
            latitude: userLocation.coordinate.latitude,
            longitude: userLocation.coordinate.longitude
        ))

        // 群組彈窗冷卻（3 分鐘）
        if let lastPopup = groupPopupCooldowns[key], now.timeIntervalSince(lastPopup) < 3 * 60 { return }

        // 手動關閉冷卻（1 分鐘）
        if let lastDismiss = groupDismissals[key], now.timeIntervalSince(lastDismiss) < 60 { return }

        // 計算空置數量
        var vacantCount = 0
        var totalCount = 0
        for m in group {
            totalCount += 1
            if let status = occupancies[m.id], status.isVacant {
                vacantCount += 1
            } else if occupancies[m.id] == nil {
                // 仲未有佔用數據，唔算空置
            }
        }

        if vacantCount > 0 {
            popupVacantCount = vacantCount
            groupPopupCooldowns[key] = now
            currentGroupKey = key
            isPopupPresented = true
        }
    }

    // MARK: - Stationary Detection (Speed=0 for 10 seconds)

    private func updateStationaryDetection(speed: Double, nearbyMeters: [ParkingMeter]) {
        if speed < 0.5 {
            if stationaryStartTime == nil {
                stationaryStartTime = Date()
                stationaryTimer?.invalidate()
                stationaryTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
                    guard let self else { return }
                    Task { @MainActor in
                        self.onStationary10Seconds(nearbyMeters: nearbyMeters)
                    }
                }
            }
        } else {
            stationaryStartTime = nil
            stationaryTimer?.invalidate()
            stationaryTimer = nil
            if speed >= 5 {
                hasDrivenAwaySinceLastStationaryPopup = true
            }
        }
    }

    @MainActor
    private func onStationary10Seconds(nearbyMeters: [ParkingMeter]) {
        guard hasDrivenAwaySinceLastStationaryPopup else { return }
        guard !isPopupPresented else { return }

        let now = Date()
        if let suppress = globalSuppressUntil, now < suppress { return }

        // 檢查附近有冇咪錶位
        guard !nearbyMeters.isEmpty else { return }

        guard let userLocation = nearbyMeters.first.map({ $0.location }) else { return }

        let groups = groupMeters(nearbyMeters)
        guard let group = groups.first else { return }
        let key = groupKey(group, userLocation: CLLocation(
            latitude: userLocation.coordinate.latitude,
            longitude: userLocation.coordinate.longitude
        ))

        // 群組冷卻
        if let lastPopup = groupPopupCooldowns[key], now.timeIntervalSince(lastPopup) < 3 * 60 { return }
        if let lastDismiss = groupDismissals[key], now.timeIntervalSince(lastDismiss) < 60 { return }

        // 計算有冇空位
        var vacantCount = 0
        for m in group {
            if let status = occupancies[m.id], status.isVacant {
                vacantCount += 1
            }
        }

        // 條件 B：全部佔用但停車 10 秒，照彈
        popupVacantCount = vacantCount
        groupPopupCooldowns[key] = now
        currentGroupKey = key
        hasDrivenAwaySinceLastStationaryPopup = false
        isStationaryPopupReady = true
    }

    // MARK: - Action Callbacks

    /// 用戶撳「前往繳費」
    func onUserTappedPay() {
        globalSuppressUntil = Date().addingTimeInterval(30 * 60)
        isPopupPresented = false
        isStationaryPopupReady = false
    }

    /// 用戶手動關閉彈窗（1 分鐘冷卻）
    func onUserDismissedPopup() {
        if let key = currentGroupKey {
            groupDismissals[key] = Date()
        }
        isPopupPresented = false
        isStationaryPopupReady = false
    }

    // MARK: - Utilities

    /// 車輛類型顯示文字
    static func vehicleTypeDisplay(_ type: Int) -> String {
        switch type {
        case 1: return "A 類車輛（私家車）"
        case 2: return "電單車"
        case 3: return "輕型貨車"
        case 4: return "重型貨車"
        default: return "任何車輛"
        }
    }

    /// 最長泊車時間顯示文字
    static func lppDisplay(_ minutes: Int) -> String {
        if minutes >= 60 {
            let h = minutes / 60
            let m = minutes % 60
            return m > 0 ? "\(h) 小時 \(m) 分鐘" : "\(h) 小時"
        }
        return "\(minutes) 分鐘"
    }

    /// 收費顯示文字（含時間單位）
    static func paymentDisplay(_ unit: Double, timeUnit: Int = 15) -> String {
        let fee = unit.truncatingRemainder(dividingBy: 1) == 0
            ? "$\(Int(unit))"
            : "$\(String(format: "%.1f", unit))"
        return "\(fee) / \(timeUnit)分鐘"
    }

    /// 運作時段代碼解碼
    /// 去掉數字前綴（多杆共用時段），取最後一個字母查表
    static func operatingPeriodDisplay(_ code: String) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }

        // 去掉前導數字（3D→D, 4Q→Q, 7J→J, 120→120）
        let letterPart = trimmed.filter { !$0.isNumber }
        let numberPart = trimmed.filter { $0.isNumber }

        let base: String
        switch letterPart.uppercased() {
        case "A": base = "週一至六 08:00–00:00"
        case "B": base = "週一至六 08:00–20:00"
        case "D": base = "週一至六 08:00–00:00；週日 10:00–22:00"
        case "F": base = "每天 08:00–21:00"
        case "H": base = "每天 08:00–20:00"
        case "J": base = "每天 08:00–00:00"
        case "N": base = "每天 19:00–00:00"
        case "P": base = "週一至六 08:00–20:00（週日禁止泊車）"
        case "Q": base = "週一至六 08:00–20:00；週日 10:00–22:00"
        case "S": base = "週一至五 17:00–00:00；六 08:00–00:00；日 10:00–22:00"
        case "T": base = "週一至六 08:00–20:00；週日 10:00–22:00"
        case "Z": base = "24 小時"
        case "G": base = "每天 08:00–20:00"
        default:
            // 純數字（如 120）→ 分鐘
            if let mins = Int(trimmed), mins > 0 {
                return "\(mins) 分鐘"
            }
            return trimmed
        }

        // 多杆共用標記（3D、4Q 等）
        if !numberPart.isEmpty {
            return "\(numberPart)號杆：\(base)"
        }
        return base
    }
}