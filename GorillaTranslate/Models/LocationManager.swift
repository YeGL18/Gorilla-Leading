import Foundation
import UIKit
import SwiftUI
import CoreLocation
import Combine
import CoreMotion
import AVFoundation

// MARK: - Kalman Filter for speed smoothing
class KalmanFilter {
    // State: [position, velocity]
    private var x: Double = 0      // position estimate
    private var v: Double = 0      // velocity estimate
    private var P: Double = 1      // position error covariance
    private var Pv: Double = 1     // velocity error covariance
    let processNoise: Double
    let measurementNoise: Double
    private var initialized = false
    private var lastUpdateTime: Date?
    private var firstMeasurement: Double?
    private var firstMeasurementTime: Date?

    init(processNoise: Double = 0.01, measurementNoise: Double = 0.5) {
        self.processNoise = processNoise
        self.measurementNoise = measurementNoise
    }

    /// Update with a new GPS measurement (called every ~1 second)
    func update(measurement: Double) -> Double {
        let now = Date()

        if !initialized {
            // First measurement: just store it
            x = measurement
            v = 0
            initialized = true
            lastUpdateTime = now
            firstMeasurement = measurement
            firstMeasurementTime = now
            return x
        }

        // Second measurement: calculate initial velocity
        if let first = firstMeasurement, let firstTime = firstMeasurementTime {
            let dt = now.timeIntervalSince(firstTime)
            if dt > 0 {
                v = (measurement - first) / dt
            }
            firstMeasurement = nil
            firstMeasurementTime = nil
        }

        let dt = lastUpdateTime?.timeIntervalSinceNow.magnitude ?? 1.0
        lastUpdateTime = now

        // Predict step: use velocity to predict next position
        let predictedX = x + v * dt
        let predictedP = P + Pv + processNoise

        // Update step
        let kalmanGain = predictedP / (predictedP + measurementNoise)
        let innovation = measurement - predictedX
        x = predictedX + kalmanGain * innovation
        v = v + kalmanGain * innovation / max(dt, 0.1)  // update velocity estimate
        P = (1 - kalmanGain) * predictedP

        return x
    }

    /// Predict position at a future time (for smooth interpolation between GPS updates)
    func predict(at time: Date) -> Double {
        guard let lastUpdate = lastUpdateTime else { return x }
        let dt = time.timeIntervalSince(lastUpdate)
        return x + v * dt
    }

    /// Current predicted position (now)
    var predictedPosition: Double {
        return x
    }

    /// Current velocity estimate
    var velocity: Double {
        return v
    }

