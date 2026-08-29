import Foundation
import CoreLocation
import CoreMotion

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
    private var locationServicesStarted = false

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

        var duration: String {
            let departure: Date
            if let d = departureDate, d.timeIntervalSince(arrivalDate) < 7 * 24 * 3600 {
                departure = d
            } else {
                let elapsed = Date().timeIntervalSince(arrivalDate)
                if elapsed < 60 { return "< 1 min" }
                else if elapsed < 3600 { return "\(Int(elapsed / 60)) min" }
                else {
                    let h = Int(elapsed / 3600)
                    let m = Int(elapsed.truncatingRemainder(dividingBy: 3600) / 60)
                    return "\(h)h \(m)m"
                }
            }
            let interval = departure.timeIntervalSince(arrivalDate)
            if interval < 60 {
                return "< 1 min"
            } else if interval < 3600 {
                return "\(Int(interval / 60)) min"
            } else {
                let hours = Int(interval / 3600)
                let mins = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
                return "\(hours)h \(mins)m"
            }
        }
    }

    @Published var speed: Double = 0
    @Published var smoothedSpeed: Double = 0
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var gpsQuality: GPSQuality = .unknown
    @Published var currentAddress: String = ""
    @Published var visits: [VisitRecord] = []
    @Published var lastLocation: CLLocation?
    @Published var heading: Double = 0
    @Published var hasLoadedVisits: Bool = false

    private let visitsKey = "visit_records"

    // Kalman filter for speed smoothing
    private let speedKalmanFilter = KalmanFilter(processNoise: 0.01, measurementNoise: 0.5)
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
    }

    func startLocationServicesIfNeeded() {
        guard !locationServicesStarted else { return }
        locationServicesStarted = true
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        manager.startMonitoringVisits()
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
        // 啟動氣壓計持續採集，用於泊車樓層預測
        ParkingFloorStore.shared.barometer.startIfAuthorized()
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
                ParkingFloorStore.shared.barometer.currentSpeedKmh = self.speed
                ParkingFloorStore.shared.barometer.lastSpeedUpdateTime = Date()
            }
            let newQuality = self.quality(from: location.horizontalAccuracy)
            self.recentQualities.append(newQuality)
            if self.recentQualities.count > self.requiredSamples {
                self.recentQualities.removeFirst()
            }
            if self.recentQualities.count == self.requiredSamples,
               self.recentQualities.allSatisfy({ $0 == newQuality }) {
                self.gpsQuality = newQuality
            }

            if self.lastGeocodeLocation == nil ||
               location.distance(from: self.lastGeocodeLocation!) > 20 {
                self.reverseGeocode(location: location)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        let speedMs = manager.location?.speed ?? -1
        let speedKmh = speedMs >= 0 ? speedMs * 3.6 : 0
        let transport: String
        if speedKmh < 2 {
            transport = "Walking"
        } else if speedKmh < 80 {
            transport = "Driving"
        } else {
            transport = "Transit"
        }

        let record = VisitRecord(
            id: UUID(),
            address: "",
            latitude: visit.coordinate.latitude,
            longitude: visit.coordinate.longitude,
            arrivalDate: visit.arrivalDate,
            departureDate: visit.departureDate.timeIntervalSince(visit.arrivalDate) < 7 * 24 * 3600 ? visit.departureDate : nil,
            transportType: transport
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
                transportType: record.transportType
            )
            self.upsertVisitRecord(base)
        }
        
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let self else { return }
            var addr = ""
            if let placemark = placemarks?.first {
                var parts: [String] = []
                if let number = placemark.subThoroughfare, let street = placemark.thoroughfare {
                    parts.append("\(street) \(number)")
                } else if let street = placemark.thoroughfare {
                    parts.append(street)
                }
                addr = parts.joined(separator: " ")
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
                    transportType: record.transportType
                )
                self.upsertVisitRecord(updated)
            }
        }
    }

    private func reverseGeocode(location: CLLocation) {
        lastGeocodeLocation = location
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let placemark = placemarks?.first, error == nil else { return }
            DispatchQueue.main.async {
                var parts: [String] = []
                if let number = placemark.subThoroughfare, let street = placemark.thoroughfare {
                    parts.append("\(street) \(number)")
                } else if let street = placemark.thoroughfare {
                    parts.append(street)
                }
                self?.currentAddress = parts.joined(separator: " ")
            }
        }
    }

    private func matchVisitIndex(arrivalDate: Date, coordinate: CLLocationCoordinate2D) -> Int? {
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        for (idx, v) in visits.enumerated() {
            if abs(v.arrivalDate.timeIntervalSince(arrivalDate)) > 2.0 { continue }
            let d = target.distance(from: CLLocation(latitude: v.latitude, longitude: v.longitude))
            if d < 60 { return idx }
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
                    transportType: cur.transportType
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
        saveVisits()

        // MARK: TripPredictor: arrival / departure 掛鉤
        Task { @MainActor in
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
            self.authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedWhenInUse {
                manager.requestAlwaysAuthorization()
                self.gpsQuality = .unknown
            } else if manager.authorizationStatus == .authorizedAlways {
                self.gpsQuality = .unknown
            } else {
                self.gpsQuality = .bad
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let h = newHeading.magneticHeading
        DispatchQueue.main.async {
            self.heading = h
        }
    }

    private func saveVisits() {
        if let data = try? JSONEncoder().encode(visits) {
            UserDefaults.standard.set(data, forKey: visitsKey)
            UserDefaults.standard.synchronize()
        }
    }

    private func loadVisits() {
        guard let data = UserDefaults.standard.data(forKey: visitsKey),
              let decoded = try? JSONDecoder().decode([VisitRecord].self, from: data) else { return }
        visits = decoded.sorted { $0.arrivalDate > $1.arrivalDate }
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

    func clearVisits() {
        visits = []
        UserDefaults.standard.removeObject(forKey: visitsKey)
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
    var predictedFromLotLearned: Bool?
    // LLM 照片識別結果（持久化）
    var llmSpotNumber: String?
    var llmAreaCode: String?
    var llmFloorText: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var displayFloor: String? {
        if let manualFloorIndex {
            return llmFloorText ?? ParkingFloorStore.formatFloor(manualFloorIndex)
        }
        if let predictedFloorIndex {
            return llmFloorText ?? ParkingFloorStore.formatFloor(predictedFloorIndex)
        }
        return llmFloorText
    }
}

// MARK: - GCJ-02 Coordinate Transformation (China map offset fix)

extension CLLocationCoordinate2D {
    /// Convert WGS-84 coordinate to GCJ-02 (China's offset coordinate system).
    /// In China, Apple Maps tiles use GCJ-02, but GPS returns WGS-84.
    /// The blue dot is auto-corrected by iOS, but manually placed annotations need conversion.
    var wgs84ToGCJ02: CLLocationCoordinate2D {
        // China bounding box check
        guard longitude >= 72.004 && longitude <= 137.8347 &&
              latitude >= 0.8293 && latitude <= 55.8271 else {
            return self
        }

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
        // Same China bounding box check as wgs84ToGCJ02 — outside China this
        // is an exact no-op.
        guard longitude >= 72.004 && longitude <= 137.8347 &&
              latitude >= 0.8293 && latitude <= 55.8271 else {
            return self
        }
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

struct ParkingLotFloorLearning: Codable, Hashable {
    var createdAt: Date
    var manualFloorIndex: Int
    var altitudeDeltaMeters: Double
    var metersPerFloor: Double
    var lotID: UUID
    var pointID: UUID
}

struct ParkingLotRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String?
    var centerLatitude: Double
    var centerLongitude: Double
    var radiusMeters: Double
    var createdAt: Date
    var updatedAt: Date
    var points: [ParkingPointRecord]
    var learnedMetersPerFloor: Double?
    var learnedOffsetMeters: Double?
    var learnedConfidence: Double?
    var floorLearningHistory: [ParkingLotFloorLearning]?

    var centerCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: centerLatitude, longitude: centerLongitude)
    }

    func centerDistance(to coordinate: CLLocationCoordinate2D) -> Double {
        let a = CLLocation(latitude: centerLatitude, longitude: centerLongitude)
        let b = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return a.distance(from: b)
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

    @Published private(set) var lots: [ParkingLotRecord] = []
    /// 當前活躍的停車場 ID（最近一次 recordParkingPoint 命中的 lot）
    @Published var activeLotID: UUID?

    /// 最近一次低速/停留時的 GPS 位置（用於修正泊車位置，避免使用 visit 到達位置）
    var lastStationaryCoordinate: CLLocationCoordinate2D?
    /// 樓層曲線鎖定的樓層值（用於修正泊車樓層，避免獨立計算結果不一致）
    var floorCurveLockedFloor: Int?

    private let storeKey = "parking_floor_store_v1"
    private let defaults: UserDefaults

    let barometer = BarometerSessionManager()
    private var hasLoaded = false

    init() {
        defaults = UserDefaults(suiteName: "group.com.gorilla.translate") ?? .standard
    }

    /// 當前泊車會話（從活躍 lot 的最新 point 計算）
    var currentSession: ParkingSessionSnapshot? {
        let lot: ParkingLotRecord?
        if let activeID = activeLotID {
            lot = lots.first(where: { $0.id == activeID })
        } else {
            lot = lots.first
        }
        guard let lot, let point = lot.points.first else { return nil }
        let lotName = lot.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let locationName = (lotName?.isEmpty == false) ? lotName : (point.address.isEmpty ? nil : point.address)
        let floorDisplay = point.llmFloorText ?? point.displayFloor
        let floorIndex = point.manualFloorIndex ?? point.predictedFloorIndex
        return ParkingSessionSnapshot(
            locationName: locationName,
            spotNumber: point.llmSpotNumber,
            areaCode: point.llmAreaCode,
            floorDisplay: floorDisplay,
            floorIndex: floorIndex
        )
    }

    /// 更新活躍停車點的 LLM 照片識別結果
    func updateLLMData(spotNumber: String?, areaCode: String?, floorText: String?, floorIndex: Int?) {
        let lotIdx: Int
        if let activeID = activeLotID, let idx = lots.firstIndex(where: { $0.id == activeID }) {
            lotIdx = idx
        } else {
            lotIdx = 0
        }
        guard lots.indices.contains(lotIdx), !lots[lotIdx].points.isEmpty else { return }
        lots[lotIdx].points[0].llmSpotNumber = spotNumber
        lots[lotIdx].points[0].llmAreaCode = areaCode
        lots[lotIdx].points[0].llmFloorText = floorText
        if let floorIndex {
            setManualFloor(pointID: lots[lotIdx].points[0].id, floorIndex: floorIndex)
        } else {
            lots[lotIdx].updatedAt = Date()
            persist()
        }
    }

    func prepare() {
        guard !hasLoaded else { return }
        hasLoaded = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            load()
        }
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
        lots.flatMap { $0.points }.sorted { $0.createdAt > $1.createdAt }
    }
    
    var lotNameByPointID: [UUID: String] {
        var result: [UUID: String] = [:]
        for lot in lots {
            let name = lot.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { continue }
            for p in lot.points {
                result[p.id] = name
            }
        }
        return result
    }
    
    func clearAll() {
        lots = []
        persist()
    }
    
    func recordParkingPoint(from visit: LocationManager.VisitRecord) {
        // 確保氣壓計正在運行
        barometer.startIfAuthorized()

        // Bug 3a 修復：優先使用停留時的 GPS 位置（更準確）
        let visitCoord = CLLocationCoordinate2D(latitude: visit.latitude, longitude: visit.longitude)
        let coordinate: CLLocationCoordinate2D
        if let statCoord = lastStationaryCoordinate {
            let statLoc = CLLocation(latitude: statCoord.latitude, longitude: statCoord.longitude)
            let visitLoc = CLLocation(latitude: visitCoord.latitude, longitude: visitCoord.longitude)
            // 如果停留位置距離 visit 位置 < 200m，使用停留位置（更準確）
            if statLoc.distance(from: visitLoc) < 200 {
                coordinate = statCoord
            } else {
                coordinate = visitCoord
            }
        } else {
            coordinate = visitCoord
        }

        // 方案 A：用「停留瞬間海拔」做基準（最準確）
        var altitudeDelta: Double? = nil
        var referenceAlt: Double? = nil
        var finalAlt: Double? = nil
        var sampleCount: Int? = nil
        var pressure: Double? = nil

        if let statAlt = barometer.stationaryAltitude, barometer.samples.count >= 3 {
            // 用最近 10 秒嘅平滑海拔做 final
            let recent = barometer.samples.suffix(10)
            let smoothedFinal = recent.map { $0.relativeAltitude }.reduce(0, +) / Double(recent.count)
            altitudeDelta = smoothedFinal - statAlt
            referenceAlt = statAlt
            finalAlt = smoothedFinal
            sampleCount = recent.count
            pressure = barometer.samples.last?.pressure
        } else {
            // 方案 B fallback：窗口計算（原有邏輯）
            var window = barometer.altitudeWindow(around: visit.arrivalDate,
                                                  before: 4 * 60,
                                                  after: 1 * 60)
            if window == nil || (window?.samples ?? 0) < 3 {
                window = barometer.stationaryRecentWindow(seconds: 2 * 60)
            }
            if window == nil || (window?.samples ?? 0) < 3 {
                window = barometer.recentWindow(seconds: 2 * 60)
            }
            altitudeDelta = window?.deltaMeters
            referenceAlt = window?.referenceAlt
            finalAlt = window?.finalAlt
            sampleCount = window?.samples
            pressure = window?.finalPressure
        }

        let predicted = predictFloor(
            near: coordinate,
            createdAt: visit.arrivalDate,
            altitudeDelta: altitudeDelta,
            sampleCount: sampleCount,
            referenceAlt: referenceAlt,
            finalAlt: finalAlt,
            pressure: pressure
        )

        // Bug 3b 修復：優先使用樓層曲線鎖定的樓層（更準確）
        let finalFloorIndex: Int?
        let finalConfidence: Double?
        if let lockedFloor = floorCurveLockedFloor {
            finalFloorIndex = lockedFloor
            finalConfidence = 0.9  // 鎖定的樓層信心度高
        } else {
            finalFloorIndex = predicted.floorIndex
            finalConfidence = predicted.confidence
        }

        recordParkingPoint(
            coordinate: coordinate,
            address: visit.address,
            createdAt: visit.arrivalDate,
            predictedFloorIndex: finalFloorIndex,
            manualFloorIndex: nil,
            confidence: finalConfidence,
            altitudeDelta: altitudeDelta,
            sampleCount: sampleCount,
            referenceAlt: referenceAlt,
            finalAlt: finalAlt,
            pressure: pressure,
            predictedFromLotLearned: predicted.fromLotLearned
        )

        // 如果氣壓計樣本不夠導致樓層未知，60 秒後重試
        if predicted.floorIndex == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
                guard let self else { return }
                self.retryFloorPrediction(coordinate: coordinate)
            }
        }
    }

    /// 當樓層曲線鎖定時，更新活躍泊車點的坐標和樓層
    func updateActivePointFromFloorCurve(lockedFloor: Int, coordinate: CLLocationCoordinate2D?) {
        // 保存鎖定樓層供 recordParkingPoint 使用
        floorCurveLockedFloor = lockedFloor

        guard let activeLotID, let lotIdx = lots.firstIndex(where: { $0.id == activeLotID }) else { return }
        guard let point = lots[lotIdx].points.first else { return }

        // 更新樓層
        if point.predictedFloorIndex != lockedFloor {
            lots[lotIdx].points[0].predictedFloorIndex = lockedFloor
            lots[lotIdx].points[0].confidence = 0.9
        }

        // 更新坐標（如果有更準確的位置）
        if let coord = coordinate {
            let existingLoc = CLLocation(latitude: point.latitude, longitude: point.longitude)
            let newLoc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            // 只有當新位置距離現有位置 < 200m 時才更新（避免錯誤更新）
            if existingLoc.distance(from: newLoc) < 200 {
                lots[lotIdx].points[0].latitude = coord.latitude
                lots[lotIdx].points[0].longitude = coord.longitude
            }
        }

        lots[lotIdx].updatedAt = Date()
        persist()
    }

    private func retryFloorPrediction(coordinate: CLLocationCoordinate2D) {
        // 重試時用現在時間前後 8 分鐘的樣本窗口
        var window = barometer.altitudeWindow(around: Date(), before: 8 * 60, after: 1 * 60)
        if window == nil || (window?.sampleCount ?? 0) < 3 {
            window = barometer.stationaryRecentWindow(seconds: 2 * 60)
        }
        if window == nil || (window?.sampleCount ?? 0) < 3 {
            window = barometer.recentWindow(seconds: 2 * 60)
        }
        guard let window, window.sampleCount >= 3 else { return }
        let predicted = predictFloor(
            near: coordinate,
            createdAt: Date(),
            altitudeDelta: window.deltaMeters,
            sampleCount: window.samples,
            referenceAlt: window.referenceAlt,
            finalAlt: window.finalAlt,
            pressure: window.finalPressure
        )
        guard let floorIndex = predicted.floorIndex else { return }
        // 找到最近的停車點並更新樓層
        let lotIdx = findLotIndex(near: coordinate, radiusMeters: Self.defaultRadiusMeters)
        guard let lotIdx, let point = lots[lotIdx].points.first else { return }
        if point.predictedFloorIndex == nil && point.manualFloorIndex == nil {
            lots[lotIdx].points[0].predictedFloorIndex = floorIndex
            lots[lotIdx].points[0].confidence = predicted.confidence
            lots[lotIdx].points[0].barometerAltitudeDeltaMeters = window.deltaMeters
            lots[lotIdx].points[0].barometerSampleCount = window.samples
            lots[lotIdx].updatedAt = Date()
            persist()
        }
    }
    
    func recordParkingPoint(
        coordinate: CLLocationCoordinate2D,
        address: String,
        createdAt: Date,
        predictedFloorIndex: Int?,
        manualFloorIndex: Int?,
        confidence: Double?
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
            predictedFromLotLearned: nil
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
        predictedFromLotLearned: Bool?
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
            predictedFromLotLearned: predictedFromLotLearned
        )
        
        if let idx = findLotIndex(near: coordinate, radiusMeters: Self.defaultRadiusMeters) {
            var lot = lots[idx]
            let dup = lot.points.contains { p in
                abs(p.createdAt.timeIntervalSince(createdAt)) < 30 &&
                CLLocation(latitude: p.latitude, longitude: p.longitude).distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) < 10
            }
            guard !dup else { return }
            lot.points.insert(inserting, at: 0)
            lot.updatedAt = now
            lots[idx] = lot
            activeLotID = lot.id
        } else {
            let lot = ParkingLotRecord(
                id: UUID(),
                name: nil,
                centerLatitude: coordinate.latitude,
                centerLongitude: coordinate.longitude,
                radiusMeters: Self.defaultRadiusMeters,
                createdAt: now,
                updatedAt: now,
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
    }
    
    func setManualFloor(pointID: UUID, floorIndex: Int?) {
        var changed = false
        for i in lots.indices {
            if let pIndex = lots[i].points.firstIndex(where: { $0.id == pointID }) {
                let before = lots[i].points[pIndex].manualFloorIndex
                lots[i].points[pIndex].manualFloorIndex = floorIndex
                lots[i].updatedAt = Date()
                changed = true
                
                if floorIndex != before,
                   let newIdx = floorIndex,
                   let delta = lots[i].points[pIndex].barometerAltitudeDeltaMeters {
                    applyFloorLearning(
                        lotIndex: i,
                        pointID: pointID,
                        manualFloorIndex: newIdx,
                        altitudeDeltaMeters: delta
                    )
                }
                
                if floorIndex != before {
                    lots[i] = rerunPredictions(lot: lots[i])
                }
                
                break
            }
        }
        if changed {
            persist()
        }
    }
    
    private func applyFloorLearning(
        lotIndex: Int,
        pointID: UUID,
        manualFloorIndex: Int,
        altitudeDeltaMeters: Double
    ) {
        let lotID = lots[lotIndex].id
        let delta = altitudeDeltaMeters
        let floorIdx = manualFloorIndex
        let metersPerFloor = floorIdx == 0 ? 0 : (delta / Double(floorIdx))
        
        let learning = ParkingLotFloorLearning(
            createdAt: Date(),
            manualFloorIndex: manualFloorIndex,
            altitudeDeltaMeters: delta,
            metersPerFloor: metersPerFloor,
            lotID: lotID,
            pointID: pointID
        )
        if lots[lotIndex].floorLearningHistory == nil {
            lots[lotIndex].floorLearningHistory = []
        }
        lots[lotIndex].floorLearningHistory!.append(learning)
        
        let history = lots[lotIndex].floorLearningHistory ?? []
        let valid = history.filter {
            $0.manualFloorIndex != 0 && $0.altitudeDeltaMeters != 0
        }
        if valid.count >= 1 {
            var mean = valid.reduce(0.0) { $0 + abs($1.metersPerFloor) } / Double(valid.count)
            if mean < 2.0 { mean = 2.0 }
            if mean > 6.0 { mean = 6.0 }
            lots[lotIndex].learnedMetersPerFloor = mean
            
            let std = sqrt(valid.reduce(0.0) { sum, x in
                let d = abs(x.metersPerFloor) - mean
                return sum + d * d
            } / max(1.0, Double(valid.count)))
            let coef = std / max(0.1, mean)
            let conf: Double = max(0.1, min(0.98, 1.0 - coef))
            let sampleBoost = min(1.0, Double(valid.count) / 4.0)
            lots[lotIndex].learnedConfidence = 0.3 + 0.7 * (0.6 * conf + 0.4 * sampleBoost)
        }
        
        let offsets: [Double] = history.compactMap { h in
            guard h.manualFloorIndex != 0 else { return nil }
            return h.altitudeDeltaMeters - Double(h.manualFloorIndex) * (lots[lotIndex].learnedMetersPerFloor ?? Self.defaultMetersPerFloor)
        }
        if !offsets.isEmpty {
            lots[lotIndex].learnedOffsetMeters = offsets.reduce(0.0, +) / Double(offsets.count)
        }
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

    private func rerunPredictions(lot: ParkingLotRecord) -> ParkingLotRecord {
        var copy = lot
        let mpF = copy.learnedMetersPerFloor ?? Self.defaultMetersPerFloor
        let offset = copy.learnedOffsetMeters ?? 0.0
        let lotConf = copy.learnedConfidence ?? 0.0
        
        for i in copy.points.indices {
            let p = copy.points[i]
            guard p.manualFloorIndex == nil else { continue }
            guard let delta = p.barometerAltitudeDeltaMeters,
                  let samples = p.barometerSampleCount else { continue }
            let adjustedDelta = max(0.0, delta - offset)
            let raw = (adjustedDelta / mpF).rounded(.toNearestOrAwayFromZero)
            var predicted: Int? = Int(raw)
            if predicted ?? 0 < 0 { predicted = 0 }
            if (predicted ?? 0) > 30 { predicted = 30 }
            
            let sampleFactor: Double = samples >= 40 ? 1.0 : (Double(samples) / 40.0)
            let learnedFactor: Double = (copy.learnedMetersPerFloor != nil) ? 1.0 : 0.35
            var conf: Double = 0.15 + 0.85 * (0.55 * lotConf + 0.25 * sampleFactor + 0.2 * learnedFactor)
            if abs((Double(predicted ?? 0) * mpF) - adjustedDelta) > mpF * 0.5 {
                conf *= 0.7
            }
            conf = max(0.1, min(0.98, conf))
            
            copy.points[i].predictedFloorIndex = predicted
            copy.points[i].confidence = conf
            copy.points[i].predictedFromLotLearned = copy.learnedMetersPerFloor != nil
        }
        return copy
    }
    
    private func predictFloor(
        near coordinate: CLLocationCoordinate2D,
        createdAt: Date,
        altitudeDelta: Double?,
        sampleCount: Int?,
        referenceAlt: Double?,
        finalAlt: Double?,
        pressure: Double?
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
        let adjustedDelta = delta - offset  // 可負數（入地庫）
        let raw = (adjustedDelta / mpF).rounded(.toNearestOrAwayFromZero)
        var predicted = Int(raw)
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

    func setPointCoordinate(pointID: UUID, coordinate: CLLocationCoordinate2D) {
        var changed = false
        for i in lots.indices {
            if let pIndex = lots[i].points.firstIndex(where: { $0.id == pointID }) {
                lots[i].points[pIndex].latitude = coordinate.latitude
                lots[i].points[pIndex].longitude = coordinate.longitude
                lots[i].updatedAt = Date()
                changed = true
                break
            }
        }
        if changed {
            persist()
        }
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

    /// 同步停車場名稱：搵到同一位置嘅 lot 並更新名稱（由地址叢集改名觸發）
    func syncLotName(near coordinate: CLLocationCoordinate2D, newName: String) {
        if let idx = findLotIndex(near: coordinate, radiusMeters: 180) {
            lots[idx].name = newName
            lots[idx].updatedAt = Date()
            persist()
        }
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
            persist()
            break
        }
    }
    
    func findLotIndex(near coordinate: CLLocationCoordinate2D, radiusMeters: Double) -> Int? {
        let loc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        for (idx, lot) in lots.enumerated() {
            let c = CLLocation(latitude: lot.centerLatitude, longitude: lot.centerLongitude)
            if c.distance(from: loc) <= min(radiusMeters, lot.radiusMeters) {
                return idx
            }
        }
        return nil
    }
    
    private func persist() {
        do {
            let data = try JSONEncoder().encode(lots)
            defaults.set(data, forKey: storeKey)
            defaults.synchronize()
        } catch {
            // encode 失敗時唔好刪數據，保留上一次成功嘅版本
            print("[ParkingFloorStore] persist encode error: \(error)")
        }
    }
    
    private func load() {
        guard let data = defaults.data(forKey: storeKey) else { return }
        guard let decoded = try? JSONDecoder().decode([ParkingLotRecord].self, from: data) else { return }
        lots = decoded.map { rerunPredictions(lot: $0) }.sorted { $0.updatedAt > $1.updatedAt }
    }
    
    static func formatFloor(_ idx: Int) -> String {
        if idx == 0 { return "G" }
        if idx < 0 { return "B\(abs(idx))" }
        return "\(idx)"
    }
}

struct BarometerSample: Hashable {
    let timestamp: Date
    let relativeAltitude: Double
    let pressure: Double
    /// 採樣時的車速 (km/h)，-1 表示未知
    let speedKmh: Double
}

final class BarometerSessionManager: NSObject, ObservableObject {
    private let altimeter = CMAltimeter()
    private let queue = OperationQueue()
    @Published private(set) var samples: [BarometerSample] = []
    private(set) var isUpdating = false
    /// 當前車速 (km/h)，由 LocationManager 更新；-1 = 未知
    @Published var currentSpeedKmh: Double = -1
    /// 最後一次 GPS 更新速度的時間
    var lastSpeedUpdateTime: Date = Date()

    // MARK: - 停留偵測（10 秒靜止 → 記錄海拔）
    /// 連續低速樣本計數（每秒 +1，高速歸零）
    private var consecutiveLowSpeedCount: Int = 0
    /// 是否已記錄停留海拔
    private var hasRecordedStationaryAltitude = false
    /// 進入「停留中」瞬間嘅平滑海拔
    @Published var stationaryAltitude: Double? = nil
    /// 最近 10 個低速樣本嘅海拔（用於平滑計算，在背景 queue 操作）
    private var recentLowSpeedAlts: [Double] = []
    
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
    }
    
    deinit {
        if isUpdating {
            altimeter.stopRelativeAltitudeUpdates()
            isUpdating = false
        }
    }
    
    @discardableResult
    func startIfAuthorized() -> Bool {
        guard isAvailable else { return false }
        guard isAuthorized else { return false }
        guard !isUpdating else { return true }
        isUpdating = true
        let altimeter = self.altimeter
        altimeter.startRelativeAltitudeUpdates(to: queue) { [weak self] data, _ in
            guard let self = self, let data = data else { return }
            // 偵測 GPS 失效：超過 15 秒冇速度更新，將速度視為 0（靜止/地庫/隧道）
            let effectiveSpeed: Double
            let speedAge = Date().timeIntervalSince(self.lastSpeedUpdateTime)
            if speedAge > 15 {
                effectiveSpeed = 0
            } else {
                effectiveSpeed = self.currentSpeedKmh
            }
            let sample = BarometerSample(
                timestamp: Date(),
                relativeAltitude: data.relativeAltitude.doubleValue,
                pressure: data.pressure.doubleValue,
                speedKmh: effectiveSpeed
            )

            // 偵測停留：連續 10 秒低速 → 記錄海拔（取 10 個樣本平滑）
            let alt = data.relativeAltitude.doubleValue
            if effectiveSpeed < Self.stationarySpeedThreshold {
                self.consecutiveLowSpeedCount += 1
                // 維護最近 10 個低速海拔
                self.recentLowSpeedAlts.append(alt)
                if self.recentLowSpeedAlts.count > 10 {
                    self.recentLowSpeedAlts.removeFirst(self.recentLowSpeedAlts.count - 10)
                }
                if self.consecutiveLowSpeedCount >= 10 && !self.hasRecordedStationaryAltitude {
                    self.hasRecordedStationaryAltitude = true
                    // 取最近 10 個樣本嘅平均做平滑海拔
                    let smoothed = self.recentLowSpeedAlts.reduce(0, +) / Double(self.recentLowSpeedAlts.count)
                    DispatchQueue.main.async {
                        self.stationaryAltitude = smoothed
                    }
                }
            } else {
                self.consecutiveLowSpeedCount = 0
                self.recentLowSpeedAlts.removeAll()
                // 重新開始行駛 → 重置，下次停車可以再記錄
                if self.hasRecordedStationaryAltitude {
                    self.hasRecordedStationaryAltitude = false
                    DispatchQueue.main.async {
                        self.stationaryAltitude = nil
                    }
                }
            }

            DispatchQueue.main.async {
                self.samples.append(sample)
                // 保留最多 ~15 分鐘的樣本（氣壓計每秒約 1 個）
                let maxSamples = 15 * 60
                if self.samples.count > maxSamples {
                    self.samples.removeFirst(self.samples.count - maxSamples)
                }
            }
        }
        return true
    }
    
    func stop() {
        if isUpdating {
            altimeter.stopRelativeAltitudeUpdates()
            isUpdating = false
        }
    }

    func clearSamples() {
        samples.removeAll()
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
            $0.element.timestamp >= cutoff && $0.element.speedKmh < Self.stationarySpeedThreshold
        }
        return computeWindowResult(candidates: Array(candidates))
    }

    /// 取「預測用到嘅」樣本 index 範圍，供曲線圖標色
    func lastUsedSampleRange(seconds: TimeInterval = 2 * 60) -> Range<Int>? {
        return stationaryRecentWindow(seconds: seconds)?.usedSampleRange
            ?? recentWindow(seconds: seconds)?.usedSampleRange
    }
}