    func reset() {
        x = 0
        v = 0
        P = 1
        Pv = 1
        initialized = false
        lastUpdateTime = nil
        firstMeasurement = nil
        firstMeasurementTime = nil
    }
}

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private(set) var manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var recentQualities: [GPSQuality] = []
    private let requiredSamples = 5
    private var lastGeocodeLocation: CLLocation?
    private var lastGeocodeTime: Date?
    private var locationServicesStarted = false

    // MARK: - CMMotionActivity 交通模式偵測
    private let motionActivityManager = CMMotionActivityManager()
    @Published var currentMotionActivity: CMMotionActivity?
    /// 最後一次偵測到各種交通模式的時間
    @Published var lastAutomotiveTime: Date?
    @Published var lastWalkingTime: Date?
    @Published var lastRunningTime: Date?
    @Published var lastCyclingTime: Date?

    // MARK: - 車載藍牙斷聯偵測（泊車位置修正）
    /// 最近一次速度超過 15 km/h 嘅時間（判斷「啱啱揸緊車」）
    private var lastHighSpeedTime: Date?
    /// 最近 60 秒 GPS fixes（斷聯嗰刻取中位數坐標用，單點 fix 會跳）
    private var recentFixBuffer: [(latitude: Double, longitude: Double, date: Date)] = []
    /// 斷聯候選「落車點」（30 分鐘內）
    @Published private(set) var carExitEvents: [CarExitEvent] = []
    private let carExitEventsKey = "car_exit_events_v1"
    /// 見過嘅車載藍牙音訊裝置（名 + UID），填滿「我嘅車藍牙」選擇列表
    @Published private(set) var seenBluetoothDevices: [CarBluetoothDevice] = []
    /// 用戶認住嘅「我嘅車藍牙」——斷線判定認住呢部車，唔再靠估
    @Published private(set) var myCarBluetooth: CarBluetoothDevice?
    private let seenBluetoothDevicesKey = "seen_car_bluetooth_devices_v1"
    private let myCarBluetoothKey = "my_car_bluetooth_device_v1"

    enum GPSQuality {
        case good
        case poor
        case bad
        case unknown
    }

    struct VisitRecord: Identifiable, Codable {
        let id: UUID
        let address: String
        let latitude: Double
        let longitude: Double
        let arrivalDate: Date
        var departureDate: Date?
        let transportType: String
        /// CMMotionActivity 偵測：到訪前是否有 automotive 活動（舊資料預設 true）
        let isAutomotive: Bool

        // 向後相容：舊資料沒有 isAutomotive 欄位時預設 true
        enum CodingKeys: String, CodingKey {
            case id, address, latitude, longitude, arrivalDate, departureDate, transportType, isAutomotive
        }

        init(id: UUID, address: String, latitude: Double, longitude: Double,
             arrivalDate: Date, departureDate: Date? = nil, transportType: String,
             isAutomotive: Bool = true) {
            self.id = id
            self.address = address
            self.latitude = latitude
            self.longitude = longitude
            self.arrivalDate = arrivalDate
            self.departureDate = departureDate
            self.transportType = transportType
            self.isAutomotive = isAutomotive
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            address = try c.decode(String.self, forKey: .address)
            latitude = try c.decode(Double.self, forKey: .latitude)
            longitude = try c.decode(Double.self, forKey: .longitude)
            arrivalDate = try c.decode(Date.self, forKey: .arrivalDate)
            departureDate = try c.decodeIfPresent(Date.self, forKey: .departureDate)
            transportType = try c.decode(String.self, forKey: .transportType)
            isAutomotive = try c.decodeIfPresent(Bool.self, forKey: .isAutomotive) ?? true
        }

        var duration: String {
            // 修復「舊記錄顯示至今」：有離場時間就用離場時間計固定時長；
            // 淨係真係仲停留緊（departureDate == nil）先用即時累加
            if let d = departureDate, d >= arrivalDate {
                return Self.formatSpan(d.timeIntervalSince(arrivalDate))
            }
            return Self.formatSpan(Date().timeIntervalSince(arrivalDate))
        }

        static func matchesArrival(timeDifference: TimeInterval, distance: CLLocationDistance) -> Bool {
            // Near-identical arrival timestamps identify the same visit despite GPS drift.
            // Wider time tolerance is only safe when coordinates remain very close.
            (timeDifference <= 30 && distance < 500) || (timeDifference < 300 && distance < 150)
        }

        /// 時長格式（同參考 UI 一致）：< 1min / 29min / 1hr 36min
        static func formatSpan(_ interval: TimeInterval) -> String {
            let minutes = Int(max(0, interval) / 60)
            if minutes < 1 { return "< 1min" }
            if minutes < 60 { return "\(minutes)min" }
            let h = minutes / 60
            let m = minutes % 60
            return m == 0 ? "\(h)hr" : "\(h)hr \(m)min"
        }
    }

    @Published var speed: Double = 0
    @Published var smoothedSpeed: Double = 0

    /// 逐格滾動插值用：卡爾曼速度外推預測值（GPS 更新之間會持續平滑推進，
    /// 數字逐格滾動）。關閉卡爾曼時直接回傳平滑時速。
    func predictedSpeed(at date: Date = Date()) -> Double {
        guard kalmanSmoothingEnabled else { return smoothedSpeed }
        return min(299, max(0, speedKalmanFilter.predict(at: date)))
    }

    func resetSpeedFilter() {
        speedKalmanFilter.reset()
        smoothedSpeed = 0
        speed = 0
    }

    /// GPS 失聯判定（時速顯示凍結用）：除咗質素差，仲要計「幾耐冇新 fix」——
    /// 隧道入面一個定位回調都冇，gpsQuality 會停喺最後狀態（.good），
    /// 所以要靠 lastLocation 時間戳年齡判定失聯。超過 2.5 秒冇新 fix = 失聯。
    /// 注意 .unknown 唔算失聯：佢只係「未有質素判定」（冷啟動／權限回調
    /// 重新廣播），只要仲有新 fix 就唔應該凍結時速顯示。
    var isGPSLost: Bool {
        if gpsQuality == .bad { return true }
        guard let loc = lastLocation else { return true }
        return Date().timeIntervalSince(loc.timestamp) > 2.5
    }
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var gpsQuality: GPSQuality = .unknown
    @Published var currentAddress: String = ""
    @Published var currentPOIName: String = ""  // POI／大廈名（用於輪播顯示）
    /// 街道名（街道＋門牌，冇街道就退地區名）——輪播另一邊。
    /// 同 `currentAddress` 分開：地址字串優先級係 POI名 > 地區名 > 街道名，
    /// 直接拎嚟輪播會成日同 POI 名相同而輪唔到。
    @Published var currentStreetName: String = ""
    @Published var currentLocality: String = ""  // 當前城市/地區
    @Published var visits: [VisitRecord] = []
    @Published var lastLocation: CLLocation?
    @Published var heading: Double = 0

    /// Map camera seed: a weak or briefly stale fix is still better than an unrelated city.
    var mapReferenceLocation: CLLocation? {
        if let location = lastLocation,
           location.horizontalAccuracy >= 0,
           CLLocationCoordinate2DIsValid(location.coordinate),
           location.coordinate.latitude != 0 || location.coordinate.longitude != 0 {
            return location
        }

        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "lastKnownLatitude") != nil,
              defaults.object(forKey: "lastKnownLongitude") != nil else { return nil }
        let coordinate = CLLocationCoordinate2D(
            latitude: defaults.double(forKey: "lastKnownLatitude"),
            longitude: defaults.double(forKey: "lastKnownLongitude")
        )
        guard CLLocationCoordinate2DIsValid(coordinate),
              coordinate.latitude != 0 || coordinate.longitude != 0 else { return nil }
        return CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    /// Convert current UI interface orientation to CLDeviceOrientation
    /// so CLLocationManager reports heading relative to the screen top.
    static func currentDeviceOrientation() -> CLDeviceOrientation {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first else { return .portrait }
        switch scene.interfaceOrientation {
        case .landscapeLeft:  return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        case .portraitUpsideDown: return .portraitUpsideDown
        default: return .portrait
        }
    }
    @Published var hasLoadedVisits: Bool = false

    private let visitsKey = "visit_records"

    // Kalman filter for speed smoothing
    private let speedKalmanFilter = KalmanFilter(processNoise: 0.5, measurementNoise: 0.3)
    private var kalmanSmoothingEnabled: Bool {
        UserDefaults.standard.bool(forKey: "kalmanSmoothingEnabled")
    }

    // TripPredictor dedupe：一條 visit 只會 learning departure 一次、predict arrival 一次
    private var learnedDepartureVisits: Set<UUID> = []
    private var predictedArrivalVisits: Set<UUID> = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
        loadVisits()
        loadMotionSegments()
        loadCarExitEvents()
        loadCarBluetoothState()
        startCarAudioRouteMonitor()
    }

    func startLocationServicesIfNeeded() {
        guard !locationServicesStarted else { return }
        locationServicesStarted = true
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        manager.startMonitoringVisits()
        if CLLocationManager.headingAvailable() {
            manager.headingOrientation = Self.currentDeviceOrientation()
            manager.startUpdatingHeading()
        }
        // 啟動 CMMotionActivity 偵測交通模式
        startMotionActivityMonitoring()
    }

    // MARK: - CMMotionActivity 監測

    private func startMotionActivityMonitoring() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        motionActivityManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let activity else { return }
            self?.currentMotionActivity = activity
            ParkingFloorStore.shared.barometer.updateMotion(activity)
            let now = Date()
            if activity.automotive {
                self?.lastAutomotiveTime = now
            }
            if activity.walking {
                self?.lastWalkingTime = now
            }
            if activity.running {
                self?.lastRunningTime = now
            }
            if activity.cycling {
                self?.lastCyclingTime = now
            }
            // 持續記錄交通模式分段（行程分段顯示＋開車到達判定用）
            self?.recordMotionActivity(activity)
        }
        // 回填 App 死咗嗰陣嘅歷史分段
        backfillMotionSegments()
    }

    // MARK: - 交通模式分段（CMMotionActivity 持續記錄）

    private let motionSegmentsKey = "motion_segments"

    /// 由 CMMotionActivity 累積出嚟嘅交通模式分段。
    /// 舊記錄冇分段數據 → 行程行顯示單行（同參考圖一致）；新行程先有 🚗33min ▶ 🚶1min ▶… 分段。
    @Published private(set) var motionSegments: [MotionSegment] = []

    private static func modeString(_ activity: CMMotionActivity) -> String {
        if activity.automotive { return "Driving" }
        if activity.walking { return "Walking" }
        if activity.running { return "Running" }
        if activity.cycling { return "Cycling" }
        if activity.stationary { return "Stationary" }
        return "Unknown"
    }

    private func recordMotionActivity(_ activity: CMMotionActivity) {
        let mode = Self.modeString(activity)
        if var last = motionSegments.last, last.end == nil {
            if last.mode == mode { return } // 同一段延續，唔使理
            if activity.startDate > last.start {
                last.end = activity.startDate
                motionSegments[motionSegments.count - 1] = last
            } else {
                return // 亂序更新，唔好打亂時間軸
            }
        }
        appendSegment(mode: mode, start: activity.startDate, end: nil)
        trimAndSaveMotionSegments()
    }

    private func appendSegment(mode: String, start: Date, end: Date?) {
        guard let last = motionSegments.last else {
            motionSegments.append(MotionSegment(id: UUID(), mode: mode, start: start, end: end))
            return
        }
        if last.mode == mode, last.end == nil || (last.end ?? .distantPast) >= start {
            var l = last
            l.end = (l.end == nil || end == nil) ? nil : Self.laterDate(l.end, end)
            motionSegments[motionSegments.count - 1] = l
            return
        }
        if let le = last.end, start < le {
            // 同前段重疊：以前段為準，剪走重疊部分
            if let e = end, e <= le { return }
            motionSegments.append(MotionSegment(id: UUID(), mode: mode, start: le, end: end))
            return
        }
        motionSegments.append(MotionSegment(id: UUID(), mode: mode, start: start, end: end))
    }

    private static func laterDate(_ a: Date?, _ b: Date?) -> Date? {
        switch (a, b) {
        case (nil, nil): return nil
        case (let x?, nil): return x
        case (nil, let y?): return y
        case (let x?, let y?): return max(x, y)
        }
    }

    private func trimAndSaveMotionSegments() {
        let cutoff = Date().addingTimeInterval(-45 * 24 * 3600)
        if let firstKeep = motionSegments.firstIndex(where: { $0.resolvedEnd >= cutoff }), firstKeep > 0 {
            motionSegments.removeFirst(firstKeep)
        }
        if motionSegments.count > 3000 {
            motionSegments.removeFirst(motionSegments.count - 3000)
        }
        if let data = try? JSONEncoder().encode(motionSegments) {
            UserDefaults.standard.set(data, forKey: motionSegmentsKey)
        }
    }

    private func loadMotionSegments() {
        guard let data = UserDefaults.standard.data(forKey: motionSegmentsKey),
              let decoded = try? JSONDecoder().decode([MotionSegment].self, from: data) else { return }
        motionSegments = decoded
    }

    /// 重啟後回填 CMMotionActivity 歷史（App 死咗嗰陣嘅行程都可以分段＋判定）。
    /// queryActivityStarting 回傳嘅係「轉換點」平面陣列：第 n 段由 startDate 開始，
    /// 到下一段 startDate 為止（CMMotionActivity 冇 endDate）
    private func backfillMotionSegments() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        let to = Date()
        // CoreMotion 只保留最近 7 日數據，窗口控制喺 2.5 日內
        let earliest = to.addingTimeInterval(-2.5 * 24 * 3600)
        let lastRecorded = motionSegments.last
        let resumeAt = lastRecorded?.end ?? lastRecorded?.start ?? earliest
        let from = max(resumeAt.addingTimeInterval(-300), earliest)
        guard to.timeIntervalSince(from) > 60 else { return }
        motionActivityManager.queryActivityStarting(from: from, to: to, to: .main) { [weak self] activities, error in
            guard let self, let activities, error == nil else { return }
            let ordered = activities.sorted { $0.startDate < $1.startDate }
            guard !ordered.isEmpty else { return }
            // Live updates received while the history query was in flight must survive.
            let liveTail = self.motionSegments.compactMap { segment -> MotionSegment? in
                guard segment.end == nil || segment.resolvedEnd > to else { return nil }
                var tail = segment
                tail.start = max(tail.start, to)
                return tail
            }
            // Rebuild the queried tail: an open segment saved before termination must not
            // silently extend through every later trip or overlap the recovered history.
            self.motionSegments = self.motionSegments.compactMap { segment in
                guard segment.start < from else { return nil }
                guard segment.resolvedEnd > from else { return segment }
                var trimmed = segment
                trimmed.end = from
                return trimmed
            }
            for (index, act) in ordered.enumerated() {
                let end = min(index + 1 < ordered.count ? ordered[index + 1].startDate : to, to)
                let start = max(act.startDate, from)
                guard end > start else { continue }
                self.appendSegment(mode: Self.modeString(act), start: start, end: end)
            }
            for segment in liveTail {
                self.appendSegment(mode: segment.mode, start: segment.start, end: segment.end)
            }
            if liveTail.isEmpty, let activity = self.currentMotionActivity {
                self.appendSegment(mode: Self.modeString(activity), start: to, end: nil)
            }
            self.trimAndSaveMotionSegments()
        }
    }

    /// 某時間範圍內嘅「移動」分段（揸車/步行/跑步/騎行）：夾入窗口、濾雜訊、合併同模式短停頓
    func tripSegments(from: Date, to: Date) -> [MotionSegment] {
        guard to > from else { return [] }
        let clipped = motionSegments
            .compactMap { $0.clipped(from: from, to: to) }
            .filter { $0.isMovement && $0.resolvedEnd.timeIntervalSince($0.start) >= 10 }
        var merged: [MotionSegment] = []
        for seg in clipped {
            if var last = merged.last,
               seg.mode == last.mode,
               seg.start.timeIntervalSince(last.resolvedEnd) < 120 {
                last.end = seg.resolvedEnd
                merged[merged.count - 1] = last
            } else {
                merged.append(seg)
            }
        }
        return merged
    }

    /// A complete, non-overlapping trip timeline. Conflicting historical samples are
    /// unknown rather than three simultaneous (and impossible) transport modes.
    func tripTimeline(from: Date, to: Date) -> [MotionSegment] {
        guard to > from else { return [] }
        let samples = motionSegments.compactMap { $0.clipped(from: from, to: to) }
        guard !samples.isEmpty else { return [] }
        let boundaries = Array(Set([from, to] + samples.flatMap { [$0.start, $0.resolvedEnd] })).sorted()
        var result: [MotionSegment] = []
        for (start, end) in zip(boundaries, boundaries.dropFirst()) where end > start {
            let modes = Set(samples.filter { $0.start < end && $0.resolvedEnd > start }.map(\.mode))
            let mode = modes.count == 1 ? modes.first! : "Unknown"
            if let last = result.last, last.mode == mode, last.resolvedEnd == start {
                result[result.count - 1].end = end
            } else {
                result.append(MotionSegment(id: UUID(), mode: mode, start: start, end: end))
            }
        }
        return result
    }

    /// 「全程揸車先算」：成段行程冇步行/跑步/騎行段（≥20 秒）先算開車到達（泊車記憶）；
    /// 有任何非揸車段 → 非開車到達（逗留記憶）。冇分段數據就退回舊嘅模式判斷。
    func classifyTrip(tripStart: Date?, arrival: Date) -> (isAutomotive: Bool, transportType: String) {
        let earliest = arrival.addingTimeInterval(-8 * 3600)
        let start = max(tripStart ?? arrival.addingTimeInterval(-2 * 3600), earliest)
        let segs = tripSegments(from: start, to: arrival)
        guard !segs.isEmpty else {
            // 冇分段數據（例如更新前嘅行程）：退回舊判斷
            let autom = lastTransportMode(around: arrival) == .driving
            return (autom, autom ? "Driving" : transportTypeFromSpeed())
        }
        let nonDriving = segs.filter {
            $0.mode != "Driving" && $0.resolvedEnd.timeIntervalSince($0.start) >= 20
        }
        let driving = segs.filter {
            $0.mode == "Driving" && $0.resolvedEnd.timeIntervalSince($0.start) >= 20
        }
        let lastMode = segs.last?.mode ?? "Unknown"
        if !nonDriving.isEmpty { return (false, lastMode) }
        if !driving.isEmpty { return (true, lastMode) }
        return (false, lastMode)
    }

    private func transportTypeFromSpeed() -> String {
        let kmh = max(0, speed)
        if kmh < 2 { return "Walking" }
        if kmh < 80 { return "Driving" }
        return "Transit"
    }

    /// 判斷某個時間點前後是否在開車（用於 CLVisit 到達時判斷交通模式）
    func wasAutomotive(around date: Date, within interval: TimeInterval = 300) -> Bool {
        // 用「最後一個模式」判斷，而非「有沒有開車記錄」
        // 例如：開車 20 分鐘 → 步行 10 分鐘 → 到達 → 應該是步行到達
        let mode = lastTransportMode(around: date, within: interval)
        return mode == .driving
    }

    /// 判斷某個時間點前後的交通模式（回傳最接近到達時間的模式）
    /// 關鍵邏輯：看最後一個交通模式，而非優先級
    func lastTransportMode(around date: Date, within interval: TimeInterval = 300) -> GorillaActivityState {
        // 收集所有在時間範圍內的模式，按時間排序，取最近的
        var candidates: [(time: Date, mode: GorillaActivityState)] = []

        if let t = lastAutomotiveTime, abs(t.timeIntervalSince(date)) < interval {
            candidates.append((t, .driving))
        }
        if let t = lastCyclingTime, abs(t.timeIntervalSince(date)) < interval {
            candidates.append((t, .nonAutomotiveParking))  // 騎車到達 → 逗留
        }
        if let t = lastRunningTime, abs(t.timeIntervalSince(date)) < interval {
            candidates.append((t, .nonAutomotiveParking))  // 跑步到達 → 逗留
        }
        if let t = lastWalkingTime, abs(t.timeIntervalSince(date)) < interval {
            candidates.append((t, .nonAutomotiveParking))  // 步行到達 → 逗留
        }

        // 取最接近到達時間的模式
        if let closest = candidates.min(by: { abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date)) }) {
            return closest.mode
        }

        return .nonAutomotiveParking  // 沒有記錄 → 預設逗留
    }

    private func quality(from accuracy: CLLocationAccuracy) -> GPSQuality {
        if accuracy < 0 { return .unknown }
        if accuracy <= 10 { return .good }
        if accuracy <= 30 { return .poor }
        return .bad
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        DispatchQueue.main.async {
            self.lastLocation = location
            // 緩存當前坐標（樓層慣例自動判定用；以前呢兩個 key 冇人寫，成日判死香港）
            if location.horizontalAccuracy >= 0,
               CLLocationCoordinate2DIsValid(location.coordinate),
               location.coordinate.latitude != 0 || location.coordinate.longitude != 0 {
                UserDefaults.standard.set(location.coordinate.latitude, forKey: "lastKnownLatitude")
                UserDefaults.standard.set(location.coordinate.longitude, forKey: "lastKnownLongitude")
            }
            if location.speed >= 0 {
                let rawSpeed = location.speed * 3.6
                self.speed = rawSpeed
                // Kalman smoothing
                if self.kalmanSmoothingEnabled {
                    let smoothed = self.speedKalmanFilter.update(measurement: rawSpeed)
                    self.smoothedSpeed = smoothed
                } else {
                    self.speedKalmanFilter.reset()
                    self.smoothedSpeed = rawSpeed
                }
                // 同步車速給氣壓計，用於標記樣本
            }
            ParkingFloorStore.shared.barometer.updateDriving(
                speed: location.speed >= 0 ? location.speed * 3.6 : -1,
                timestamp: location.timestamp,
                coordinate: location.coordinate
            )
            // 藍牙斷聯事件維護：記錄 fix、追蹤「斷聯後有冇再開車」
            let now = Date()
            self.recentFixBuffer.append((location.coordinate.latitude, location.coordinate.longitude, now))
            self.recentFixBuffer.removeAll { now.timeIntervalSince($0.date) > 60 }
            if self.smoothedSpeed > 15 { self.lastHighSpeedTime = now }
            self.updateCarExitEvents(now: now)
            let newQuality = self.quality(from: location.horizontalAccuracy)
            self.recentQualities.append(newQuality)
            if self.recentQualities.count > self.requiredSamples {
                self.recentQualities.removeFirst()
            }
            if self.recentQualities.count == self.requiredSamples,
               self.recentQualities.allSatisfy({ $0 == newQuality }) {
                self.gpsQuality = newQuality
            }

            // geocode 節流：移動超過 50 米先查一次；高速（≥60 km/h）再加
            // 「至少隔 5 秒」——60+ 每 5 秒已經行咗成百米，密過呢個冇意義，
            // 只會白刷 geocoder。未到 5 秒就唔更新 lastGeocodeLocation，
            // 下個 fix 行遠咗自然會補查。
            let speedNow = location.speed >= 0 ? location.speed * 3.6 : self.speed
            let movedFar = self.lastGeocodeLocation == nil ||
                location.distance(from: self.lastGeocodeLocation!) > 50
            if movedFar {
                let throttled = speedNow >= 60 &&
                    self.lastGeocodeTime != nil &&
                    Date().timeIntervalSince(self.lastGeocodeTime!) < 5
                if !throttled {
                    self.reverseGeocode(location: location)
                }
            }
        }
    }

    // MARK: - 車載藍牙斷聯偵測（音訊路由監聽）

    /// 監聽車載音訊路由斷聯——公開 API 入面唯一可靠嘅「車藍牙斷線」信號。
    /// 唔用 CoreBluetooth：iOS 唔畀讀任意藍牙連接狀態（仲要藍牙權限）；
    /// 音訊路由變化免權限免掃描，熄火斷線嗰下照樣捉到。
    private func startCarAudioRouteMonitor() {
        // 開嗰刻已經連住車藍牙都照記低（一開設定頁已經有嘢睇）
        recordBluetoothDevices(in: AVAudioSession.sharedInstance().currentRoute)
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self else { return }
            guard let previous = note.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription else { return }
            // 任何路由變化都順手記低見過嘅藍牙裝置（新舊兩邊都睇，填滿「我嘅車藍牙」列表）
            self.recordBluetoothDevices(in: previous)
            self.recordBluetoothDevices(in: AVAudioSession.sharedInstance().currentRoute)
            let hadCarAudio = previous.outputs.contains { Self.isCarAudioPort($0) }
            let stillConnected = AVAudioSession.sharedInstance().currentRoute.outputs.contains { Self.isCarAudioPort($0) }
            guard hadCarAudio, !stillConnected else { return }
            self.handleCarAudioDisconnect(previous: previous)
        }
    }

    private static func isCarAudioPort(_ port: AVAudioSessionPortDescription) -> Bool {
        switch port.portType {
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .carAudio:
            return true
        default:
            return false
        }
    }

    /// 只有藍牙類型嘅輸出先係「藍牙裝置」（.carAudio 可能係有線 CarPlay，冇藍牙身份）
    private static func isBluetoothAudioPort(_ port: AVAudioSessionPortDescription) -> Bool {
        switch port.portType {
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
            return true
        default:
            return false
        }
    }

    // MARK: - 「我嘅車藍牙」認車（裝置名 + UID）

    /// 記低路由入面見過嘅車載藍牙裝置，填滿「我嘅車藍牙」選擇列表
    private func recordBluetoothDevices(in route: AVAudioSessionRouteDescription) {
        for port in route.outputs where Self.isBluetoothAudioPort(port) {
            recordBluetoothDevice(name: port.portName, uid: port.uid)
        }
    }

    private func recordBluetoothDevice(name: String, uid: String) {
        let key = uid.isEmpty ? name : uid
        let now = Date()
        if let idx = seenBluetoothDevices.firstIndex(where: { $0.id == key }) {
            seenBluetoothDevices[idx].name = name
            seenBluetoothDevices[idx].lastSeen = now
        } else {
            seenBluetoothDevices.append(CarBluetoothDevice(uid: uid, name: name, lastSeen: now))
            if seenBluetoothDevices.count > 20 {
                seenBluetoothDevices.removeFirst(seenBluetoothDevices.count - 20)
            }
        }
        persistSeenBluetoothDevices()
        // 已認住嘅車就順手更新「最後見到」時間
        if myCarBluetooth?.id == key {
            myCarBluetooth = CarBluetoothDevice(uid: uid, name: name, lastSeen: now)
            persistMyCarBluetooth()
        }
    }

    /// 認住「我嘅車藍牙」（設定頁點選）
    func selectMyCarBluetooth(_ device: CarBluetoothDevice) {
        myCarBluetooth = device
        persistMyCarBluetooth()
    }

    func clearMyCarBluetooth() {
        myCarBluetooth = nil
        UserDefaults.standard.removeObject(forKey: myCarBluetoothKey)
    }

    /// 斷線嗰個係咪「我嘅車」——UID 為主（同一部車長期穩定），名做後備（萬一 UID 變）
    private func isMyCarBluetooth(name: String, uid: String) -> Bool {
        guard let car = myCarBluetooth else { return false }
        if !car.uid.isEmpty, !uid.isEmpty { return car.uid == uid }
        return car.name.compare(name, options: [.caseInsensitive]) == .orderedSame
    }

    private func persistSeenBluetoothDevices() {
        if let data = try? JSONEncoder().encode(seenBluetoothDevices) {
            UserDefaults.standard.set(data, forKey: seenBluetoothDevicesKey)
        }
    }

    private func persistMyCarBluetooth() {
        if let car = myCarBluetooth, let data = try? JSONEncoder().encode(car) {
            UserDefaults.standard.set(data, forKey: myCarBluetoothKey)
        }
    }

    private func loadCarBluetoothState() {
        if let data = UserDefaults.standard.data(forKey: seenBluetoothDevicesKey),
           let list = try? JSONDecoder().decode([CarBluetoothDevice].self, from: data) {
            seenBluetoothDevices = list.sorted { $0.lastSeen > $1.lastSeen }
        }
        if let data = UserDefaults.standard.data(forKey: myCarBluetoothKey),
           let car = try? JSONDecoder().decode(CarBluetoothDevice.self, from: data) {
            myCarBluetooth = car
        }
    }

    /// 斷聯嗰刻記低候選「落車點」
    /// 已認住「我嘅車藍牙」→ 斷線嗰個一定要係部車先算（耳機／家用音響斷線徹底唔會誤判）
    /// 未認車 → 照舊要「啱啱揸緊車」先入，
    /// 行緊路藍牙耳機斷線、喺屋企熄音響都唔會當落車。
    private func handleCarAudioDisconnect(previous: AVAudioSessionRouteDescription) {
        let now = Date()
        let ports = previous.outputs.filter { Self.isCarAudioPort($0) }
        if myCarBluetooth != nil {
            guard ports.contains(where: { isMyCarBluetooth(name: $0.portName, uid: $0.uid) }) else { return }
        } else {
            let recentlyDriving = (lastAutomotiveTime.map { now.timeIntervalSince($0) < 10 * 60 } ?? false)
                || (lastHighSpeedTime.map { now.timeIntervalSince($0) < 10 * 60 } ?? false)
            guard recentlyDriving else { return }
        }
        if myCarBluetooth != nil {
            ParkingFloorStore.shared.barometer.finishForCarDisconnect()
        }
        guard let coord = medianCoordinate(around: now) else { return }
        carExitEvents.append(CarExitEvent(
            id: UUID(), date: now, latitude: coord.latitude, longitude: coord.longitude,
            settled: false, rejected: false, consumed: false
        ))
        carExitEvents.removeAll { now.timeIntervalSince($0.date) > 30 * 60 }
        persistCarExitEvents()
    }

    /// 斷聯時刻附近（±10 秒）嘅 GPS 中位數坐標（單點 fix 會跳，中位數穩定啲）
    private func medianCoordinate(around date: Date) -> CLLocationCoordinate2D? {
        let window = recentFixBuffer.filter { abs($0.date.timeIntervalSince(date)) <= 10 }
        guard !window.isEmpty else { return nil }
        let lats = window.map(\.latitude).sorted()
        let lons = window.map(\.longitude).sorted()
        return CLLocationCoordinate2D(latitude: lats[lats.count / 2], longitude: lons[lons.count / 2])
    }

    /// 斷聯事件狀態維護：60 秒後又開車 → 取消（中途斷線）；3 分鐘內安靜 → 落實
    private func updateCarExitEvents(now: Date) {
        guard !carExitEvents.isEmpty else { return }
        var changed = false
        for i in carExitEvents.indices {
            guard !carExitEvents[i].settled, !carExitEvents[i].rejected else { continue }
            let age = now.timeIntervalSince(carExitEvents[i].date)
            if age > 60, smoothedSpeed > 10 {
                carExitEvents[i].rejected = true
                changed = true
            } else if age > 3 * 60 {
                carExitEvents[i].settled = true
                changed = true
            }
        }
        if changed { persistCarExitEvents() }
    }

    /// 落停車點嗰刻搵最近嘅可用斷聯事件（用嚟修正坐標／推斷咪錶）
    /// CLVisit 成日遲過 3 分鐘先送到，所以事件就算仲未「落實」，
    /// 只要過咗 60 秒「中途斷線」判定窗口又未被取消，都可以照用。
    func latestSettledCarExit(near coordinate: CLLocationCoordinate2D, around date: Date) -> CarExitEvent? {
        let loc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let now = Date()
        return carExitEvents
            .filter { !$0.rejected && !$0.consumed }
            .filter { $0.settled || now.timeIntervalSince($0.date) > 60 }
            .filter { abs($0.date.timeIntervalSince(date)) <= 20 * 60 }
            .filter { CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: loc) < 200 }
            .max { $0.date < $1.date }
    }

    /// 標記斷聯事件已用（一個事件只修正一個停車點）
    func markCarExitConsumed(_ eventID: UUID) {
        guard let idx = carExitEvents.firstIndex(where: { $0.id == eventID }) else { return }
        carExitEvents[idx].consumed = true
        persistCarExitEvents()
    }

    private func persistCarExitEvents() {
        if let data = try? JSONEncoder().encode(carExitEvents) {
            UserDefaults.standard.set(data, forKey: carExitEventsKey)
        }
    }

    private func loadCarExitEvents() {
        guard let data = UserDefaults.standard.data(forKey: carExitEventsKey),
              let events = try? JSONDecoder().decode([CarExitEvent].self, from: data) else { return }
        let now = Date()
        carExitEvents = events.filter { now.timeIntervalSince($0.date) <= 30 * 60 }
    }

    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        // 交通模式判定：「全程揸車先算」—— 成段行程入面冇步行/跑步/騎行段先算
        // 開車到達（泊車記憶），有任何非揸車段就係非開車到達（逗留記憶）。
        // 用 CMMotionActivity 分段歷史判斷成段行程，取代以前「到達前後 5 分鐘最近模式」
        // 嗰種成日睇錯嘅估法。
        let prev = visits.first { $0.arrivalDate < visit.arrivalDate }
        let tripStart = prev?.departureDate ?? prev?.arrivalDate
        let classification = classifyTrip(tripStart: tripStart, arrival: visit.arrivalDate)
        var transport = classification.transportType
        // 段行程均速 > 80 km/h 當公共交通（巴士/火車/飛機）
        if classification.isAutomotive, let prev, let tripStart, tripStart < visit.arrivalDate {
            let dist = CLLocation(latitude: prev.latitude, longitude: prev.longitude)
                .distance(from: CLLocation(latitude: visit.coordinate.latitude, longitude: visit.coordinate.longitude))
            if dist / visit.arrivalDate.timeIntervalSince(tripStart) * 3.6 > 80 {
                transport = "Transit"
            }
        }
        let automotive = classification.isAutomotive

        let record = VisitRecord(
            id: UUID(),
            address: "",
            latitude: visit.coordinate.latitude,
            longitude: visit.coordinate.longitude,
            arrivalDate: visit.arrivalDate,
            departureDate: visit.departureDate.timeIntervalSince(visit.arrivalDate) < 7 * 24 * 3600 ? visit.departureDate : nil,
            transportType: transport,
            isAutomotive: automotive
        )

        let location = CLLocation(latitude: visit.coordinate.latitude, longitude: visit.coordinate.longitude)
        DispatchQueue.main.async {
            let matched = self.matchVisitIndex(arrivalDate: record.arrivalDate, coordinate: visit.coordinate)
            let id = matched != nil ? self.visits[matched!].id : record.id
            let base = VisitRecord(
                id: id,
                address: "",
                latitude: record.latitude,
                longitude: record.longitude,
                arrivalDate: record.arrivalDate,
                departureDate: record.departureDate,
                transportType: record.transportType,
                isAutomotive: record.isAutomotive
            )
            self.upsertVisitRecord(base)
        }

        geocoder.reverseGeocodeLocation(
            location,
            preferredLocale: Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        ) { [weak self] placemarks, error in
            guard let self else { return }
            var addr = ""
            if let placemark = placemarks?.first {
                // 順手做區域權威判定（isoCountryCode：HK/MO vs CN）
                MapRegionJudge.record(placemark: placemark, at: location.coordinate)
                // 與地圖標點採用同一命名次序：合適 POI > 所在區域。
                addr = Self.preferredPlaceName(from: placemark)
            }
            DispatchQueue.main.async {
                let matched = self.matchVisitIndex(arrivalDate: record.arrivalDate, coordinate: visit.coordinate)
                let id = matched != nil ? self.visits[matched!].id : record.id
                let updated = VisitRecord(
                    id: id,
                    address: addr.isEmpty ? "Unknown" : addr,
                    latitude: record.latitude,
                    longitude: record.longitude,
                    arrivalDate: record.arrivalDate,
                    departureDate: record.departureDate,
                    transportType: record.transportType,
                    isAutomotive: record.isAutomotive
                )
                self.upsertVisitRecord(updated)
            }
        }
    }

    private func reverseGeocode(location: CLLocation) {
        lastGeocodeLocation = location
        lastGeocodeTime = Date()
        geocoder.reverseGeocodeLocation(
            location,
            preferredLocale: Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        ) { [weak self] placemarks, error in
            guard let placemark = placemarks?.first, error == nil else { return }
            // 順手做區域權威判定（isoCountryCode：HK/MO vs CN，同 Apple/高德切換同一條邊界）
            MapRegionJudge.record(placemark: placemark, at: location.coordinate)
            DispatchQueue.main.async {
                // POI／大廈名（輪播一邊）
                let poiName = Self.preferredPOIName(from: placemark)

                // 街道名（街道＋門牌；冇街道就退地區名）——輪播另一邊。
                // 以前呢個位直接用 currentAddress 當「街道名」，而地址字串
                // 優先級係 POI名 > 地區名 > 街道名，POI 名一入咗地址，
                // 「POI名同地址一樣就清空」就永遠成立 → POI 欄永遠空 →
                // 輪播從來冇真正啟動過。所以獨立一個街道名欄出嚟。
                var streetParts: [String] = []
                if let number = placemark.subThoroughfare, let street = placemark.thoroughfare {
                    streetParts.append("\(street) \(number)")
                } else if let street = placemark.thoroughfare {
                    streetParts.append(street)
                }
                if streetParts.isEmpty {
                    if let sub = placemark.subLocality, !sub.isEmpty {
                        streetParts.append(sub)
                    }
                    if let locality = placemark.locality, !locality.isEmpty,
                       locality != placemark.subLocality {
                        streetParts.append(locality)
                    }
                }

                // 地址字串維持原本優先級：POI名 > 地區名 > 街道名
                var preferredName = Self.preferredPlaceName(from: placemark)
                if preferredName.isEmpty {
                    if let number = placemark.subThoroughfare, let street = placemark.thoroughfare {
                        preferredName = "\(street) \(number)"
                    } else if let street = placemark.thoroughfare {
                        preferredName = street
                    }
                }

                self?.currentAddress = preferredName
                self?.currentPOIName = poiName
                self?.currentStreetName = streetParts.joined(separator: " ")
                self?.currentLocality = placemark.locality ?? ""
            }
        }
    }

    private static func preferredPOIName(from placemark: CLPlacemark) -> String {
        if let area = placemark.areasOfInterest?
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) {
            return area
        }
        let name = placemark.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let street = placemark.thoroughfare?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !name.isEmpty && name != street ? name : ""
    }

    private static func preferredPlaceName(from placemark: CLPlacemark) -> String {
        let poi = preferredPOIName(from: placemark)
        if !poi.isEmpty { return poi }
        for region in [placemark.subLocality, placemark.locality, placemark.administrativeArea] {
            let value = region?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !value.isEmpty { return value }
        }
        return ""
    }

    private func matchVisitIndex(arrivalDate: Date, coordinate: CLLocationCoordinate2D) -> Int? {
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        for (idx, v) in visits.enumerated() {
            // 30 秒容差：同一個 CLVisit 幾次送達可能帶輕微唔同嘅到達時間／坐標
            // （地庫車場 GPS 質心會漂）。以前 2 秒太緊，離場事件配唔返原記錄
            // 就整出第二條重複記錄 → 舊記錄永遠顯示至今＋行程時間出負數
            let d = target.distance(from: CLLocation(latitude: v.latitude, longitude: v.longitude))
            if VisitRecord.matchesArrival(timeDifference: abs(v.arrivalDate.timeIntervalSince(arrivalDate)), distance: d) {
                return idx
            }
        }
        return nil
    }
    
    private func upsertVisitRecord(_ record: VisitRecord) {
        let previousCurDep: Date?
        let matchedIdx: Int? = matchVisitIndex(arrivalDate: record.arrivalDate, coordinate: CLLocationCoordinate2D(latitude: record.latitude, longitude: record.longitude))
        if let idx = matchedIdx {
            var cur = visits[idx]
            previousCurDep = cur.departureDate

            if let newDep = record.departureDate {
                if let oldDep = cur.departureDate {
                    cur.departureDate = max(oldDep, newDep)
                } else {
                    cur.departureDate = newDep
                }
            }

            if !record.address.isEmpty, cur.address.isEmpty || cur.address == "Unknown" {
                cur = VisitRecord(
                    id: cur.id,
                    address: record.address,
                    latitude: cur.latitude,
                    longitude: cur.longitude,
                    arrivalDate: cur.arrivalDate,
                    departureDate: cur.departureDate,
                    transportType: cur.transportType,
                    isAutomotive: cur.isAutomotive
                )
            }

            visits[idx] = cur
        } else {
            previousCurDep = nil
            visits.insert(record, at: 0)
        }

        visits.sort {
            if $0.arrivalDate != $1.arrivalDate { return $0.arrivalDate > $1.arrivalDate }
            if ($0.departureDate != nil) != ($1.departureDate != nil) { return $0.departureDate != nil }
            if let d0 = $0.departureDate, let d1 = $1.departureDate, d0 != d1 { return d0 > d1 }
            return $0.id.uuidString > $1.id.uuidString
        }
        visits = repairVisitDuplicates(visits)
        saveVisits()

        // MARK: TripPredictor: arrival / departure 掛鉤（只限開車到訪）
        Task { @MainActor in
            // 非開車到訪不納入行程預測
            guard record.isAutomotive else { return }

            // 1) Arrival Predict：新 visit（matched==nil）且 address 非空 → predictNext
            let latest = self.visits.first(where: { $0.id == record.id }) ?? record
            if matchedIdx == nil,
               !latest.address.isEmpty, latest.address != "Unknown",
               !self.predictedArrivalVisits.contains(latest.id) {
                self.predictedArrivalVisits.insert(latest.id)
                let coord = CLLocationCoordinate2D(latitude: latest.latitude, longitude: latest.longitude)
                let place = ParkingFloorStore.shared.resolvePlace(coordinate: coord, address: latest.address)
                let _ = TripPredictor.shared.predictNext(currentPlace: place, atDate: latest.arrivalDate)
            }
            // 2) Departure Learning：previous dep nil → 而家有 dep，且 fromPlace 搵得到
            if let dep = latest.departureDate, previousCurDep == nil,
               !latest.address.isEmpty, latest.address != "Unknown",
               !self.learnedDepartureVisits.contains(latest.id) {
                self.learnedDepartureVisits.insert(latest.id)
                // 搵上一個 complete visit（arrival 早過呢個 arrival 且 dep!=nil）作為 fromPlace
                let fromVisit = self.visits
                    .filter { $0.id != latest.id && $0.departureDate != nil && $0.arrivalDate < latest.arrivalDate }
                    .sorted { $0.arrivalDate > $1.arrivalDate }
                    .first
                let coord = CLLocationCoordinate2D(latitude: latest.latitude, longitude: latest.longitude)
                let toPlace = ParkingFloorStore.shared.resolvePlace(coordinate: coord, address: latest.address)
                let fromPlace: PlaceInfo?
                if let fv = fromVisit, !fv.address.isEmpty, fv.address != "Unknown" {
                    let fcoord = CLLocationCoordinate2D(latitude: fv.latitude, longitude: fv.longitude)
                    fromPlace = ParkingFloorStore.shared.resolvePlace(coordinate: fcoord, address: fv.address)
                } else {
                    fromPlace = nil
                }
                TripPredictor.shared.recordLearning(
                    fromPlace: fromPlace, toPlace: toPlace,
                    atDate: dep
                )
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            let status = manager.authorizationStatus
            // 呢個回調每次回前景都會重新廣播一次相同狀態 —— 以前無條件將
            // gpsQuality 重設 .unknown，一回前景 isGPSLost 即刻變 true，
            // 時速數字無端端變半透明＋凍結。而家淨係喺狀態真係改變時先重設。
            let statusChanged = self.authorizationStatus != status
            self.authorizationStatus = status
            if status == .authorizedWhenInUse {
                manager.requestAlwaysAuthorization()
            }
            guard statusChanged else { return }
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                self.gpsQuality = .unknown
            default:
                self.gpsQuality = .bad
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // Keep headingOrientation in sync with actual device orientation
        let desired = Self.currentDeviceOrientation()
        if manager.headingOrientation != desired {
            manager.headingOrientation = desired
        }
        let h = newHeading.magneticHeading
        DispatchQueue.main.async {
            self.heading = h
        }
    }

    func saveVisits() {
        if let data = try? JSONEncoder().encode(visits) {
            UserDefaults.standard.set(data, forKey: visitsKey)
            UserDefaults.standard.synchronize()
        }
    }

    private func loadVisits() {
        guard let data = UserDefaults.standard.data(forKey: visitsKey),
              let decoded = try? JSONDecoder().decode([VisitRecord].self, from: data) else { return }
        visits = repairVisitDuplicates(decoded.sorted { $0.arrivalDate > $1.arrivalDate })
        for v in visits {
            if v.departureDate != nil {
                learnedDepartureVisits.insert(v.id)
            }
            if !v.address.isEmpty && v.address != "Unknown" {
                predictedArrivalVisits.insert(v.id)
            }
        }
        hasLoadedVisits = true
    }

    private func repairVisitDuplicates(_ records: [VisitRecord]) -> [VisitRecord] {
        let repaired = dedupeVisits(records)
        let backupKey = "visit_records_before_duplicate_repair_v2"
        if repaired.count < records.count,
           UserDefaults.standard.data(forKey: backupKey) == nil,
           let original = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(original, forKey: backupKey)
        }
        return repaired
    }

    /// 合併重複到訪記錄：以前配對太緊，離場事件成日整出第二條重複記錄，
    /// 原記錄就永遠開住顯示至今。呢度將「同一地點 5 分鐘內到達」嘅記錄合併，
    /// 離場時間取返 iOS 系統送過嚟嗰個（原生數據，唔係 App 估出嚟）
    private func dedupeVisits(_ sorted: [VisitRecord]) -> [VisitRecord] {
        var result: [VisitRecord] = []
        for v in sorted {
            if let idx = result.firstIndex(where: {
                VisitRecord.matchesArrival(
                    timeDifference: abs($0.arrivalDate.timeIntervalSince(v.arrivalDate)),
                    distance: CLLocation(latitude: $0.latitude, longitude: $0.longitude)
                        .distance(from: CLLocation(latitude: v.latitude, longitude: v.longitude))
                )
            }) {
                var keep = result[idx]
                keep.departureDate = Self.laterDate(keep.departureDate, v.departureDate)
                if (keep.address.isEmpty || keep.address == "Unknown"), !v.address.isEmpty {
                    keep = VisitRecord(
                        id: keep.id,
                        address: v.address,
                        latitude: keep.latitude,
                        longitude: keep.longitude,
                        arrivalDate: keep.arrivalDate,
                        departureDate: keep.departureDate,
                        transportType: keep.transportType,
                        isAutomotive: keep.isAutomotive
                    )
                }
                result[idx] = keep
            } else {
                result.append(v)
            }
        }
        return result
    }

    func clearVisits() {
        visits = []
        UserDefaults.standard.removeObject(forKey: visitsKey)
    }
}

/// CMMotionActivity 交通模式分段（揸車/步行/跑步/騎行/靜止）。
/// 用嚟做行程分段顯示（🚗33min ▶ 🚶1min ▶…）同「全程揸車先算」到達判定。
struct MotionSegment: Identifiable, Codable, Equatable {
    var id: UUID
    /// Driving / Walking / Running / Cycling / Stationary / Unknown
    var mode: String
    var start: Date
    /// nil = 仲進行中
    var end: Date?

    var resolvedEnd: Date { end ?? Date() }
    var isMovement: Bool {
        mode == "Driving" || mode == "Walking" || mode == "Running" || mode == "Cycling"
    }

    /// 夾入 [from, to] 窗口；完全喺窗口外就回傳 nil
    func clipped(from: Date, to: Date) -> MotionSegment? {
        let s = max(start, from)
        let e = min(resolvedEnd, to)
        guard e > s else { return nil }
        return MotionSegment(id: id, mode: mode, start: s, end: e)
    }
}

struct ParkingPointRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var address: String
    var latitude: Double
    var longitude: Double
    var createdAt: Date
    var predictedFloorIndex: Int?
    var manualFloorIndex: Int?
    var confidence: Double?
    var barometerAltitudeDeltaMeters: Double?
    var barometerSampleCount: Int?
    var barometerReferenceAltitude: Double?
    var barometerFinalAltitude: Double?
    var barometerPressureKPa: Double?
    var barometerReferenceFloorIndex: Int?
    var lotAssignedByUser: Bool?
    var floorConfirmedByUser: Bool?
    var predictedFromLotLearned: Bool?
    /// 離場時自動認定：用戶泊車期間從未手動調過樓層，
    /// 離場時將自動判斷嘅樓層視為正確答案（用於累積學習數據）
    var departureConfirmed: Bool?
    // LLM 照片識別結果（持久化）
    var llmSpotNumber: String?
    var llmAreaCode: String?
    var llmFloorText: String?
    /// 是否開車到達（false = 非開車停留，顯示為「停留點」而非「停車點」）
    var isAutomotive: Bool
    /// 咪錶標注（車藍牙斷聯＋附近咪錶推斷）：實錘＝有具體錶號，估計＝淨係街道
    var meterID: String?
    var meterStreet: String?
    /// "confirmed"（實錘）／"estimated"（估計·街道級）
    var meterMatchKind: String?

    /// 咪錶標注（地圖標題／詳情用）：
    /// confirmed → 「牧愛街 7802A咪錶」；estimated → 「牧愛街咪錶」（唔標具體咪錶）
    var meterTag: String? {
        let street = meterStreet?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !street.isEmpty else { return nil }
        if meterMatchKind == "confirmed", let meterID = meterID?.trimmingCharacters(in: .whitespacesAndNewlines), !meterID.isEmpty {
            return String(format: String(localized: "%@ %@咪錶"), street, meterID)
        }
        return String(format: String(localized: "%@咪錶"), street)
    }

    mutating func removeMeterAnnotation() {
        meterID = nil
        meterStreet = nil
        meterMatchKind = nil
    }

    // 向後相容：舊資料沒有 isAutomotive 欄位時預設 true
    enum CodingKeys: String, CodingKey {
        case id, address, latitude, longitude, createdAt
        case predictedFloorIndex, manualFloorIndex, confidence
        case barometerAltitudeDeltaMeters, barometerSampleCount
        case barometerReferenceAltitude, barometerFinalAltitude, barometerPressureKPa
        case barometerReferenceFloorIndex
        case lotAssignedByUser
        case floorConfirmedByUser
        case predictedFromLotLearned, llmSpotNumber, llmAreaCode, llmFloorText
        case isAutomotive, departureConfirmed
        case meterID, meterStreet, meterMatchKind
    }

    init(
        id: UUID, address: String, latitude: Double, longitude: Double, createdAt: Date,
        predictedFloorIndex: Int? = nil, manualFloorIndex: Int? = nil, confidence: Double? = nil,
        barometerAltitudeDeltaMeters: Double? = nil, barometerSampleCount: Int? = nil,
        barometerReferenceAltitude: Double? = nil, barometerFinalAltitude: Double? = nil,
        barometerPressureKPa: Double? = nil, predictedFromLotLearned: Bool? = nil,
        llmSpotNumber: String? = nil, llmAreaCode: String? = nil, llmFloorText: String? = nil,
        isAutomotive: Bool = true, departureConfirmed: Bool? = nil,
        meterID: String? = nil, meterStreet: String? = nil, meterMatchKind: String? = nil,
        barometerReferenceFloorIndex: Int? = nil, lotAssignedByUser: Bool? = nil,
        floorConfirmedByUser: Bool? = nil
    ) {
        self.id = id
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.createdAt = createdAt
        self.predictedFloorIndex = predictedFloorIndex
        self.manualFloorIndex = manualFloorIndex
        self.confidence = confidence
        self.barometerAltitudeDeltaMeters = barometerAltitudeDeltaMeters
        self.barometerSampleCount = barometerSampleCount
        self.barometerReferenceAltitude = barometerReferenceAltitude
        self.barometerFinalAltitude = barometerFinalAltitude
        self.barometerPressureKPa = barometerPressureKPa
        self.barometerReferenceFloorIndex = barometerReferenceFloorIndex
        self.lotAssignedByUser = lotAssignedByUser
        self.floorConfirmedByUser = floorConfirmedByUser
        self.predictedFromLotLearned = predictedFromLotLearned
        self.departureConfirmed = departureConfirmed
        self.llmSpotNumber = llmSpotNumber
        self.llmAreaCode = llmAreaCode
        self.llmFloorText = llmFloorText
        self.isAutomotive = isAutomotive
        self.meterID = meterID
        self.meterStreet = meterStreet
        self.meterMatchKind = meterMatchKind
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        address = try c.decode(String.self, forKey: .address)
        latitude = try c.decode(Double.self, forKey: .latitude)
        longitude = try c.decode(Double.self, forKey: .longitude)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        predictedFloorIndex = try c.decodeIfPresent(Int.self, forKey: .predictedFloorIndex)
        manualFloorIndex = try c.decodeIfPresent(Int.self, forKey: .manualFloorIndex)
        confidence = try c.decodeIfPresent(Double.self, forKey: .confidence)
        barometerAltitudeDeltaMeters = try c.decodeIfPresent(Double.self, forKey: .barometerAltitudeDeltaMeters)
        barometerSampleCount = try c.decodeIfPresent(Int.self, forKey: .barometerSampleCount)
        barometerReferenceAltitude = try c.decodeIfPresent(Double.self, forKey: .barometerReferenceAltitude)
        barometerFinalAltitude = try c.decodeIfPresent(Double.self, forKey: .barometerFinalAltitude)
        barometerPressureKPa = try c.decodeIfPresent(Double.self, forKey: .barometerPressureKPa)
        barometerReferenceFloorIndex = try c.decodeIfPresent(Int.self, forKey: .barometerReferenceFloorIndex)
        lotAssignedByUser = try c.decodeIfPresent(Bool.self, forKey: .lotAssignedByUser)
        floorConfirmedByUser = try c.decodeIfPresent(Bool.self, forKey: .floorConfirmedByUser)
        predictedFromLotLearned = try c.decodeIfPresent(Bool.self, forKey: .predictedFromLotLearned)
        departureConfirmed = try c.decodeIfPresent(Bool.self, forKey: .departureConfirmed)
        llmSpotNumber = try c.decodeIfPresent(String.self, forKey: .llmSpotNumber)
        llmAreaCode = try c.decodeIfPresent(String.self, forKey: .llmAreaCode)
        llmFloorText = try c.decodeIfPresent(String.self, forKey: .llmFloorText)
        isAutomotive = try c.decodeIfPresent(Bool.self, forKey: .isAutomotive) ?? true
        meterID = try c.decodeIfPresent(String.self, forKey: .meterID)
        meterStreet = try c.decodeIfPresent(String.self, forKey: .meterStreet)
        meterMatchKind = try c.decodeIfPresent(String.self, forKey: .meterMatchKind)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var displayFloor: String? {
        // 慣例跟停車點所在地判定（深圳點用內地慣例，你喺香港睇返都啱）
        // llmFloorText 可能係 VLM／手輸殘留（「地面1」）—— 顯示前正規化，
        // 唔係嘅話地圖標籤會變「地面1/F」（"/F" 後綴再疊埋落去）
        let cleanText = ParkingFloorStore.cleanFloorText(llmFloorText, coordinate: coordinate)
        if let manualFloorIndex {
            return cleanText ?? ParkingFloorStore.formatFloor(manualFloorIndex, coordinate: coordinate)
        }
        if let predictedFloorIndex {
            return cleanText ?? ParkingFloorStore.formatFloor(predictedFloorIndex, coordinate: coordinate)
        }
        return cleanText
    }
}

extension ParkingPointRecord {
    var effectiveFloorIndex: Int? {
        manualFloorIndex ?? ParkingFloorStore.parseFloorIndex(llmFloorText ?? "", coordinate: coordinate)
            ?? predictedFloorIndex
    }

    var isFloorConfirmed: Bool {
        floorConfirmedByUser ?? (manualFloorIndex != nil && llmFloorText == nil)
    }

    var floorStatusLabel: String {
        guard effectiveFloorIndex != nil else { return String(localized: "樓層未確認") }
        return isFloorConfirmed ? String(localized: "已確認") : String(localized: "估算")
    }
}

// MARK: - 車藍牙斷聯事件、咪錶標注、最近刪除（回收桶）

/// 停車點嘅咪錶標注：實錘（有具體錶號）／估計（淨係街道）
struct ParkingPointMeterAnnotation {
    let meterID: String?
    let street: String
    /// "confirmed"（實錘）／"estimated"（估計）
    let kind: String
    /// 實錘時要 snap 去嘅咪錶坐標（估計為 nil，沿用斷聯坐標）
    let snapCoordinate: CLLocationCoordinate2D?
}

/// 車載音訊（藍牙 A2DP/HFP／CarPlay）斷聯嗰刻嘅候選「落車點」。
/// 熄火／鎖車一刻斷聯，嗰個 GPS 位置比 CLVisit 到達中心更接近真正車位。
/// 見過／認定嘅車載藍牙音訊裝置（音訊路由入面讀到嘅名 + UID）
struct CarBluetoothDevice: Codable, Hashable, Identifiable {
    var uid: String
    var name: String
    var lastSeen: Date
    /// UID 為主（同一部車穩定），冇 UID 先用名
    var id: String { uid.isEmpty ? name : uid }
}

struct CarExitEvent: Codable, Hashable {
    let id: UUID
    let date: Date
    let latitude: Double
    let longitude: Double
    /// 斷聯後 3 分鐘內冇再開車先落實
    var settled: Bool
    /// 斷聯後 60 秒之後又開車 → 取消（中途斷線，唔係落車）
    var rejected: Bool
    /// 已經用嚟修正過停車點坐標
    var consumed: Bool

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// 回收桶入面嘅一條停車點（連埋刪除時嘅 lot 名，還原嗰陣用嚟對名合併）
struct DeletedPointEntry: Identifiable, Codable, Hashable {
    /// 同一批刪除（成個 lot 刪除）共用一個 batchID
    let batchID: UUID
    let point: ParkingPointRecord
    /// 刪除時個 lot 嘅顯示名（還原合併對名用）
    let lotName: String?
    let deletedAt: Date

    var id: UUID { point.id }
    var coordinate: CLLocationCoordinate2D { point.coordinate }
}

/// 回收桶入面嘅一條學習地點
struct DeletedPlaceEntry: Identifiable, Codable, Hashable {
    let place: PlaceInfo
    let deletedAt: Date

    var id: String { place.key }
    var displayName: String { place.displayName }
    var coordinate: CLLocationCoordinate2D { place.coordinate }
}

// MARK: - 香港／內地區域判定（幾何邊界線 + geocode 權威緩存）

/// 判定坐標係「香港/澳門/台灣」（WGS-84 圖框、香港樓層慣例）
/// 定「內地」（GCJ-02 圖框、內地樓層慣例）。
/// 兩層判定：
/// 1. geocode 權威緩存：reverseGeocode 拎到嘅 isoCountryCode（HK/MO vs CN）
///    —— 同 MapKit「香港 Apple Map／內地高德」自動切換係同一套數據源、同一條邊界。
/// 2. 幾何邊境分界線：緩存未命中（離線／點未 geocode 過）時即時判定。
enum MapRegionJudge {
    /// 幾何判定：坐標係咪內地（GCJ-02 圖框）
    static func isMainlandGeometric(_ c: CLLocationCoordinate2D) -> Bool {
        // 中國大致範圍外 = 海外（唔轉換）
        guard c.longitude >= 72.004 && c.longitude <= 137.8347 &&
              c.latitude >= 0.8293 && c.latitude <= 55.8271 else { return false }
        // 澳門：WGS-84 圖框
        if c.longitude >= 113.52 && c.longitude <= 113.63 &&
            c.latitude >= 22.06 && c.latitude <= 22.24 { return false }
        // 台灣：WGS-84 圖框
        if c.longitude >= 119.9 && c.longitude <= 122.1 &&
            c.latitude >= 21.8 && c.latitude <= 25.4 { return false }
        return !isHongKongGeometric(c)
    }

    /// 幾何判定：坐標係咪香港（WGS-84 圖框）。
    /// 注意深圳同香港貼住邊境，純矩形框必然包埋深圳（福田 22.54°N 比沙頭角仲南），
    /// 所以要用邊境分界線近似。
    private static func isHongKongGeometric(_ c: CLLocationCoordinate2D) -> Bool {
        let lat = c.latitude, lon = c.longitude
        // 香港外框
        guard lat >= 22.15 && lat <= 22.60 && lon >= 113.83 && lon <= 114.45 else { return false }
        // 深圳灣以西：蛇口／南山半島喺深圳側，只有南岸係香港
        if lon < 113.96 { return lat < 22.45 }
        // 深圳河邊界線近似 (113.96, 22.495) → (114.22, 22.555)：
        // 線以北係深圳（南山/福田/羅湖），以南係新界北（天水圍/上水/粉嶺）
        if lon <= 114.22 {
            let borderLat = 22.495 + (lon - 113.96) * (22.555 - 22.495) / (114.22 - 113.96)
            return lat < borderLat
        }
        // 烏蛟騰以東：北面係鹽田/大鵬灣，南面係西貢
        return lat < 22.52
    }

    /// 權威判定：geocode 緩存優先（邊境位都唔會錯），退化幾何判定
    static func isMainland(_ c: CLLocationCoordinate2D) -> Bool {
        if let verdict = cachedVerdict(for: c) { return verdict }
        return isMainlandGeometric(c)
    }

    /// reverseGeocode 拎到 placemark 時寫入緩存
    static func record(placemark: CLPlacemark, at c: CLLocationCoordinate2D) {
        guard let code = placemark.isoCountryCode?.uppercased() else { return }
        let mainland: Bool
        switch code {
        case "HK", "MO", "TW": mainland = false
        case "CN": mainland = true
        default: return  // 海外唔影響呢套判定
        }
        setCachedVerdict(mainland, for: c)
    }

    // MARK: 緩存（UserDefaults，按 0.01° 網格 ≈ 1km）

    private static let cacheKey = "regionVerdictCache"

    private static func cacheBucket(for c: CLLocationCoordinate2D) -> String {
        String(format: "%.2f,%.2f", c.latitude, c.longitude)
    }

    private static func cachedVerdict(for c: CLLocationCoordinate2D) -> Bool? {
        (UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: Bool])?[cacheBucket(for: c)]
    }

    private static func setCachedVerdict(_ value: Bool, for c: CLLocationCoordinate2D) {
        var dict = UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: Bool] ?? [:]
        let key = cacheBucket(for: c)
        guard dict[key] != value else { return }
        dict[key] = value
        if dict.count > 512 { dict.removeAll() }  // 只係保險閥，實際好難到
        UserDefaults.standard.set(dict, forKey: cacheKey)
    }
}

// MARK: - GCJ-02 Coordinate Transformation (China map offset fix)

extension CLLocationCoordinate2D {
    /// Convert WGS-84 coordinate to GCJ-02 (China's offset coordinate system).
    /// In China, Apple Maps tiles use GCJ-02, but GPS returns WGS-84.
    /// The blue dot is auto-corrected by iOS, but manually placed annotations need conversion.
    var wgs84ToGCJ02: CLLocationCoordinate2D {
        // 香港/澳門/台灣/海外 = WGS-84 圖框，唔使轉換（內地圖框先係 GCJ-02）
        guard MapRegionJudge.isMainland(self) else { return self }

        let a: Double = 6378245.0
        let ee: Double = 0.00669342162296594323

        func transformLat(_ x: Double, _ y: Double) -> Double {
            var ret: Double = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
            ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
            ret += (20.0 * sin(y * .pi) + 40.0 * sin(y / 3.0 * .pi)) * 2.0 / 3.0
            ret += (160.0 * sin(y / 12.0 * .pi) + 320.0 * sin(y * .pi / 30.0)) * 2.0 / 3.0
            return ret
        }

        func transformLon(_ x: Double, _ y: Double) -> Double {
            var ret: Double = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
            ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
            ret += (20.0 * sin(x * .pi) + 40.0 * sin(x / 3.0 * .pi)) * 2.0 / 3.0
            ret += (150.0 * sin(x / 12.0 * .pi) + 300.0 * sin(x / 30.0 * .pi)) * 2.0 / 3.0
            return ret
        }

        let dLat = transformLat(longitude - 105.0, latitude - 35.0)
        let dLon = transformLon(longitude - 105.0, latitude - 35.0)
        let radLat = latitude / 180.0 * .pi
        var magic = sin(radLat)
        magic = 1.0 - ee * magic * magic
        let sqrtMagic = sqrt(magic)

        let newLat = latitude + (dLat * 180.0) / ((a * (1.0 - ee)) / (magic * sqrtMagic) * .pi)
        let newLon = longitude + (dLon * 180.0) / (a / sqrtMagic * cos(radLat) * .pi)

        return CLLocationCoordinate2D(latitude: newLat, longitude: newLon)
    }

    /// Convert GCJ-02 coordinate back to WGS-84 (iterative inverse).
    /// In China, MKLocalSearch results and MKMapView screen-tap coordinates
    /// come back in GCJ-02 (the map data's own frame). Since this app stores
    /// everything as WGS-84 and converts to GCJ-02 only at display/route time,
    /// China search/map-picked coordinates must be converted back before saving.
    var gcj02ToWGS84: CLLocationCoordinate2D {
        // 同 wgs84ToGCJ02 一致：內地圖框先有 GCJ-02 偏移，其他地方係 no-op
        guard MapRegionJudge.isMainland(self) else { return self }
        var wgs = self
        // 5 iterations converge to sub-millimetre accuracy.
        for _ in 0..<5 {
            let shifted = wgs.wgs84ToGCJ02
            wgs = CLLocationCoordinate2D(
                latitude: wgs.latitude + (latitude - shifted.latitude),
                longitude: wgs.longitude + (longitude - shifted.longitude)
            )
        }
        return wgs
    }
}

enum ParkingFloorMode: Int, CaseIterable, Identifiable {
    case fixed = 0
    case perVisit = 1
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .fixed: return String(localized: "每個地點固定樓層")
        case .perVisit: return String(localized: "相同地點不同樓層")
        }
    }
}

struct ParkingLotFloorLearning: Codable, Hashable {
    var createdAt: Date
    var manualFloorIndex: Int
    var altitudeDeltaMeters: Double
    var metersPerFloor: Double
    var lotID: UUID
    var pointID: UUID
    var referenceFloorIndex: Int? = nil
    var travelledFloors: Int { manualFloorIndex - (referenceFloorIndex ?? 0) }
}

struct ParkingFloorCalibration {
    var metersPerFloor: Double
    var offset: Double
    var confidence: Double

    static func learn(_ history: [ParkingLotFloorLearning]) -> Self? {
        // Reject sign mismatches and implausible ratios rather than teaching a wrong entry level.
        let valid = history.filter {
            $0.travelledFloors != 0 && $0.altitudeDeltaMeters.isFinite
                && (2...6).contains($0.altitudeDeltaMeters / Double($0.travelledFloors))
        }
        guard !valid.isEmpty else { return nil }
        func median(_ values: [Double]) -> Double {
            let sorted = values.sorted()
            let n = sorted.count
            return n % 2 == 0 ? (sorted[n / 2 - 1] + sorted[n / 2]) / 2 : sorted[n / 2]
        }
        var slope = median(valid.map { $0.altitudeDeltaMeters / Double($0.travelledFloors) })
        let meanFloor = valid.reduce(0.0) { $0 + Double($1.travelledFloors) } / Double(valid.count)
        let meanHeight = valid.reduce(0.0) { $0 + $1.altitudeDeltaMeters } / Double(valid.count)
        let variance = valid.reduce(0.0) { $0 + pow(Double($1.travelledFloors) - meanFloor, 2) }
        if variance > 0 {
            let covariance = valid.reduce(0.0) {
                $0 + (Double($1.travelledFloors) - meanFloor) * ($1.altitudeDeltaMeters - meanHeight)
            }
            let fitted = covariance / variance
            if (2...6).contains(fitted) { slope = fitted }
        }
        let residuals = valid.map { $0.altitudeDeltaMeters - Double($0.travelledFloors) * slope }
        let offset = max(-slope / 2, min(slope / 2, median(residuals)))
        let error = median(residuals.map { abs($0 - offset) })
        let confidence = min(0.9, 0.35 + Double(min(valid.count, 5)) * 0.08)
            * max(0.4, 1 - error / slope)
        return Self(metersPerFloor: slope, offset: offset, confidence: confidence)
    }
}

struct ParkingFloorReview: Identifiable {
    let id = UUID()
    let previousPointID: UUID
    let previousFloor: Int
    let selectedFloor: Int
    let coordinate: CLLocationCoordinate2D
}

struct ParkingBoundaryVertex: Identifiable, Codable, Hashable {
    var id = UUID()
    var latitude: Double
    var longitude: Double
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum ParkingBoundaryGeometry {
    static func contains(_ coordinate: CLLocationCoordinate2D, vertices: [ParkingBoundaryVertex]) -> Bool {
        guard vertices.count >= 3 else { return false }
        let points = projected(vertices, around: coordinate)
        var inside = false
        for i in points.indices {
            let a = points[i], b = points[(i + 1) % points.count]
            let cross = a.x * b.y - a.y * b.x
            if abs(cross) < 0.001 && a.x * b.x + a.y * b.y <= 0 { return true }
            if (a.y > 0) != (b.y > 0), 0 < a.x + (b.x - a.x) * (-a.y) / (b.y - a.y) {
                inside.toggle()
            }
        }
        return inside
    }

    static func isValid(_ vertices: [ParkingBoundaryVertex]) -> Bool {
        guard (3...24).contains(vertices.count), Set(vertices.map(\.id)).count == vertices.count,
              vertices.allSatisfy({ CLLocationCoordinate2DIsValid($0.coordinate) }) else { return false }
        let p = projected(vertices, around: vertices[0].coordinate)
        var area = 0.0
        for i in p.indices {
            let a = p[i], b = p[(i + 1) % p.count]
            guard hypot(b.x - a.x, b.y - a.y) >= 1 else { return false }
            area += a.x * b.y - b.x * a.y
            for j in p.indices where j > i + 1 && !(i == 0 && j == p.count - 1) {
                let c = p[j], d = p[(j + 1) % p.count]
                if intersects(a, b, c, d) { return false }
            }
        }
        return abs(area) >= 50
    }

    private static func projected(_ vertices: [ParkingBoundaryVertex], around center: CLLocationCoordinate2D) -> [(x: Double, y: Double)] {
        vertices.map { (x: ($0.longitude - center.longitude) * 111_000 * max(0.2, cos(center.latitude * .pi / 180)),
                        y: ($0.latitude - center.latitude) * 111_000) }
    }

    private static func intersects(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double),
                                   _ c: (x: Double, y: Double), _ d: (x: Double, y: Double)) -> Bool {
        func cross(_ p: (x: Double, y: Double), _ q: (x: Double, y: Double), _ r: (x: Double, y: Double)) -> Double {
            (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)
        }
        let abC = cross(a, b, c), abD = cross(a, b, d), cdA = cross(c, d, a), cdB = cross(c, d, b)
        if abC * abD < 0 && cdA * cdB < 0 { return true }
        func onSegment(_ p: (x: Double, y: Double), _ q: (x: Double, y: Double), _ r: (x: Double, y: Double), _ cross: Double) -> Bool {
            abs(cross) < 0.001 && r.x >= min(p.x, q.x) && r.x <= max(p.x, q.x)
                && r.y >= min(p.y, q.y) && r.y <= max(p.y, q.y)
        }
        return onSegment(a, b, c, abC) || onSegment(a, b, d, abD) || onSegment(c, d, a, cdA) || onSegment(c, d, b, cdB)
    }
}

struct ParkingLotRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String?
    var centerLatitude: Double
    var centerLongitude: Double
    var radiusMeters: Double
    var createdAt: Date
    var updatedAt: Date
    var locality: String?  // 城市/地區名（用於篩選）
    var points: [ParkingPointRecord]
    var learnedMetersPerFloor: Double?
    var learnedOffsetMeters: Double?
    var learnedConfidence: Double?
    var floorLearningHistory: [ParkingLotFloorLearning]?
    var fixedFloorIndex: Int? = nil
    var floorNames: [String: String]? = nil
    /// Only explicitly separated facilities constrain horizontal matching to a floor.
    var floorScopeIndex: Int? = nil
    var boundaryVertices: [ParkingBoundaryVertex]? = nil

    var centerCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: centerLatitude, longitude: centerLongitude)
    }

    /// 地圖標點、地點管理及預測資料共用同一個名稱來源。
    /// 已辨認的 POI／停車場名優先；沒有時才退回所在地區。
    var preferredDisplayName: String? {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedName.isEmpty { return trimmedName }
        let trimmedLocality = locality?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedLocality.isEmpty ? nil : trimmedLocality
    }

    func displayName(for point: ParkingPointRecord, mode: ParkingFloorMode) -> String? {
        if mode == .perVisit, let floor = point.effectiveFloorIndex,
           let name = floorNames?[String(floor)], !name.isEmpty {
            let base = preferredDisplayName ?? point.address
            return base.isEmpty || base == name ? name : "\(base) \(name)"
        }
        return preferredDisplayName
    }

    func centerDistance(to coordinate: CLLocationCoordinate2D) -> Double {
        let a = CLLocation(latitude: centerLatitude, longitude: centerLongitude)
        let b = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return a.distance(from: b)
    }
}

struct ParkingRecordGroup: Identifiable {
    struct ID: Hashable {
        let lotID: UUID
        let floor: Int?
        let isAutomotive: Bool
    }
    let id: ID
    let records: [ParkingPointRecord]
    var latest: ParkingPointRecord { records[0] }

    static func make(lots: [ParkingLotRecord], mode: ParkingFloorMode,
                     including pointIDs: Set<UUID>? = nil) -> [Self] {
        var result: [Self] = []
        for lot in lots {
            var groups: [ID: [ParkingPointRecord]] = [:]
            for point in lot.points where pointIDs?.contains(point.id) ?? true {
                let floor: Int? = mode == .perVisit && point.isAutomotive ? point.effectiveFloorIndex : nil
                let key = ID(lotID: lot.id, floor: floor, isAutomotive: point.isAutomotive)
                groups[key, default: []].append(point)
            }
            for (key, points) in groups {
                let sorted = points.sorted(by: newer)
                result.append(Self(id: key, records: sorted))
            }
        }
        return result.sorted { newer($0.latest, $1.latest) }
    }

    private static func newer(_ a: ParkingPointRecord, _ b: ParkingPointRecord) -> Bool {
        if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
        return a.id.uuidString < b.id.uuidString
    }
}

enum ParkingLevelLayout {
    struct Site {
        var anchor: CLLocationCoordinate2D
        var points: [ParkingPointRecord]
    }

    static func eastOffsets(for points: [ParkingPointRecord]) -> [UUID: Double] {
        var sites: [Site] = []
        var cells: [String: [Int]] = [:]
        func cell(_ c: CLLocationCoordinate2D) -> (Int, Int) {
            (Int(floor(c.latitude * 111_000 / 20)), Int(floor(c.longitude * 111_000 / 20)))
        }
        for point in points.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            guard point.isAutomotive, point.manualFloorIndex != nil || point.predictedFloorIndex != nil else { continue }
            let (x, y) = cell(point.coordinate)
            let location = CLLocation(latitude: point.latitude, longitude: point.longitude)
            var nearby: [Int] = []
            for dx in -1...1 { for dy in -1...1 { nearby += cells["\(x + dx):\(y + dy)"] ?? [] } }
            if let index = nearby.first(where: {
                location.distance(from: CLLocation(latitude: sites[$0].anchor.latitude,
                                                   longitude: sites[$0].anchor.longitude)) < 12
            }) {
                sites[index].points.append(point)
            } else {
                cells["\(x):\(y)", default: []].append(sites.count)
                sites.append(Site(anchor: point.coordinate, points: [point]))
            }
        }
        var result: [UUID: Double] = [:]
        for site in sites {
            let floors = Set(site.points.compactMap { $0.manualFloorIndex ?? $0.predictedFloorIndex }).sorted()
            guard floors.count > 1 else { continue }
            for point in site.points {
                guard let floor = point.manualFloorIndex ?? point.predictedFloorIndex,
                      let rank = floors.firstIndex(of: floor) else { continue }
                result[point.id] = (Double(rank) - Double(floors.count - 1) / 2) * 10
            }
        }
        return result
    }

    static func offset(_ coordinate: CLLocationCoordinate2D, eastMeters: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: coordinate.latitude,
            longitude: coordinate.longitude + eastMeters / (111_000 * max(0.2, cos(coordinate.latitude * .pi / 180))))
    }
}

/// 當前泊車會話快照（從 lots 計算，不額外儲存）
struct ParkingSessionSnapshot {
    var locationName: String?   // 已命名的停車場名 或 地址
    var spotNumber: String?     // 車位號
    var areaCode: String?       // 區域
    var floorDisplay: String?   // 樓層顯示文字
    var floorIndex: Int?        // 樓層指數
}

final class ParkingFloorStore: ObservableObject {
    static let defaultRadiusMeters: Double = 180
    static let defaultMetersPerFloor: Double = 3.0

    nonisolated(unsafe) static let shared = ParkingFloorStore()

    @Published private(set) var lots: [ParkingLotRecord] = [] {
        didSet {
            cachedPoints = nil
            cachedLotNames = nil
            cachedRecordGroups = nil
            cachedMapPoints = nil
            mapRevision &+= 1
        }
    }
    private var cachedPoints: [ParkingPointRecord]?
    private var cachedLotNames: [UUID: String]?
    private var cachedRecordGroups: [ParkingRecordGroup]?
    private var cachedMapPoints: [ParkingPointRecord]?
    private(set) var mapRevision = 0
    /// 當前活躍的停車場 ID（最近一次 recordParkingPoint 命中的 lot）
    @Published var activeLotID: UUID?
    @Published private(set) var floorMode: ParkingFloorMode = .fixed
    @Published var floorReview: ParkingFloorReview?
    private var reviewedCaptureIDs: Set<UUID> = []

    /// 最近一次低速/停留時的 GPS 位置（用於修正泊車位置，避免使用 visit 到達位置）
    var lastStationaryCoordinate: CLLocationCoordinate2D?

    private let storeKey = "parking_floor_store_v1"
    private let defaults: UserDefaults

    // MARK: - 最近刪除（回收桶，7 日保留）
    @Published private(set) var deletedPoints: [DeletedPointEntry] = []
    @Published private(set) var deletedPlaces: [DeletedPlaceEntry] = []
    private let deletedPointsKey = "deleted_parking_points_v1"
    private let deletedPlacesKey = "deleted_places_v1"
    /// 回收保留期：7 日後自動清理
    static let trashRetention: TimeInterval = 7 * 24 * 3600

    let barometer = BarometerSessionManager()
    private var hasLoaded = false
    private var floorResultSubscription: AnyCancellable?

    init() {
        defaults = UserDefaults(suiteName: "group.com.gorilla.translate") ?? .standard
        floorMode = ParkingFloorMode(rawValue: defaults.integer(forKey: "parkingFloorMode")) ?? .fixed
        floorResultSubscription = barometer.$completedResult.compactMap { $0 }
            .removeDuplicates().receive(on: RunLoop.main).sink { [weak self] result in
                guard let self, self.hasLoaded, !result.userConfirmed,
                      self.barometer.completedResult == result else { return }
                self.applyCapturedFloor(result)
            }
    }

    func setFloorMode(_ mode: ParkingFloorMode) {
        guard mode != floorMode else { return }
        floorMode = mode
        defaults.set(mode.rawValue, forKey: "parkingFloorMode")
        cachedLotNames = nil
        cachedRecordGroups = nil
        cachedMapPoints = nil
        mapRevision &+= 1
        // Do not rewrite, merge or reclassify historical visits on a settings change.
    }

    func setFloorName(lotID: UUID, floor: Int, name: String) {
        guard let index = lots.firstIndex(where: { $0.id == lotID }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if lots[index].floorNames == nil { lots[index].floorNames = [:] }
        lots[index].floorNames?[String(floor)] = trimmed.isEmpty ? nil : trimmed
        lots[index].updatedAt = Date()
        persist()
    }

    func setLotFloorScope(lotID: UUID, floor: Int?) {
        guard let index = lots.firstIndex(where: { $0.id == lotID }) else { return }
        lots[index].floorScopeIndex = floor.map { max(-10, min(30, $0)) }
        lots[index].updatedAt = Date()
        persist()
    }

    func setReferenceFloor(pointID: UUID, floor: Int) {
        guard let li = lots.firstIndex(where: { $0.points.contains { $0.id == pointID } }),
              let pi = lots[li].points.firstIndex(where: { $0.id == pointID }) else { return }
        let reference = max(-10, min(30, floor))
        lots[li].points[pi].barometerReferenceFloorIndex = reference
        let point = lots[li].points[pi]
        if let delta = point.barometerAltitudeDeltaMeters {
            if let manual = point.manualFloorIndex {
                applyFloorLearning(lotIndex: li, pointID: pointID, manualFloorIndex: manual,
                                   altitudeDeltaMeters: delta)
            } else {
                lots[li].points[pi].predictedFloorIndex = estimatedFloor(near: point.coordinate,
                    delta: delta, referenceFloor: reference)
            }
        }
        lots[li].updatedAt = Date()
        persist()
    }

    func requestFloorReview(captureID: UUID) {
        guard floorMode == .perVisit, !reviewedCaptureIDs.contains(captureID),
              let result = barometer.completedResult, result.id == captureID,
              result.userConfirmed, let selected = result.selectedFloor,
              let lat = result.latitude, let lon = result.longitude else { return }
        reviewedCaptureIDs.insert(captureID)
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let index = result.pointID.flatMap { id in lots.firstIndex { $0.points.contains { $0.id == id } } }
            ?? findLotIndex(near: coordinate, radiusMeters: Self.defaultRadiusMeters)
        guard let index,
              let previous = lots[index].points.filter({
                  $0.id != result.pointID && $0.createdAt < result.startedAt && $0.manualFloorIndex != nil
              }).max(by: { $0.createdAt < $1.createdAt }),
              let floor = previous.manualFloorIndex, floor != selected else { return }
        floorReview = ParkingFloorReview(previousPointID: previous.id, previousFloor: floor,
                                        selectedFloor: selected, coordinate: coordinate)
    }

    func resolveFloorReview(correctPrevious: Bool) {
        guard let review = floorReview else { return }
        floorReview = nil
        if correctPrevious {
            setManualFloor(pointID: review.previousPointID, floorIndex: review.selectedFloor)
        }
    }

    var currentPoint: ParkingPointRecord? { allPoints.first }

    /// Metadata edits and late historical callbacks must not select the live session.
    var currentSession: ParkingSessionSnapshot? {
        guard let point = currentPoint, let lot = lot(containing: point.id) else { return nil }
        let lotName = lot.displayName(for: point, mode: floorMode)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let locationName = (lotName?.isEmpty == false) ? lotName : (point.address.isEmpty ? nil : point.address)
        let floorDisplay = ParkingFloorStore.cleanFloorText(point.llmFloorText, coordinate: point.coordinate) ?? point.displayFloor
        let floorIndex = point.manualFloorIndex ?? point.predictedFloorIndex
        return ParkingSessionSnapshot(
            locationName: locationName,
            spotNumber: point.llmSpotNumber,
            areaCode: point.llmAreaCode,
            floorDisplay: floorDisplay,
            floorIndex: floorIndex
        )
    }

    func session(forArrival arrival: Date) -> ParkingSessionSnapshot? {
        guard let point = currentPoint, abs(point.createdAt.timeIntervalSince(arrival)) <= 600 else { return nil }
        return currentSession
    }

    /// 更新活躍停車點的 LLM 照片識別結果
    func updateLLMData(spotNumber: String?, areaCode: String?, floorText: String?, floorIndex: Int?,
                       userConfirmedFloor: Bool = false) {
        guard let point = currentPoint,
              let lotIdx = lots.firstIndex(where: { $0.points.contains(where: { $0.id == point.id }) }),
              let pointIdx = lots[lotIdx].points.firstIndex(where: { $0.id == point.id }) else { return }
        // 先落樓層指數（setManualFloor 改指數時會清走 llmFloorText），
        // 之後先寫樓層文字 —— 編輯器輸入嘅牌面文字唔會被自己清走
        if let floorIndex {
            if userConfirmedFloor {
                setManualFloor(pointID: point.id, floorIndex: floorIndex)
            } else if !point.isFloorConfirmed {
                lots[lotIdx].points[pointIdx].predictedFloorIndex = floorIndex
                lots[lotIdx].points[pointIdx].manualFloorIndex = nil
                lots[lotIdx].points[pointIdx].floorConfirmedByUser = false
            }
        }
        lots[lotIdx].points[pointIdx].llmSpotNumber = spotNumber
        lots[lotIdx].points[pointIdx].llmAreaCode = areaCode
        // 樓層文字入store前正規化（「地面1」→「1」），源頭清走「地面」雜字
        if userConfirmedFloor || !point.isFloorConfirmed {
            lots[lotIdx].points[pointIdx].llmFloorText = ParkingFloorStore.cleanFloorText(floorText, coordinate: point.coordinate)
        }
        lots[lotIdx].updatedAt = Date()
        persist()
    }

    func prepare() {
        guard !hasLoaded, UIApplication.shared.isProtectedDataAvailable else { return }
        floorMode = ParkingFloorMode(rawValue: defaults.integer(forKey: "parkingFloorMode")) ?? .fixed
        loadTrash()
        load()
        hasLoaded = true
    }

    // TripPredictor place resolution helper
    @MainActor
    func resolvePlace(coordinate: CLLocationCoordinate2D, address: String) -> PlaceInfo {
        TripPredictor.shared.resolvePlace(
            coordinate: coordinate,
            address: address,
            parkingLots: lots
        )
    }
    
    var allPoints: [ParkingPointRecord] {
        if let cachedPoints { return cachedPoints }
        let points = lots.flatMap { $0.points }.sorted { $0.createdAt > $1.createdAt }
        cachedPoints = points
        return points
    }
    
    var mapPoints: [ParkingPointRecord] {
        if let cachedMapPoints { return cachedMapPoints }
        let sites = lots.sorted {
            ($0.points.map(\.createdAt).max() ?? $0.createdAt) > ($1.points.map(\.createdAt).max() ?? $1.createdAt)
        }.prefix(30)
        let ids = Set(sites.map(\.id))
        let points = recordGroups.filter { ids.contains($0.id.lotID) }.map(\.latest)
        cachedMapPoints = points
        return points
    }

    var recordGroups: [ParkingRecordGroup] {
        if let cachedRecordGroups { return cachedRecordGroups }
        let groups = ParkingRecordGroup.make(lots: lots, mode: floorMode)
        cachedRecordGroups = groups
        return groups
    }

    func recordGroup(containing pointID: UUID) -> ParkingRecordGroup? {
        recordGroups.first { $0.records.contains { $0.id == pointID } }
    }

    func setManualFloors(pointIDs: Set<UUID>, floorIndex: Int) {
        let ids = allPoints.filter { pointIDs.contains($0.id) && $0.isAutomotive }.map(\.id)
        for id in ids {
            setManualFloor(pointID: id, floorIndex: max(-10, min(30, floorIndex)), persistChanges: false)
        }
        if !ids.isEmpty { persist() }
    }

    var lotNameByPointID: [UUID: String] {
        if let cachedLotNames { return cachedLotNames }
        var result: [UUID: String] = [:]
        for lot in lots {
            for p in lot.points {
                guard let name = lot.displayName(for: p, mode: floorMode) else { continue }
                result[p.id] = name
            }
        }
        cachedLotNames = result
        return result
    }

    func displayName(for visit: LocationManager.VisitRecord) -> String {
        let location = CLLocation(latitude: visit.latitude, longitude: visit.longitude)
        let matches = lots.flatMap { lot in
            lot.points.compactMap { point -> (name: String, time: TimeInterval, distance: Double)? in
                let time = abs(point.createdAt.timeIntervalSince(visit.arrivalDate))
                let distance = location.distance(from: CLLocation(latitude: point.latitude, longitude: point.longitude))
                guard time <= 600, distance <= max(150, lot.radiusMeters) || (time <= 30 && distance < 500) else {
                    return nil
                }
                let name = lot.displayName(for: point, mode: floorMode) ?? point.address
                guard !name.isEmpty else { return nil }
                return (name, time, distance)
            }
        }
        return matches.min {
            if $0.time != $1.time { return $0.time < $1.time }
            return $0.distance < $1.distance
        }?.name ?? visit.address
    }
    
    func clearAll() {
        lots = []
        persist()
    }

    /// 更新最接近某個時間的停車點的 isAutomotive 標記
    func updateAutomotiveFlag(createdAt: Date, isAutomotive: Bool) {
        for i in lots.indices {
            for j in lots[i].points.indices {
                let point = lots[i].points[j]
                if abs(point.createdAt.timeIntervalSince(createdAt)) < 60 {
                    lots[i].points[j].isAutomotive = isAutomotive
                    objectWillChange.send()
                    persist()
                    return
                }
            }
        }
    }

    func recordParkingPoint(
        from visit: LocationManager.VisitRecord,
        defaultLotName: String? = nil,
        preferredCoordinate: CLLocationCoordinate2D? = nil,
        meter: ParkingPointMeterAnnotation? = nil
    ) {
        // 坐標優先級：咪錶確認吸附 > 車藍牙斷聯位置 > 停留時 GPS 位置 > visit 位置
        let visitCoord = CLLocationCoordinate2D(latitude: visit.latitude, longitude: visit.longitude)
        let visitLoc = CLLocation(latitude: visitCoord.latitude, longitude: visitCoord.longitude)
        let preferred = meter?.snapCoordinate ?? preferredCoordinate
        let coordinate: CLLocationCoordinate2D
        if let pref = preferred {
            let prefLoc = CLLocation(latitude: pref.latitude, longitude: pref.longitude)
            // 偏離 visit 太遠就唔用（防止錯誤吸附）
            if prefLoc.distance(from: visitLoc) < 200 {
                coordinate = pref
            } else {
                coordinate = visitCoord
            }
        } else if let statCoord = lastStationaryCoordinate {
            let statLoc = CLLocation(latitude: statCoord.latitude, longitude: statCoord.longitude)
            // 如果停留位置距離 visit 位置 < 200m，使用停留位置（更準確）
            if statLoc.distance(from: visitLoc) < 200 {
                coordinate = statCoord
            } else {
                coordinate = visitCoord
            }
        } else {
            coordinate = visitCoord
        }

        // 非開車到達不需要樓層偵測 — 直接建點，無樓層資訊
        if !visit.isAutomotive {
            recordParkingPoint(
                coordinate: coordinate,
                address: visit.address,
                createdAt: visit.arrivalDate,
                predictedFloorIndex: nil,
                manualFloorIndex: nil,
                confidence: nil,
                altitudeDelta: nil,
                sampleCount: nil,
                referenceAlt: nil,
                finalAlt: nil,
                pressure: nil,
                predictedFromLotLearned: false,
                isAutomotive: false,
                defaultLotName: defaultLotName,
                meter: meter
            )
            return
        }

        // Only a frozen capture belonging to this arrival can supply a floor.
        let capture = barometer.result(for: visit.arrivalDate, coordinate: coordinate)
        let predicted = predictFloor(
            near: coordinate, createdAt: visit.arrivalDate,
            altitudeDelta: capture?.deltaMeters, sampleCount: capture?.sampleCount,
            referenceAlt: capture?.referenceAltitude, finalAlt: capture?.finalAltitude,
            pressure: capture?.pressure, referenceFloor: capture?.referenceFloorIndex ?? 0
        )
        recordParkingPoint(
            coordinate: coordinate, address: visit.address, createdAt: visit.arrivalDate,
            predictedFloorIndex: capture?.selectedFloor ?? predicted.floorIndex,
            manualFloorIndex: nil, confidence: predicted.confidence,
            altitudeDelta: capture?.deltaMeters, sampleCount: capture?.sampleCount,
            referenceAlt: capture?.referenceAltitude, finalAlt: capture?.finalAltitude,
            pressure: capture?.pressure, predictedFromLotLearned: predicted.fromLotLearned,
            isAutomotive: true, defaultLotName: defaultLotName, meter: meter
        )
        if var capture,
           let point = allPoints.first(where: {
               abs($0.createdAt.timeIntervalSince(visit.arrivalDate)) < 1
                   && CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(
                       from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) < 10
           }) {
            barometer.bindResult(capture.id, pointID: point.id, arrival: point.createdAt)
            capture.pointID = point.id
            applyCapturedFloor(capture)
        }
    }

    func saveCapturedFloor(captureID: UUID, floor: Int, userConfirmed: Bool) {
        barometer.setFloor(floor, userConfirmed: userConfirmed, captureID: captureID)
        if let result = barometer.completedResult, result.id == captureID { applyCapturedFloor(result) }
    }

    private func applyCapturedFloor(_ result: ParkingAltitudeResult) {
        let matchedPoint: ParkingPointRecord?
        if let pointID = result.pointID {
            matchedPoint = allPoints.first { $0.id == pointID && $0.isAutomotive }
        } else {
            matchedPoint = allPoints.filter {
                $0.isAutomotive && result.matches(arrival: $0.createdAt, coordinate: $0.coordinate)
            }.min { abs($0.createdAt.timeIntervalSince(result.arrivalDate))
                < abs($1.createdAt.timeIntervalSince(result.arrivalDate)) }
        }
        guard let matchedPoint, let li = lots.firstIndex(where: { $0.points.contains { $0.id == matchedPoint.id } }),
              let pi = lots[li].points.firstIndex(where: { $0.id == matchedPoint.id }) else { return }
        let point = matchedPoint
        let coordinate = point.coordinate
        let initiallyUnknown = point.manualFloorIndex == nil && point.predictedFloorIndex == nil
        // Photo / later manual edits must not be overwritten by an estimate.
        if !result.userConfirmed && point.isFloorConfirmed { return }
        let prediction = predictFloor(near: coordinate, createdAt: point.createdAt,
            altitudeDelta: result.deltaMeters, sampleCount: result.sampleCount,
            referenceAlt: result.referenceAltitude, finalAlt: result.finalAltitude, pressure: result.pressure,
            referenceFloor: result.referenceFloorIndex ?? 0)
        let estimated = result.selectedFloor ?? prediction.floorIndex ?? estimatedFloor(near: coordinate,
            delta: result.deltaMeters, referenceFloor: result.referenceFloorIndex ?? 0)
        lots[li].points[pi].predictedFloorIndex = max(-10, min(30, estimated))
        if Self.parseFloorIndex(point.llmFloorText ?? "", coordinate: coordinate) == nil {
            lots[li].points[pi].llmFloorText = nil
        }
        lots[li].points[pi].barometerAltitudeDeltaMeters = result.deltaMeters
        lots[li].points[pi].barometerSampleCount = result.sampleCount
        lots[li].points[pi].barometerReferenceAltitude = result.referenceAltitude
        lots[li].points[pi].barometerFinalAltitude = result.finalAltitude
        lots[li].points[pi].barometerPressureKPa = result.pressure
        lots[li].points[pi].barometerReferenceFloorIndex = result.referenceFloorIndex
        lots[li].points[pi].confidence = result.hasSamplingGap == true
            ? min(prediction.confidence ?? 0.3, 0.35) : prediction.confidence
        barometer.bindResult(result.id, pointID: point.id, arrival: point.createdAt)
        if result.userConfirmed, let floor = result.selectedFloor {
            setManualFloor(pointID: point.id, floorIndex: floor,
                           learnFromAltitude: result.hasSamplingGap != true)
        } else {
            persist()
        }
        if floorMode == .perVisit, point.lotAssignedByUser != true,
           let floor = result.selectedFloor ?? prediction.floorIndex,
           initiallyUnknown || (lots[li].floorScopeIndex != nil && lots[li].floorScopeIndex != floor),
           let target = findLotIndex(near: coordinate, radiusMeters: Self.defaultRadiusMeters, floorIndex: floor),
           lots[target].floorScopeIndex == floor, lots[target].id != lots[li].id {
            movePoint(point.id, toLotID: lots[target].id, manuallyAssigned: false)
        }
    }
    
    func recordParkingPoint(
        coordinate: CLLocationCoordinate2D,
        address: String,
        createdAt: Date,
        predictedFloorIndex: Int?,
        manualFloorIndex: Int?,
        confidence: Double?,
        isAutomotive: Bool = true,
        defaultLotName: String? = nil
    ) {
        recordParkingPoint(
            coordinate: coordinate,
            address: address,
            createdAt: createdAt,
            predictedFloorIndex: predictedFloorIndex,
            manualFloorIndex: manualFloorIndex,
            confidence: confidence,
            altitudeDelta: nil,
            sampleCount: nil,
            referenceAlt: nil,
            finalAlt: nil,
            pressure: nil,
            predictedFromLotLearned: nil,
            isAutomotive: isAutomotive,
            defaultLotName: defaultLotName
        )
    }

    private func recordParkingPoint(
        coordinate: CLLocationCoordinate2D,
        address: String,
        createdAt: Date,
        predictedFloorIndex: Int?,
        manualFloorIndex: Int?,
        confidence: Double?,
        altitudeDelta: Double?,
        sampleCount: Int?,
        referenceAlt: Double?,
        finalAlt: Double?,
        pressure: Double?,
        predictedFromLotLearned: Bool?,
        isAutomotive: Bool = true,
        defaultLotName: String? = nil,
        meter: ParkingPointMeterAnnotation? = nil
    ) {
        let now = Date()
        let inserting = ParkingPointRecord(
            id: UUID(),
            address: address,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            createdAt: createdAt,
            predictedFloorIndex: predictedFloorIndex,
            manualFloorIndex: manualFloorIndex,
            confidence: confidence,
            barometerAltitudeDeltaMeters: altitudeDelta,
            barometerSampleCount: sampleCount,
            barometerReferenceAltitude: referenceAlt,
            barometerFinalAltitude: finalAlt,
            barometerPressureKPa: pressure,
            predictedFromLotLearned: predictedFromLotLearned,
            isAutomotive: isAutomotive,
            meterID: (isAutomotive && meter != nil) ? meter?.meterID : nil,
            meterStreet: (isAutomotive && meter != nil) ? meter?.street : nil,
            meterMatchKind: (isAutomotive && meter != nil) ? meter?.kind : nil
        )
        
        if let idx = findLotIndex(near: coordinate, radiusMeters: Self.defaultRadiusMeters,
                                  floorIndex: manualFloorIndex ?? predictedFloorIndex) {
            var lot = lots[idx]
            let dup = lot.points.first { p in
                abs(p.createdAt.timeIntervalSince(createdAt)) < 30 &&
                CLLocation(latitude: p.latitude, longitude: p.longitude).distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) < 10
            }
            if let dup {
                if dup.isAutomotive { barometer.bindActiveCapture(pointID: dup.id, arrival: dup.createdAt, coordinate: dup.coordinate) }
                return
            }
            lot.points.insert(inserting, at: 0)
            lot.updatedAt = now
            lots[idx] = lot
            activeLotID = lot.id
        } else {
            let lot = ParkingLotRecord(
                id: UUID(),
                name: (defaultLotName?.isEmpty == false) ? defaultLotName : nil,  // 周邊預設名（POI／街道／地區）
                centerLatitude: coordinate.latitude,
                centerLongitude: coordinate.longitude,
                radiusMeters: Self.defaultRadiusMeters,
                createdAt: now,
                updatedAt: now,
                locality: nil,  // 稍後由反向地理編碼填充
                points: [inserting],
                learnedMetersPerFloor: nil,
                learnedOffsetMeters: nil,
                learnedConfidence: nil,
                floorLearningHistory: nil
            )
            lots.insert(lot, at: 0)
            activeLotID = lot.id
        }
        
        persist()
        if isAutomotive {
            barometer.bindActiveCapture(pointID: inserting.id, arrival: createdAt, coordinate: coordinate)
        }
        let loadedLots = lots
        DispatchQueue.main.async {
            TripPredictor.shared.reconcilePlaceNames(with: loadedLots)
        }
    }
    
    func setManualFloor(pointID: UUID, floorIndex: Int?, learnFromAltitude: Bool = true,
                        persistChanges: Bool = true) {
        var changed = false
        for i in lots.indices {
            if let pIndex = lots[i].points.firstIndex(where: { $0.id == pointID }) {
                let before = lots[i].points[pIndex].manualFloorIndex
                lots[i].points[pIndex].manualFloorIndex = floorIndex
                lots[i].points[pIndex].floorConfirmedByUser = floorIndex != nil
                if floorMode == .fixed {
                    lots[i].fixedFloorIndex = floorIndex ?? lots[i].points.filter { $0.manualFloorIndex != nil }
                        .max(by: { $0.createdAt < $1.createdAt })?.manualFloorIndex
                }
                // 手動調樓層就清走舊嘅樓層文字（識別／編輯留低嘅），
                // 等 displayFloor 用返指數顯示 —— 唔係嘅話 +/- 會被舊文字遮住（「點撳都調唔到」）
                lots[i].points[pIndex].llmFloorText = nil
                lots[i].updatedAt = Date()
                changed = true
                
                if floorIndex != before, learnFromAltitude,
                   let newIdx = floorIndex,
                   let delta = lots[i].points[pIndex].barometerAltitudeDeltaMeters {
                    applyFloorLearning(
                        lotIndex: i,
                        pointID: pointID,
                        manualFloorIndex: newIdx,
                        altitudeDeltaMeters: delta
                    )
                }
                
                // Corrections belong to this visit; never rewrite other visits' estimated floors.
                if floorIndex == nil {
                    lots[i].floorLearningHistory?.removeAll { $0.pointID == pointID }
                    rebuildLotLearning(at: i)
                }
                
                break
            }
        }
        if changed && persistChanges {
            persist()
        }
    }

    /// An untouched estimate is not human confirmation or training evidence.
    func acceptPredictedFloorAtDeparture() {}
    
    private func applyFloorLearning(
        lotIndex: Int,
        pointID: UUID,
        manualFloorIndex: Int,
        altitudeDeltaMeters: Double
    ) {
        let lotID = lots[lotIndex].id
        let delta = altitudeDeltaMeters
        let floorIdx = manualFloorIndex
        let reference = lots[lotIndex].points.first(where: { $0.id == pointID })?.barometerReferenceFloorIndex ?? 0
        let travelled = floorIdx - reference
        let metersPerFloor = travelled == 0 ? 0 : (delta / Double(travelled))
        
        let learning = ParkingLotFloorLearning(
            createdAt: Date(),
            manualFloorIndex: manualFloorIndex,
            altitudeDeltaMeters: delta,
            metersPerFloor: metersPerFloor,
            lotID: lotID,
            pointID: pointID,
            referenceFloorIndex: reference
        )
        if lots[lotIndex].floorLearningHistory == nil {
            lots[lotIndex].floorLearningHistory = []
        }
        lots[lotIndex].floorLearningHistory!.removeAll { $0.pointID == pointID }
        lots[lotIndex].floorLearningHistory!.append(learning)
        
        rebuildLotLearning(at: lotIndex)
    }

    /// 從測試頁手動學習每層樓高度
    func learnMetersPerFloor(near coordinate: CLLocationCoordinate2D, metersPerFloor: Double, offset: Double) {
        // 搵到對應嘅停車場
        let lotIdx = findLotIndex(near: coordinate, radiusMeters: 180)
        guard let lotIndex = lotIdx else {
            // 如果搵唔到停車場，建立一個新嘅
            let newLot = ParkingLotRecord(
                id: UUID(),
                name: nil,
                centerLatitude: coordinate.latitude,
                centerLongitude: coordinate.longitude,
                radiusMeters: 50,
                createdAt: Date(),
                updatedAt: Date(),
                points: [],
                learnedMetersPerFloor: metersPerFloor,
                learnedOffsetMeters: offset,
                learnedConfidence: 0.5,
                floorLearningHistory: nil
            )
            lots.append(newLot)
            persist()
            return
        }

        // 更新學習數據
        lots[lotIndex].learnedMetersPerFloor = metersPerFloor
        lots[lotIndex].learnedOffsetMeters = offset
        lots[lotIndex].updatedAt = Date()
        persist()
    }

    
    private func predictFloor(
        near coordinate: CLLocationCoordinate2D,
        createdAt: Date,
        altitudeDelta: Double?,
        sampleCount: Int?,
        referenceAlt: Double?,
        finalAlt: Double?,
        pressure: Double?,
        referenceFloor: Int = 0
    ) -> (floorIndex: Int?, confidence: Double?, fromLotLearned: Bool) {
        let lotIdx = findLotIndex(near: coordinate, radiusMeters: Self.defaultRadiusMeters)
        let mpF: Double
        let offset: Double
        let lotConf: Double
        let fromLearned: Bool
        if let idx = lotIdx, let learned = lots[idx].learnedMetersPerFloor {
            mpF = learned
            offset = lots[idx].learnedOffsetMeters ?? 0.0
            lotConf = lots[idx].learnedConfidence ?? 0.0
            fromLearned = true
        } else {
            mpF = Self.defaultMetersPerFloor
            offset = 0.0
            lotConf = 0.0
            fromLearned = false
        }
        guard let delta = altitudeDelta, let samples = sampleCount else {
            return (nil, nil, fromLearned)
        }
        if floorMode == .fixed, let lotIdx {
            let fixed = lots[lotIdx].fixedFloorIndex
                ?? lots[lotIdx].points.filter { $0.manualFloorIndex != nil }
                    .max(by: { $0.createdAt < $1.createdAt })?.manualFloorIndex
            if let fixed { return (fixed, 0.5, true) }
        }
        let adjustedDelta = delta - offset  // 可負數（入地庫）
        let raw = (adjustedDelta / mpF).rounded(.toNearestOrAwayFromZero)
        var predicted = Int(raw) + referenceFloor
        if predicted < -10 { predicted = -10 }  // 最多地下 10 層
        if predicted > 30 { predicted = 30 }
        
        let sampleFactor: Double = samples >= 40 ? 1.0 : (Double(samples) / 40.0)
        let learnedFactor: Double = fromLearned ? 1.0 : 0.35
        var conf: Double = 0.15 + 0.85 * (0.55 * lotConf + 0.25 * sampleFactor + 0.2 * learnedFactor)
        if abs((Double(predicted) * mpF) - adjustedDelta) > mpF * 0.5 {
            conf *= 0.7
        }
        conf = max(0.1, min(0.98, conf))
        
        return (predicted, conf, fromLearned)
    }

    func estimatedFloor(near coordinate: CLLocationCoordinate2D, delta: Double, referenceFloor: Int = 0) -> Int {
        predictFloor(near: coordinate, createdAt: Date(), altitudeDelta: delta, sampleCount: 40,
                     referenceAlt: nil, finalAlt: nil, pressure: nil, referenceFloor: referenceFloor).floorIndex
            ?? referenceFloor
    }

    func setPointCoordinate(pointID: UUID, coordinate: CLLocationCoordinate2D) {
        for i in lots.indices {
            if let pIndex = lots[i].points.firstIndex(where: { $0.id == pointID }) {
                lots[i].points[pIndex].latitude = coordinate.latitude
                lots[i].points[pIndex].longitude = coordinate.longitude
                lots[i].updatedAt = Date()
                recomputeLotGeometry(at: i)
                objectWillChange.send()
                persist()
                return
            }
        }
    }

    func removeMeterAnnotation(pointID: UUID) {
        for lotIndex in lots.indices {
            guard let pointIndex = lots[lotIndex].points.firstIndex(where: { $0.id == pointID }) else { continue }
            lots[lotIndex].points[pointIndex].removeMeterAnnotation()
            lots[lotIndex].updatedAt = Date()
            persist()
            return
        }
    }

    func lot(containing pointID: UUID) -> ParkingLotRecord? {
        lots.first { lot in lot.points.contains(where: { $0.id == pointID }) }
    }

    @discardableResult
    func setBoundary(lotID: UUID, vertices: [ParkingBoundaryVertex]?) -> Bool {
        guard let i = lots.firstIndex(where: { $0.id == lotID }),
              vertices.map(ParkingBoundaryGeometry.isValid) ?? true else { return false }
        lots[i].boundaryVertices = vertices
        recomputeLotGeometry(at: i)
        lots[i].updatedAt = Date()
        persist()
        return true
    }

    @discardableResult
    func mergeLot(_ sourceID: UUID, into targetID: UUID) -> Bool {
        guard sourceID != targetID, let source = lots.first(where: { $0.id == sourceID }),
              let ti = lots.firstIndex(where: { $0.id == targetID }) else { return false }
        let existingIDs = Set(lots[ti].points.map(\.id))
        let moving = source.points.filter { !existingIDs.contains($0.id) }.map { point in
            var p = point
            p.lotAssignedByUser = true
            return p
        }
        lots[ti].points.append(contentsOf: moving)
        let movingIDs = Set(moving.map(\.id))
        var history = lots[ti].floorLearningHistory ?? []
        history.append(contentsOf: (source.floorLearningHistory ?? []).filter { movingIDs.contains($0.pointID) }.map {
            var learning = $0; learning.lotID = targetID; return learning
        })
        lots[ti].floorLearningHistory = history
        var names = lots[ti].floorNames ?? [:]
        for (floor, name) in source.floorNames ?? [:] where names[floor] == nil { names[floor] = name }
        lots[ti].floorNames = names
        if lots[ti].floorScopeIndex != source.floorScopeIndex { lots[ti].floorScopeIndex = nil }
        if activeLotID == sourceID { activeLotID = targetID }
        lots.removeAll { $0.id == sourceID }
        guard let i = lots.firstIndex(where: { $0.id == targetID }) else { return false }
        recomputeLotGeometry(at: i)
        rebuildLotLearning(at: i)
        lots[i].updatedAt = Date()
        persist()
        let saved = lots
        DispatchQueue.main.async { TripPredictor.shared.reconcilePlaceNames(with: saved) }
        return true
    }

    @discardableResult
    func movePoint(_ pointID: UUID, toLotID destinationID: UUID, manuallyAssigned: Bool = true) -> Bool {
        guard let sourceIndex = lots.firstIndex(where: { lot in
            lot.points.contains(where: { $0.id == pointID })
        }), lots[sourceIndex].id != destinationID,
              lots.contains(where: { $0.id == destinationID }),
              let pointIndex = lots[sourceIndex].points.firstIndex(where: { $0.id == pointID }) else {
            return false
        }

        let sourceID = lots[sourceIndex].id
        var point = lots[sourceIndex].points.remove(at: pointIndex)
        if manuallyAssigned { point.lotAssignedByUser = true }
        let movedLearning = (lots[sourceIndex].floorLearningHistory ?? []).filter { $0.pointID == pointID }
        lots[sourceIndex].floorLearningHistory?.removeAll { $0.pointID == pointID }

        if lots[sourceIndex].points.isEmpty {
            lots.remove(at: sourceIndex)
        } else if let updatedSource = lots.firstIndex(where: { $0.id == sourceID }) {
            recomputeLotGeometry(at: updatedSource)
            rebuildLotLearning(at: updatedSource)
        }

        guard let destinationIndex = lots.firstIndex(where: { $0.id == destinationID }) else {
            return false
        }
        lots[destinationIndex].points.insert(point, at: 0)
        if !movedLearning.isEmpty {
            if lots[destinationIndex].floorLearningHistory == nil {
                lots[destinationIndex].floorLearningHistory = []
            }
            lots[destinationIndex].floorLearningHistory?.append(contentsOf: movedLearning.map {
                var learning = $0
                learning.lotID = destinationID
                return learning
            })
        }
        lots[destinationIndex].updatedAt = Date()
        recomputeLotGeometry(at: destinationIndex)
        rebuildLotLearning(at: destinationIndex)
        if activeLotID == sourceID { activeLotID = destinationID }
        objectWillChange.send()
        persist()
        return true
    }

    @discardableResult
    func createLot(name: String, moving pointID: UUID) -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let sourceIndex = lots.firstIndex(where: { lot in
                  lot.points.contains(where: { $0.id == pointID })
              }),
              let point = lots[sourceIndex].points.first(where: { $0.id == pointID }) else {
            return nil
        }
        let sourceLocality = lots[sourceIndex].locality
        let newID = UUID()
        lots.append(ParkingLotRecord(
            id: newID,
            name: trimmed,
            centerLatitude: point.latitude,
            centerLongitude: point.longitude,
            radiusMeters: 25,
            createdAt: Date(),
            updatedAt: Date(),
            locality: sourceLocality,
            points: [],
            learnedMetersPerFloor: nil,
            learnedOffsetMeters: nil,
            learnedConfidence: nil,
            floorLearningHistory: nil,
            floorScopeIndex: floorMode == .perVisit ? point.manualFloorIndex : nil
        ))
        guard movePoint(pointID, toLotID: newID) else {
            lots.removeAll { $0.id == newID }
            return nil
        }
        return newID
    }

    func setLotName(lotID: UUID, name: String?) {
        guard let idx = lots.firstIndex(where: { $0.id == lotID }) else { return }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let newName = trimmed?.isEmpty == true ? nil : trimmed
        lots[idx].name = newName
        lots[idx].updatedAt = Date()
        persist()
        let lot = lots[idx]
        DispatchQueue.main.async {
            // 同步 placeCatalog 中嘅 lot: 記錄
            if let n = newName {
                TripPredictor.shared.renameLotPlace(lotID: lotID, newName: n)
            }
            // 同步 placeCatalog 中嘅 addr: 記錄（同一位置嘅地址叢集）
            TripPredictor.shared.syncClusterName(
                nearLatitude: lot.centerLatitude,
                longitude: lot.centerLongitude,
                newName: newName
            )
        }
    }

    /// 更新停車場嘅城市信息
    func setLotLocality(lotID: UUID, locality: String) {
        guard let idx = lots.firstIndex(where: { $0.id == lotID }) else { return }
        guard lots[idx].locality == nil || lots[idx].locality?.isEmpty == true else { return }
        lots[idx].locality = locality
        persist()
    }

    /// 為所有冇城市信息嘅停車場批量更新
    func updateMissingLocalities(currentLocality: String) {
        guard !currentLocality.isEmpty else { return }
        var changed = false
        for i in 0..<lots.count {
            if lots[i].locality == nil || lots[i].locality?.isEmpty == true {
                lots[i].locality = currentLocality
                changed = true
            }
        }
        if changed { persist() }
    }

    /// 同步停車場名稱：搵到同一位置嘅 lot 並更新名稱（由地址叢集改名觸發）
    func syncLotName(near coordinate: CLLocationCoordinate2D, newName: String) {
        if let idx = findLotIndex(near: coordinate, radiusMeters: 180) {
            lots[idx].name = newName
            lots[idx].updatedAt = Date()
            persist()
        }
    }

    /// 刪除指定停車點（soft delete：搬入「最近刪除」，7 日內可還原）
    func deletePoint(pointID: UUID) {
        for lotIndex in lots.indices {
            if let pIndex = lots[lotIndex].points.firstIndex(where: { $0.id == pointID }) {
                let lot = lots[lotIndex]
                let point = lot.points[pIndex]
                deletedPoints.removeAll { $0.point.id == point.id }
                deletedPoints.append(DeletedPointEntry(
                    batchID: UUID(), point: point,
                    lotName: lot.preferredDisplayName, deletedAt: Date()
                ))
                lots[lotIndex].points.remove(at: pIndex)
                lots[lotIndex].updatedAt = Date()
                // 如果刪除後該停車場無點，則刪除整個停車場
                if lots[lotIndex].points.isEmpty {
                    lots.remove(at: lotIndex)
                } else {
                    recomputeLotGeometry(at: lotIndex)
                    rebuildLotLearning(at: lotIndex)
                }
                objectWillChange.send()
                persistTrash()
                persist()
                return
            }
        }
    }

    /// 刪除整個停車場（soft delete：入面每個點都入「最近刪除」，同一 batch 可一齊還原）
    func deleteLot(lotID: UUID) {
        guard let idx = lots.firstIndex(where: { $0.id == lotID }) else { return }
        let lot = lots[idx]
        let batch = UUID()
        let now = Date()
        let name = lot.preferredDisplayName
        for point in lot.points {
            deletedPoints.removeAll { $0.point.id == point.id }
        }
        deletedPoints.append(contentsOf: lot.points.map {
            DeletedPointEntry(batchID: batch, point: $0, lotName: name, deletedAt: now)
        })
        lots.removeAll { $0.id == lotID }
        objectWillChange.send()
        persistTrash()
        persist()
    }

    /// 還原「最近刪除」入面嘅一條停車點。
    /// 名一樣 → 合併入附近現有 lot；名唔一樣（或者附近冇 lot）→ 獨立成返一個 lot。
    func restorePoint(entryID: UUID) {
        guard let entryIdx = deletedPoints.firstIndex(where: { $0.id == entryID }) else { return }
        let entry = deletedPoints[entryIdx]
        let coord = entry.point.coordinate
        let nameKey = Self.normalizedLotName(entry.lotName)
        if let targetIdx = lots.firstIndex(where: {
            Self.normalizedLotName($0.preferredDisplayName) == nameKey
                && $0.centerDistance(to: coord) <= Self.defaultRadiusMeters
        }) {
            var lot = lots[targetIdx]
            if !lot.points.contains(where: { $0.id == entry.point.id }) {
                lot.points.insert(entry.point, at: 0)
                lot.updatedAt = Date()
                lots[targetIdx] = lot
                recomputeLotGeometry(at: targetIdx)
                rebuildLotLearning(at: targetIdx)
            }
        } else {
            lots.insert(ParkingLotRecord(
                id: UUID(), name: entry.lotName,
                centerLatitude: coord.latitude, centerLongitude: coord.longitude,
                radiusMeters: Self.defaultRadiusMeters,
                createdAt: entry.point.createdAt, updatedAt: Date(), locality: nil,
                points: [entry.point],
                learnedMetersPerFloor: nil, learnedOffsetMeters: nil,
                learnedConfidence: nil, floorLearningHistory: nil
            ), at: 0)
        }
        deletedPoints.remove(at: entryIdx)
        objectWillChange.send()
        persistTrash()
        persist()
    }

    /// 成批還原（成個 lot 刪除嗰批，逐條放返入同一個 lot）
    func restoreBatch(batchID: UUID) {
        let ids = deletedPoints.filter { $0.batchID == batchID }.map(\.id)
        for id in ids { restorePoint(entryID: id) }
    }

    /// 永久刪除（回收桶入面嘅停車點）
    func permanentlyDeletePoint(entryID: UUID) {
        deletedPoints.removeAll { $0.id == entryID }
        persistTrash()
    }

    /// 刪除學習地點（soft delete：移出 placeCatalog，入「最近刪除」）
    func deletePlace(_ place: PlaceInfo) {
        deletedPlaces.removeAll { $0.place.key == place.key }
        deletedPlaces.append(DeletedPlaceEntry(place: place, deletedAt: Date()))
        DispatchQueue.main.async {
            TripPredictor.shared.removePlace(key: place.key)
        }
        persistTrash()
    }

    /// 還原學習地點（放返入 placeCatalog，key／預測記錄引用跟返）
    func restorePlace(entryID: String) {
        guard let idx = deletedPlaces.firstIndex(where: { $0.id == entryID }) else { return }
        let place = deletedPlaces[idx].place
        DispatchQueue.main.async {
            TripPredictor.shared.restorePlace(place)
        }
        deletedPlaces.remove(at: idx)
        persistTrash()
    }

    /// 永久刪除（回收桶入面嘅學習地點）
    func permanentlyDeletePlace(entryID: String) {
        deletedPlaces.removeAll { $0.id == entryID }
        persistTrash()
    }

    /// 清理過期（7 日）嘅回收記錄
    func purgeExpiredTrash() {
        let cutoff = Date().addingTimeInterval(-Self.trashRetention)
        let hadExpired = deletedPoints.contains { $0.deletedAt < cutoff }
            || deletedPlaces.contains { $0.deletedAt < cutoff }
        guard hadExpired else { return }
        deletedPoints.removeAll { $0.deletedAt < cutoff }
        deletedPlaces.removeAll { $0.deletedAt < cutoff }
        persistTrash()
    }

    private static func normalizedLotName(_ name: String?) -> String {
        (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func persistTrash() {
        if let data = try? JSONEncoder().encode(deletedPoints) {
            defaults.set(data, forKey: deletedPointsKey)
        }
        if let data = try? JSONEncoder().encode(deletedPlaces) {
            defaults.set(data, forKey: deletedPlacesKey)
        }
    }

    private func loadTrash() {
        if let data = defaults.data(forKey: deletedPointsKey),
           let entries = try? JSONDecoder().decode([DeletedPointEntry].self, from: data) {
            deletedPoints = entries
        }
        if let data = defaults.data(forKey: deletedPlacesKey),
           let entries = try? JSONDecoder().decode([DeletedPlaceEntry].self, from: data) {
            deletedPlaces = entries
        }
        purgeExpiredTrash()
    }

    func nudgePoint(pointID: UUID, northMeters: Double, eastMeters: Double) {
        guard northMeters != 0 || eastMeters != 0 else { return }
        for lotIndex in lots.indices {
            guard let pIndex = lots[lotIndex].points.firstIndex(where: { $0.id == pointID }) else { continue }
            let lat = lots[lotIndex].points[pIndex].latitude
            let lon = lots[lotIndex].points[pIndex].longitude
            let latRad = lat * Double.pi / 180
            let dLat = northMeters / 111_000.0
            let dLon = eastMeters / (111_000.0 * max(0.2, cos(latRad)))
            let newCoord = CLLocationCoordinate2D(latitude: lat + dLat, longitude: lon + dLon)
            lots[lotIndex].points[pIndex].latitude = newCoord.latitude
            lots[lotIndex].points[pIndex].longitude = newCoord.longitude
            lots[lotIndex].updatedAt = Date()
            recomputeLotGeometry(at: lotIndex)
            objectWillChange.send()
            persist()
            break
        }
    }
    
    func findLotIndex(near coordinate: CLLocationCoordinate2D, radiusMeters: Double, floorIndex: Int? = nil) -> Int? {
        let loc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let candidates = lots.enumerated().compactMap { idx, lot -> (index: Int, distance: Double, floorMatch: Bool, customBoundary: Bool)? in
            let c = CLLocation(latitude: lot.centerLatitude, longitude: lot.centerLongitude)
            let distance = c.distance(from: loc)
            let hasCustomBoundary = lot.boundaryVertices.map(ParkingBoundaryGeometry.isValid) ?? false
            if hasCustomBoundary, let vertices = lot.boundaryVertices {
                guard ParkingBoundaryGeometry.contains(coordinate, vertices: vertices) else { return nil }
            } else {
                guard distance <= min(radiusMeters, lot.radiusMeters) else { return nil }
            }
            if floorMode == .perVisit, let floorIndex, let scope = lot.floorScopeIndex, scope != floorIndex {
                return nil
            }
            return (idx, distance, floorIndex != nil && lot.floorScopeIndex == floorIndex, hasCustomBoundary)
        }
        if floorMode == .perVisit, floorIndex == nil,
           candidates.filter({ lots[$0.index].floorScopeIndex != nil }).count > 1 {
            return candidates.filter { lots[$0.index].floorScopeIndex == nil }
                .min(by: { $0.distance < $1.distance })?.index
        }
        return candidates.min {
            if floorMode == .perVisit, $0.floorMatch != $1.floorMatch { return $0.floorMatch }
            if $0.customBoundary != $1.customBoundary { return $0.customBoundary }
            return $0.distance < $1.distance
        }?.index
    }

    private func recomputeLotGeometry(at index: Int) {
        guard lots.indices.contains(index) else { return }
        if let vertices = lots[index].boundaryVertices, ParkingBoundaryGeometry.isValid(vertices) {
            let latitude = vertices.map(\.latitude).reduce(0, +) / Double(vertices.count)
            let longitude = vertices.map(\.longitude).reduce(0, +) / Double(vertices.count)
            let center = CLLocation(latitude: latitude, longitude: longitude)
            lots[index].centerLatitude = latitude
            lots[index].centerLongitude = longitude
            lots[index].radiusMeters = vertices.map {
                center.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
            }.max() ?? 25
            return
        }
        guard !lots[index].points.isEmpty else { return }
        let points = lots[index].points
        let latitude = points.reduce(0.0) { $0 + $1.latitude } / Double(points.count)
        let longitude = points.reduce(0.0) { $0 + $1.longitude } / Double(points.count)
        let center = CLLocation(latitude: latitude, longitude: longitude)
        let farthest = points.map {
            center.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
        }.max() ?? 0
        lots[index].centerLatitude = latitude
        lots[index].centerLongitude = longitude
        lots[index].radiusMeters = min(Self.defaultRadiusMeters, max(25, farthest + 25))
        lots[index].updatedAt = Date()
    }

    private func rebuildLotLearning(at index: Int) {
        guard lots.indices.contains(index) else { return }
        let pointIDs = Set(lots[index].points.filter(\.isFloorConfirmed).map(\.id))
        lots[index].floorLearningHistory?.removeAll { !pointIDs.contains($0.pointID) }
        guard let calibration = ParkingFloorCalibration.learn(lots[index].floorLearningHistory ?? []) else {
            lots[index].learnedMetersPerFloor = nil
            lots[index].learnedOffsetMeters = nil
            lots[index].learnedConfidence = nil
            return
        }
        lots[index].learnedMetersPerFloor = calibration.metersPerFloor
        lots[index].learnedOffsetMeters = calibration.offset
        lots[index].learnedConfidence = calibration.confidence
    }
    
    // MARK: - 文件備份路徑（Documents/parking_lots_backup.json）
    private var backupFileURL: URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return docs.appendingPathComponent("parking_lots_backup.json")
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(lots)
            // 1. UserDefaults（主存儲）
            defaults.set(data, forKey: storeKey)
            defaults.synchronize()
            // 2. 文件備份（防止異常關機丟失）
            if let url = backupFileURL {
                try data.write(to: url, options: .atomic)
            }
        } catch {
            print("[ParkingFloorStore] persist error: \(error)")
        }
    }

    private func load() {
        var data: Data? = defaults.data(forKey: storeKey)
        var source = "UserDefaults"
        // 如果 UserDefaults 為空，嘗試從文件備份恢復
        if data == nil, let url = backupFileURL, FileManager.default.fileExists(atPath: url.path) {
            data = try? Data(contentsOf: url)
            source = "file backup"
        }
        guard let data else { return }
        guard let decoded = try? JSONDecoder().decode([ParkingLotRecord].self, from: data) else {
            print("[ParkingFloorStore] load decode failed from \(source)")
            return
        }
        print("[ParkingFloorStore] loaded \(decoded.count) lots from \(source)")
        lots = decoded.sorted { $0.updatedAt > $1.updatedAt }
        let loadedLots = lots
        DispatchQueue.main.async {
            TripPredictor.shared.reconcilePlaceNames(with: loadedLots)
        }
        // 如果是從備份恢復的，同步回 UserDefaults
        if source == "file backup" {
            defaults.set(data, forKey: storeKey)
            defaults.synchronize()
        }
    }
    
    /// 當前生效嘅樓層慣例：true = 內地慣例（地面=1樓），false = 香港慣例（地面=G）
    /// 「自動」模式按位置判定（香港/澳門用香港標準，其他用內地標準）：
    /// - 傳入停車點坐標 → 跟停車點所在地（深圳點永遠顯示「內地慣例」）
    /// - 唔傳 → 跟當前位置
    static func isMainlandConventionActive(for coordinate: CLLocationCoordinate2D? = nil) -> Bool {
        // 未設定過就當「自動」（=2，同設定頁 @AppStorage 默認值一致）。
        // 注意 integer(forKey:) 對唔存在嘅 key 會返 0（=香港）——
        // 以前就係咁，設定頁顯示「自動」但實際行緊「香港」，深圳點都標住「香港慣例」。
        let convention = (UserDefaults.standard.object(forKey: "floorConvention") as? Int) ?? 2
        if convention == 2 {
            return !isHongKongRegion(coordinate)
        }
        return convention == 1
    }

    /// 慣例名稱（樓層顯示隔離嘅標註用）
    static func conventionLabel(for coordinate: CLLocationCoordinate2D? = nil) -> String {
        isMainlandConventionActive(for: coordinate) ? String(localized: "內地慣例") : String(localized: "香港慣例")
    }

    /// 樓層文字正規化：「地面1」「1/F」「1層」→「1」；「地面」→「G」/「1」。
    /// 解析唔到就原樣返回（只去首尾空格）。存資料同顯示前都過一次，
    /// 等 VLM／手輸殘留（「地面」等雜字）唔會跟住落地圖標籤。
    static func cleanFloorText(_ text: String?, coordinate: CLLocationCoordinate2D? = nil) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if let idx = parseFloorIndex(trimmed, coordinate: coordinate) {
            return formatFloor(idx, coordinate: coordinate)
        }
        return trimmed
    }

    static func formatFloor(_ idx: Int, coordinate: CLLocationCoordinate2D? = nil) -> String {
        let useMainland = isMainlandConventionActive(for: coordinate)

        if useMainland {
            // 內地：地面=1樓，B1=-1→B1，0→1，1→2
            if idx < 0 { return "B\(abs(idx))" }
            return "\(idx + 1)"
        } else {
            // 香港：地面=G，B1=-1→B1，0→G，1→1
            if idx == 0 { return "G" }
            if idx < 0 { return "B\(abs(idx))" }
            return "\(idx)"
        }
    }

    /// 判斷位置是否在香港/澳門圖框（自動偵測樓層慣例用）
    /// 傳入坐標就判斷嗰個點；唔傳就判斷當前位置（UserDefaults 緩存經緯度）
    private static func isHongKongRegion(_ coordinate: CLLocationCoordinate2D? = nil) -> Bool {
        if let coordinate {
            return !MapRegionJudge.isMainland(coordinate)
        }
        let lat = UserDefaults.standard.double(forKey: "lastKnownLatitude")
        let lon = UserDefaults.standard.double(forKey: "lastKnownLongitude")
        if lat == 0 && lon == 0 { return true }  // 未有定位：預設香港
        return !MapRegionJudge.isMainland(CLLocationCoordinate2D(latitude: lat, longitude: lon))
    }

    /// 將「牌面樓層文字」解析成內部樓層指數（0=地面，負數=地庫），按當前樓層慣例換算：
    /// 內地牌面「3」= 內部 2（地面係 1 樓）；香港牌面「3」= 內部 3（地面係 G）。
    /// 地庫「B2」／「地下2層」兩地一致 → -2。
    static func parseFloorIndex(_ text: String, coordinate: CLLocationCoordinate2D? = nil) -> Int? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if trimmed.isEmpty { return nil }
        // 「地面」「地面1」「地面1層」：先剝走「地面」前綴再解析
        // （VLM 對地面層成日答「地面1」，原樣存落去地圖標籤會變「地面1/F」）
        if trimmed.hasPrefix("地面") {
            trimmed = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return 0 }
        }
        // 地面：G / GF / LG / 地下
        if trimmed == "G" || trimmed == "GF" || trimmed == "LG" || trimmed == "地下" { return 0 }
        // 地庫：B2 / B 2 → -2
        if trimmed.hasPrefix("B"), let num = Int(trimmed.dropFirst().trimmingCharacters(in: .whitespaces)) {
            return -num
        }
        // 「地下2層/层」→ -2
        if let regex = try? NSRegularExpression(pattern: "^地下(\\d+)[層层]$"),
           let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)),
           let range = Range(match.range(at: 1), in: trimmed),
           let num = Int(trimmed[range]) {
            return -num
        }
        // 「-2樓/楼」或「-2」→ -2
        if trimmed.hasPrefix("-") {
            let rest = trimmed.dropFirst()
            let digits = rest.prefix(while: { $0.isNumber })
            if let num = Int(digits), num > 0 { return -num }
            return nil
        }
        // 「3樓/楼」或純數字「3」→ 牌面數字按慣例換算成內部指數
        let digits = trimmed.prefix(while: { $0.isNumber })
        guard let num = Int(digits), num > 0 else { return nil }
        return isMainlandConventionActive(for: coordinate) ? num - 1 : num
    }
}

/// 樓層慣例標註小膠囊：標明樓層數值跟「香港慣例」定「內地慣例」
/// （自動模式跟停車點所在地判定，冇坐標就跟當前位置）。可放喺任何樓層顯示隔離。
struct FloorConventionBadge: View {
    /// 關聯停車點坐標（慣例跟點所在地判定）
    var coordinate: CLLocationCoordinate2D? = nil
    /// 深色背景（泊車記憶／確認卡等黑底）用淺色文字
    var onDark: Bool = false
    /// 極細版（空間窄嘅行內用）
    var compact: Bool = false

    var body: some View {
        Text(ParkingFloorStore.conventionLabel(for: coordinate))
            .font(.system(size: compact ? 8 : 9, weight: .semibold))
            .foregroundStyle(onDark ? Color.white.opacity(0.6) : Color.secondary)
            .padding(.horizontal, compact ? 5 : 6)
            .padding(.vertical, compact ? 2 : 3)
            .background(
                Capsule().fill(onDark ? Color.white.opacity(0.15) : Color.secondary.opacity(0.15))
            )
    }
}

struct BarometerSample: Hashable, Codable {
    let timestamp: Date
    let relativeAltitude: Double
    let pressure: Double
    /// 採樣時的車速 (km/h)，-1 表示未知
    let speedKmh: Double
}

/// Time-based decisions only advance on new sensor events, never timer polls.
struct ParkingAltitudeCapture {
    private(set) var samples: [BarometerSample] = []
    private(set) var stationarySince: Date?
    private var initialAltitudes: [Double] = []
    private(set) var referenceAltitude: Double?

    mutating func append(_ sample: BarometerSample, stationaryEvidence: Bool = false) -> Bool {
        guard sample.relativeAltitude.isFinite, sample.pressure.isFinite,
              samples.last.map({ sample.timestamp > $0.timestamp }) ?? true else { return false }
        if let last = samples.last, sample.timestamp.timeIntervalSince(last.timestamp) > 2.5 {
            stationarySince = nil
        }
        samples.append(sample)
        if samples.count > 900 { samples.removeFirst(samples.count - 900) }
        if initialAltitudes.count < 3 {
            initialAltitudes.append(sample.relativeAltitude)
            referenceAltitude = initialAltitudes.sorted()[initialAltitudes.count / 2]
        }
        let stopped = (sample.speedKmh >= 0 && sample.speedKmh <= 0.5)
            || (sample.speedKmh < 0 && stationaryEvidence)
        guard stopped else { stationarySince = nil; return false }
        if stationarySince == nil { stationarySince = sample.timestamp }
        guard let since = stationarySince, sample.timestamp.timeIntervalSince(since) >= 10 else { return false }
        let stable = samples.filter { $0.timestamp >= sample.timestamp.addingTimeInterval(-8) }
        guard stable.count >= 5, let first = stable.first,
              sample.timestamp.timeIntervalSince(first.timestamp) >= 7,
              let lo = stable.map(\.relativeAltitude).min(),
              let hi = stable.map(\.relativeAltitude).max() else { return false }
        return hi - lo <= 0.5
    }

    var finalAltitude: Double? {
        let tail = samples.suffix(5).map(\.relativeAltitude).sorted()
        return tail.isEmpty ? nil : tail[tail.count / 2]
    }

    func resumedAfterBriefStop(speed: Double, at date: Date) -> Bool {
        guard speed > 2, let since = stationarySince else { return false }
        let elapsed = date.timeIntervalSince(since)
        return elapsed >= 1
    }
}

/// Asking about a stable stop never ends the sensor session.
struct ParkingStopConfirmation {
    private(set) var promptID: UUID?
    private(set) var nextPromptAt: Date?

    mutating func update(stableStop: Bool, isStopped: Bool = true, at date: Date) {
        guard isStopped else { reset(); return }
        guard stableStop else { promptID = nil; return }
        if nextPromptAt.map({ date >= $0 }) ?? true {
            promptID = UUID()
            nextPromptAt = date.addingTimeInterval(10)
        }
    }

    mutating func deferPrompt(at date: Date) {
        promptID = nil
        nextPromptAt = date.addingTimeInterval(10)
    }

    mutating func reset() {
        promptID = nil
        nextPromptAt = nil
    }
}

struct ParkingAltitudeResult: Codable, Identifiable, Equatable {
    var id: UUID
    var startedAt: Date
    var stoppedAt: Date
    var arrivalDate: Date
    var latitude: Double?
    var longitude: Double?
    var referenceAltitude: Double
    var finalAltitude: Double
    var pressure: Double?
    var sampleCount: Int
    var selectedFloor: Int?
    var userConfirmed = false
    var pointID: UUID?
    var hasSamplingGap: Bool?
    var referenceFloorIndex: Int?
    var deltaMeters: Double { finalAltitude - referenceAltitude }

    mutating func selectFloor(_ floor: Int, confirmedByUser: Bool) {
        selectedFloor = max(-10, min(30, floor))
        userConfirmed = userConfirmed || confirmedByUser
    }

    func matches(arrival: Date, coordinate: CLLocationCoordinate2D) -> Bool {
        // A visit can be reported while sampling continues for several minutes at a gate.
        if pointID != nil {
            guard abs(arrival.timeIntervalSince(arrivalDate)) < 1 else { return false }
        } else {
            guard arrival >= startedAt.addingTimeInterval(-120),
                  arrival <= stoppedAt.addingTimeInterval(120) else { return false }
        }
        guard let latitude, let longitude else { return false }
        return CLLocation(latitude: latitude, longitude: longitude).distance(
            from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        ) < 200
    }
}

final class BarometerSessionManager: NSObject, ObservableObject {
    private let altimeter = CMAltimeter()
    private let queue = OperationQueue()
    @Published private(set) var samples: [BarometerSample] = []
    @Published private(set) var isUpdating = false
    @Published private(set) var captureID: UUID?
    @Published private(set) var completedResult: ParkingAltitudeResult?
    @Published private(set) var gatePassUntil: Date?
    @Published private(set) var stopConfirmationID: UUID?
    @Published var referenceFloorIndex = 0
    private var stopConfirmation = ParkingStopConfirmation()
    private var capture = ParkingAltitudeCapture()
    var stationarySince: Date? { capture.stationarySince }
    var captureReferenceAltitude: Double? { capture.referenceAltitude }
    private var startedAt: Date?
    private var capturePointID: UUID?
    private var captureArrivalDate: Date?
    private var lastDrivingTime: Date?
    private var lastCoordinate: CLLocationCoordinate2D?
    private var motionStationary = false
    private var motionAutomotive = false
    private var manualSampling = false
    private var sensorGeneration = UUID()
    private var backgroundObserver: NSObjectProtocol?
    private var results: [ParkingAltitudeResult] = []
    private let resultsKey = "parking_altitude_results_v1"
    private let resultDefaults = UserDefaults(suiteName: "group.com.gorilla.translate") ?? .standard
    /// 當前車速 (km/h)，由 LocationManager 更新；-1 = 未知
    @Published var currentSpeedKmh: Double = -1
    /// 最後一次 GPS 更新速度的時間
    var lastSpeedUpdateTime: Date = Date()

    /// Frozen parking altitude; it is never updated by walking or elevator samples.
    @Published var stationaryAltitude: Double? = nil
    
    var isAvailable: Bool { CMAltimeter.isRelativeAltitudeAvailable() }
    
    var isAuthorized: Bool { CMAltimeter.authorizationStatus() == .authorized }
    
    var authorizationLabel: String {
        switch CMAltimeter.authorizationStatus() {
        case .notDetermined: return "未決定"
        case .restricted: return "限制"
        case .denied: return "拒絕"
        case .authorized: return "已授權"
        @unknown default: return "未知"
        }
    }
    
    override init() {
        super.init()
        queue.maxConcurrentOperationCount = 1
        queue.name = "BarometerSessionManager.queue"
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.suspendCapture() }
    }
    
    deinit {
        if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
        if isUpdating {
            altimeter.stopRelativeAltitudeUpdates()
            isUpdating = false
        }
    }
    
    @discardableResult
    func startIfAuthorized() -> Bool {
        cancelCapture()
        manualSampling = true
        capture = ParkingAltitudeCapture()
        samples = []
        stationaryAltitude = nil
        return startSensor()
    }

    func updateMotion(_ activity: CMMotionActivity?) {
        guard let activity else { return }
        motionStationary = activity.stationary && !activity.walking && !activity.running && !activity.cycling
            && activity.confidence != .low
        motionAutomotive = activity.automotive && !activity.walking && !activity.running
    }

    func updateDriving(speed: Double, timestamp: Date, coordinate: CLLocationCoordinate2D) {
        currentSpeedKmh = speed
        lastSpeedUpdateTime = timestamp
        if CLLocationCoordinate2DIsValid(coordinate) { lastCoordinate = coordinate }
        guard Date().timeIntervalSince(timestamp) <= 5 else { return }
        if speed > 0.5 { resetStopConfirmation() }
        if captureID != nil, capture.resumedAfterBriefStop(speed: speed, at: timestamp),
           gatePassUntil.map({ $0 < timestamp }) ?? true {
            gatePassUntil = Date().addingTimeInterval(3)
        }
        if speed >= 20 { lastDrivingTime = timestamp }
        let resumedDriving = speed >= 8 || (speed > 2 && motionAutomotive)
        if resumedDriving, completedResult != nil {
            // Keep confirmed captures for delayed visits, even after driving resumes.
            completedResult = nil
        }
        guard UIApplication.shared.applicationState == .active, !manualSampling else { return }
        if speed >= 20 {
            if captureID != nil { cancelCapture() }
            return
        }
        guard speed >= 0, !isUpdating, completedResult == nil,
              let lastDrivingTime, timestamp.timeIntervalSince(lastDrivingTime) < 10 * 60 else { return }
        capture = ParkingAltitudeCapture()
        samples = []
        stationaryAltitude = nil
        startedAt = timestamp
        capturePointID = nil
        captureArrivalDate = nil
        referenceFloorIndex = 0
        if startSensor() { captureID = UUID() }
    }

    private func startSensor() -> Bool {
        guard isAvailable else { return false }
        guard isAuthorized || CMAltimeter.authorizationStatus() == .notDetermined else { return false }
        guard !isUpdating else { return true }
        isUpdating = true
        let generation = UUID()
        sensorGeneration = generation
        let startedUptime = ProcessInfo.processInfo.systemUptime
        let startedWallTime = Date()
        altimeter.startRelativeAltitudeUpdates(to: queue) { [weak self] data, _ in
            guard let data else {
                DispatchQueue.main.async {
                    guard let self, self.sensorGeneration == generation else { return }
                    self.cancelCapture()
                }
                return
            }
            let timestamp = startedWallTime.addingTimeInterval(data.timestamp - startedUptime)
            let altitude = data.relativeAltitude.doubleValue
            let pressure = data.pressure.doubleValue
            DispatchQueue.main.async {
                guard let self, self.isUpdating, self.sensorGeneration == generation,
                      UIApplication.shared.applicationState == .active else { return }
                let speedAge = timestamp.timeIntervalSince(self.lastSpeedUpdateTime)
                let speed = speedAge >= -2 && speedAge <= 5 ? self.currentSpeedKmh : -1
                let sample = BarometerSample(timestamp: timestamp, relativeAltitude: altitude,
                                             pressure: pressure, speedKmh: speed)
                let stableStop = self.capture.append(sample, stationaryEvidence: self.motionStationary)
                self.samples = self.capture.samples
                if !self.manualSampling {
                    self.stopConfirmation.update(stableStop: stableStop,
                                                 isStopped: self.capture.stationarySince != nil, at: timestamp)
                    self.publishStopConfirmation()
                }
            }
        }
        return true
    }
    
    func stop() {
        resetStopConfirmation()
        sensorGeneration = UUID()
        if isUpdating {
            altimeter.stopRelativeAltitudeUpdates()
            isUpdating = false
        }
        manualSampling = false
    }

    func clearSamples() {
        resetStopConfirmation()
        samples.removeAll()
        capture = ParkingAltitudeCapture()
        stationaryAltitude = nil
    }

    func cancelCapture() {
        stop()
        captureID = nil
        startedAt = nil
        capturePointID = nil
        captureArrivalDate = nil
    }

    func suspendCapture() {
        cancelCapture()
        lastDrivingTime = nil
        gatePassUntil = nil
    }

    func finishForCarDisconnect() {
        guard isUpdating, captureID != nil, samples.count >= 3,
              let last = samples.last, Date().timeIntervalSince(last.timestamp) < 3 else { return }
        finishCapture()
    }

    @discardableResult
    func confirmParking(captureID: UUID, promptID: UUID) -> Bool {
        guard self.captureID == captureID, stopConfirmationID == promptID, isUpdating,
              samples.count >= 3, let last = samples.last,
              Date().timeIntervalSince(last.timestamp) < 3 else { return false }
        if Date().timeIntervalSince(lastSpeedUpdateTime) <= 5 && currentSpeedKmh > 0.5 { return false }
        finishCapture()
        return completedResult?.id == captureID
    }

    func deferParkingConfirmation(captureID: UUID, promptID: UUID) {
        guard self.captureID == captureID, stopConfirmationID == promptID, isUpdating else { return }
        stopConfirmation.deferPrompt(at: Date())
        publishStopConfirmation()
    }

    private func publishStopConfirmation() {
        if stopConfirmationID != stopConfirmation.promptID { stopConfirmationID = stopConfirmation.promptID }
    }

    private func resetStopConfirmation() {
        stopConfirmation.reset()
        publishStopConfirmation()
    }

    private func finishCapture() {
        guard isUpdating, let id = captureID, let first = samples.first, let last = samples.last,
              let reference = capture.referenceAltitude, let final = capture.finalAltitude else { return }
        stop() // Stop the hardware before publishing a result / showing the floor picker.
        lastDrivingTime = nil
        stationaryAltitude = final
        let result = ParkingAltitudeResult(id: id, startedAt: startedAt ?? first.timestamp,
            stoppedAt: last.timestamp, arrivalDate: captureArrivalDate ?? capture.stationarySince ?? last.timestamp,
            latitude: lastCoordinate?.latitude, longitude: lastCoordinate?.longitude,
            referenceAltitude: reference, finalAltitude: final, pressure: last.pressure,
            sampleCount: samples.count, pointID: capturePointID, referenceFloorIndex: referenceFloorIndex)
        loadResultsIfNeeded()
        results.append(result)
        persistResults()
        completedResult = result
    }

    private var resultsLoaded = false
    private func loadResultsIfNeeded() {
        guard !resultsLoaded, UIApplication.shared.isProtectedDataAvailable else { return }
        if let data = resultDefaults.data(forKey: resultsKey),
           let saved = try? JSONDecoder().decode([ParkingAltitudeResult].self, from: data) { results = saved }
        resultsLoaded = true
    }

    private func persistResults() {
        guard UIApplication.shared.isProtectedDataAvailable else { return }
        results = Array(results.suffix(32))
        if let data = try? JSONEncoder().encode(results) { resultDefaults.set(data, forKey: resultsKey) }
    }

    func result(for arrival: Date, coordinate: CLLocationCoordinate2D) -> ParkingAltitudeResult? {
        loadResultsIfNeeded()
        return results.filter { $0.matches(arrival: arrival, coordinate: coordinate) }
            .min { abs($0.arrivalDate.timeIntervalSince(arrival)) < abs($1.arrivalDate.timeIntervalSince(arrival)) }
    }

    func setFloor(_ floor: Int, userConfirmed: Bool, captureID: UUID) {
        loadResultsIfNeeded()
        guard let index = results.firstIndex(where: { $0.id == captureID }) else { return }
        results[index].selectFloor(floor, confirmedByUser: userConfirmed)
        persistResults()
        if completedResult?.id == captureID { completedResult = results[index] }
    }

    func bindActiveCapture(pointID: UUID, arrival: Date, coordinate: CLLocationCoordinate2D) {
        guard isUpdating, !manualSampling, captureID != nil, let startedAt,
              arrival >= startedAt.addingTimeInterval(-120), arrival <= Date(),
              let lastCoordinate,
              CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude).distance(
                from: CLLocation(latitude: lastCoordinate.latitude, longitude: lastCoordinate.longitude)) < 200 else { return }
        // Prefer the latest visit in this continuous capture, never a previous parking session.
        guard captureArrivalDate.map({ arrival >= $0 }) ?? true else { return }
        capturePointID = pointID
        captureArrivalDate = arrival
    }

    func bindResult(_ resultID: UUID, pointID: UUID, arrival: Date? = nil) {
        guard let index = results.firstIndex(where: { $0.id == resultID }) else { return }
        results[index].pointID = pointID
        if let arrival { results[index].arrivalDate = arrival }
        persistResults()
        if completedResult?.id == resultID { completedResult = results[index] }
    }

    struct WindowResult {
        var sampleCount: Int
        var deltaMeters: Double
        var referenceAlt: Double
        var finalAlt: Double
        var finalPressure: Double?
        /// 預測用到的樣本 index 範圍（對應 self.samples 的 index），供曲線圖標色
        var usedSampleRange: Range<Int>?
        // 原有計算屬性（兼容舊調用）
        var samples: Int { sampleCount }
    }

    /// 低速/靜止樣本的最大車速 (km/h)
    static let stationarySpeedThreshold: Double = 20.0

    /// 移動平均平滑海拔數據，去除氣壓計噪音
    private func smoothAltitudes(_ alts: [Double], windowSize: Int = 5) -> [Double] {
        guard alts.count > 1 else { return alts }
        let half = windowSize / 2
        return alts.enumerated().map { i, _ in
            let lo = max(0, i - half)
            let hi = min(alts.count, i + half + 1)
            return alts[lo..<hi].reduce(0, +) / Double(hi - lo)
        }
    }

    /// 通用計算：用平滑後嘅海拔數據，取前半段平均做基準，返回 delta（可負數）
    private func computeWindowResult(candidates: [(offset: Int, element: BarometerSample)]) -> WindowResult? {
        guard candidates.count >= 3 else { return nil }
        let rawAlts = candidates.map { $0.element.relativeAltitude }
        let smoothed = smoothAltitudes(rawAlts)
        let firstHalf = smoothed.prefix(max(1, smoothed.count / 2))
        let ref = firstHalf.reduce(0, +) / Double(firstHalf.count)
        let final = smoothed.last!
        let delta = final - ref  // 可負數（入地庫）
        return WindowResult(
            sampleCount: candidates.count,
            deltaMeters: delta,
            referenceAlt: ref,
            finalAlt: final,
            finalPressure: candidates.last!.element.pressure,
            usedSampleRange: candidates.first!.offset..<(candidates.last!.offset + 1)
        )
    }

    func altitudeWindow(around date: Date, before: TimeInterval, after: TimeInterval) -> WindowResult? {
        guard !samples.isEmpty else { return nil }
        let start = date.addingTimeInterval(-before)
        let end = date.addingTimeInterval(after)
        let candidates = samples.enumerated().filter {
            $0.element.timestamp >= start && $0.element.timestamp <= end
        }
        guard candidates.count >= 3 else { return nil }

        // 平滑海拔數據
        let rawAlts = candidates.map { $0.element.relativeAltitude }
        let smoothed = smoothAltitudes(rawAlts)

        // 找路面基準線：最後一個高速樣本（仍在路面行駛時嘅海拔）
        var roadBaselineAlt: Double? = nil
        for (i, c) in candidates.enumerated() {
            if c.element.speedKmh >= Self.stationarySpeedThreshold {
                roadBaselineAlt = smoothed[i]
            }
        }

        let ref: Double
        if let baseline = roadBaselineAlt {
            ref = baseline
        } else {
            // 冇高速樣本，用前半段平均
            let firstHalf = smoothed.prefix(max(1, smoothed.count / 2))
            ref = firstHalf.reduce(0, +) / Double(firstHalf.count)
        }

        let final = smoothed.last!
        let delta = final - ref  // 可負數（入地庫 = 往下）
        return WindowResult(
            sampleCount: candidates.count,
            deltaMeters: delta,
            referenceAlt: ref,
            finalAlt: final,
            finalPressure: candidates.last!.element.pressure,
            usedSampleRange: candidates.first!.offset..<(candidates.last!.offset + 1)
        )
    }

    /// 取最近 N 秒的樣本，不管到達時間
    func recentWindow(seconds: TimeInterval) -> WindowResult? {
        guard !samples.isEmpty else { return nil }
        let cutoff = Date().addingTimeInterval(-seconds)
        let candidates = samples.enumerated().filter { $0.element.timestamp >= cutoff }
        return computeWindowResult(candidates: Array(candidates))
    }

    /// 只用低速/靜止樣本計算高度差（排除開車時的海拔變化）
    func stationaryRecentWindow(seconds: TimeInterval) -> WindowResult? {
        guard !samples.isEmpty else { return nil }
        let cutoff = Date().addingTimeInterval(-seconds)
        let candidates = samples.enumerated().filter {
            $0.element.timestamp >= cutoff && $0.element.speedKmh >= 0
                && $0.element.speedKmh < Self.stationarySpeedThreshold
        }
        return computeWindowResult(candidates: Array(candidates))
    }

    /// 取「預測用到嘅」樣本 index 範圍，供曲線圖標色
    func lastUsedSampleRange(seconds: TimeInterval = 2 * 60) -> Range<Int>? {
        return stationaryRecentWindow(seconds: seconds)?.usedSampleRange
            ?? recentWindow(seconds: seconds)?.usedSampleRange
    }
}
