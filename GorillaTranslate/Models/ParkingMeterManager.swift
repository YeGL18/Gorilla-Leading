import Foundation
import CoreLocation
import MapKit
import Combine

struct MeterNotice: Identifiable {
    enum Kind { case destination, nearby, stationary }
    let id = UUID()
    let kind: Kind
    let meter: ParkingMeter
    let count: Int
    let destinationName: String
    let expiresAt: Date
    var title: String {
        switch kind {
        case .destination: return String(format: String(localized: "檢測到%@附近有 %d 個空置咪錶位"), destinationName, count)
        case .nearby: return String(format: String(localized: "檢測到附近有 %d 個空置咪錶位"), count)
        case .stationary: return String(localized: "檢測到旁邊的咪錶位")
        }
    }
    /// 彈窗主動作：空置咪錶（附近／目的地）→ 導航去個錶位；
    /// 人就喺個錶位隔離 → 前往繳費
    var actionTitle: String {
        switch kind {
        case .destination: return String(localized: "前往咪錶位")
        case .nearby: return String(localized: "導航")
        case .stationary: return String(localized: "前往繳費")
        }
    }
    var actionSymbol: String {
        kind == .stationary ? "creditcard.fill" : "arrow.triangle.turn.up.right.diamond.fill"
    }
}

@MainActor
final class ParkingMeterManager: ObservableObject {
    static let shared = ParkingMeterManager()
    @Published private(set) var allMeters: [ParkingMeter] = []
    @Published private(set) var occupancies: [String: MeterStatus] = [:]
    @Published private(set) var visibleMeters: [ParkingMeter] = []
    @Published private(set) var lastStatusFetch: Date?
    @Published private(set) var lastSpacesFetch: Date?
    @Published private(set) var loading = false
    @Published private(set) var statusRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var statusErrorMessage: String?
    @Published private(set) var revision = 0
    @Published var selectedMeter: ParkingMeter?
    @Published private(set) var notice: MeterNotice?
    @Published var needsVehicleSelection = false
    @Published var paymentHelpPresented = false
    @Published var isTestPageActive = false

    static let spacesURL = URL(string: "https://resource.data.one.gov.hk/td/psiparkingspaces/spaceinfo/parkingspaces.csv")!
    static let occupancyURL = URL(string: "https://resource.data.one.gov.hk/td/psiparkingspaces/occupancystatus/occupancystatus.csv")!
    private let defaults: UserDefaults
    private var index = MeterSpatialIndex([])
    private var visibility = MeterVisibility()
    private var prepared = false
    private var fetchingStatus = false
    private var lastStatusAttempt: Date?
    private var lastSpacesAttempt: Date?
    private var stalePublished = false
    private var currentLocation: CLLocation?
    private var stationarySince: Date?
    private var stationaryAnchor: CLLocation?
    private var stationaryShown = false
    private var streetSuppression: [String: Date] = [:]
    private var destinationID: UUID?
    private var destinationHandled = false
    private var arrived = false
    private var routeDistance: Double?
    private var routeDate: Date?
    private var routeRequestDate: Date?
    private var routeRequestToken: UUID?
    private var lastSettings = ""
    private var isActive = true

    init(defaults: UserDefaults = .standard, initialMeters: [ParkingMeter] = [],
         initialStatuses: [String: MeterStatus] = [:], fetchedAt: Date? = nil) {
        self.defaults = defaults
        allMeters = initialMeters
        index = MeterSpatialIndex(initialMeters)
        occupancies = initialStatuses
        lastStatusFetch = fetchedAt
    }
    var isEnabled: Bool { defaults.object(forKey: "meterDetectionEnabled") as? Bool ?? true }
    var vehicle: MeterVehicle { MeterVehicle(rawValue: defaults.string(forKey: "meterVehicle") ?? "") ?? .unset }
    var radius: Double { setting("meterMapRadius", fallback: 500, range: 100...800) }
    var destinationRadius: Double { setting("meterDestinationRadius", fallback: 500, range: 50...800) }
    var nearbyRadius: Double { setting("meterNearbyRadius", fallback: 100, range: 10...200) }
    var statusRefreshInterval: TimeInterval {
        let value = defaults.object(forKey: "meterStatusRefreshInterval") as? Double ?? 60
        guard value.isFinite else { return 60 }
        return min(300, max(30, (value / 30).rounded() * 30))
    }
    func shouldRefreshStatus(at now: Date = Date()) -> Bool {
        !fetchingStatus && isActive && now.timeIntervalSince(lastStatusAttempt ?? .distantPast) >= statusRefreshInterval
    }
    private func setting(_ key: String, fallback: Double, range: ClosedRange<Double>) -> Double {
        let value = (defaults.object(forKey: key) as? Double) ?? fallback
        return min(range.upperBound, max(range.lowerBound, (value / 10).rounded() * 10))
    }
    private var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("meter-spaces-v2.csv")
    }

    func prepare() {
        guard !prepared else { return }
        prepared = true
        let url = cacheURL
        Task {
            let cached = await Task.detached(priority: .utility) {
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [ParkingMeter]() }
                return (try? MeterCSV.spaces(text)) ?? []
            }.value
            if !cached.isEmpty { install(cached) }
            lastSpacesFetch = defaults.object(forKey: "meterSpacesV2FetchedAt") as? Date
            if cached.isEmpty || Date().timeIntervalSince(lastSpacesFetch ?? .distantPast) >= 86400 {
                await refreshSpaces()
            }
        }
    }

    private func install(_ meters: [ParkingMeter]) {
        allMeters = meters
        index = MeterSpatialIndex(meters)
        revision += 1
    }

    func refreshSpaces() async {
        guard !loading else { return }
        loading = true
        lastSpacesAttempt = Date()
        defer { loading = false }
        do {
            let (data, response) = try await URLSession.shared.data(from: Self.spacesURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200, let text = String(data: data, encoding: .utf8) else {
                throw URLError(.badServerResponse)
            }
            let meters = try await Task.detached(priority: .utility) { try MeterCSV.spaces(text) }.value
            // Only replace a good cache after validation has succeeded.
            try data.write(to: cacheURL, options: .atomic)
            install(meters)
            lastSpacesFetch = Date()
            defaults.set(lastSpacesFetch, forKey: "meterSpacesV2FetchedAt")
            errorMessage = nil
        } catch { errorMessage = String(format: String(localized: "位置資料未能更新：%@"), error.localizedDescription) }
    }

    func refreshStatus(force: Bool = false) async {
        guard !fetchingStatus, isActive else { return }
        let now = Date()
        guard force || shouldRefreshStatus(at: now) else { return }
        fetchingStatus = true
        statusRefreshing = true
        lastStatusAttempt = now
        defer {
            fetchingStatus = false
            statusRefreshing = false
        }
        do {
            var request = URLRequest(url: Self.occupancyURL, cachePolicy: .reloadIgnoringLocalCacheData)
            request.timeoutInterval = 25
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, let text = String(data: data, encoding: .utf8) else {
                throw URLError(.badServerResponse)
            }
            let statuses = try await Task.detached(priority: .utility) { try MeterCSV.statuses(text) }.value
            occupancies = statuses
            lastStatusFetch = Date()
            stalePublished = false
            errorMessage = nil
            statusErrorMessage = nil
            revision += 1
        } catch {
            let message = String(format: String(localized: "狀態未能更新：%@"), error.localizedDescription)
            statusErrorMessage = message
            errorMessage = message
        }
    }

    func state(_ meter: ParkingMeter, now: Date = Date()) -> MeterDisplayState {
        MeterDisplayState.resolve(meter: meter, status: occupancies[meter.id], vehicle: vehicle, fetchedAt: lastStatusFetch, now: now)
    }

    func representative(_ meters: [ParkingMeter]) -> ParkingMeter? {
        let ranked = meters.sorted { a, b in
            guard let location = currentLocation else { return a.id < b.id }
            return location.distance(from: a.location) < location.distance(from: b.location)
        }
        return ranked.first(where: { state($0) == .vacant })
            ?? ranked.first(where: { state($0) == .incompatible }) ?? ranked.first
    }

    func select(_ meter: ParkingMeter) {
        dismissNotice()
        selectedMeter = meter
    }

    /// 推斷泊車點旁邊嘅咪錶標注（車藍牙斷聯／導航目標輔助泊車點命名）
    /// - confirmed：導航目標咪錶喺 30m 內，或者最近咪錶 ≤25m 且同第二近距離差 ≥10m（唯一最近）→ 記具體咪錶，坐標吸附去咪錶位
    /// - estimated ：40m 內有咪錶但唔可以確認係邊個 → 只記街道，唔記具體咪錶，唔吸附
    func inferMeterAnnotation(at coordinate: CLLocationCoordinate2D, navigationTargetID: String?) -> ParkingPointMeterAnnotation? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        // 導航目標咪錶優先（用戶導航去嗰個位）
        if let targetID = navigationTargetID, let target = allMeters.first(where: { $0.id == targetID }) {
            let d = target.location.distance(from: location)
            if d <= 30 {
                return ParkingPointMeterAnnotation(
                    meterID: target.id, street: target.street, kind: "confirmed",
                    snapCoordinate: target.coordinate
                )
            }
        }
        // 最近咪錶（嚴格唯一最近先算 confirmed）
        let nearby = index.nearby(location, radius: 45)
            .map { ($0, $0.location.distance(from: location)) }
            .sorted { $0.1 < $1.1 }
        guard let nearest = nearby.first else { return nil }
        if nearest.1 <= 25 {
            let secondGap = (nearby.count > 1) ? (nearby[1].1 - nearest.1) : .infinity
            if secondGap >= 10 {
                return ParkingPointMeterAnnotation(
                    meterID: nearest.0.id, street: nearest.0.street, kind: "confirmed",
                    snapCoordinate: nearest.0.coordinate
                )
            }
        }
        if nearest.1 <= 40 {
            return ParkingPointMeterAnnotation(
                meterID: nil, street: nearest.0.street, kind: "estimated", snapCoordinate: nil
            )
        }
        return nil
    }

    func dismissNotice() { notice = nil }

    func setActive(_ active: Bool) {
        isActive = active
        if !active {
            dismissNotice()
            stationarySince = nil
            stationaryAnchor = nil
            routeRequestToken = nil
        }
    }

    func updateRouteDistance(_ distance: Double, destinationID: UUID, calculatedAt: Date = Date()) {
        guard self.destinationID == destinationID else { return }
        routeDistance = distance
        routeDate = calculatedAt
    }

    func tick(location: CLLocation?, speed: Double, destination: Destination?, canPresentNotices: Bool = true, now: Date = Date()) {
        guard isActive else { return }
        if prepared && allMeters.isEmpty && !loading && now.timeIntervalSince(lastSpacesAttempt ?? .distantPast) >= 60 {
            Task { await refreshSpaces() }
        }
        if let notice, now >= notice.expiresAt { dismissNotice() }
        if !stalePublished, let date = lastStatusFetch, now.timeIntervalSince(date) > 180 {
            stalePublished = true; revision += 1
        }
        let settings = "\(vehicle.rawValue)|\(radius)|\(destinationRadius)|\(nearbyRadius)|\(isEnabled)"
        if settings != lastSettings {
            lastSettings = settings
            visibility.reset()
            dismissNotice()
            revision += 1
            if isEnabled && vehicle == .unset { needsVehicleSelection = true }
        }
        if destination?.id != destinationID {
            destinationID = destination?.id
            destinationHandled = destinationID != nil && defaults.string(forKey: "meterSuppressedDestination") == destinationID?.uuidString
            if !destinationHandled { defaults.removeObject(forKey: "meterSuppressedDestination") }
            arrived = false
            routeDistance = nil; routeDate = nil; routeRequestDate = nil
            routeRequestToken = nil
            dismissNotice()
        }
        guard isEnabled, let location, location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 100, now.timeIntervalSince(location.timestamp) < 20,
              speed.isFinite, speed >= 0 else {
            if !visibleMeters.isEmpty { visibleMeters = [] }
            stationarySince = nil; stationaryAnchor = nil
            dismissNotice()
            if isTestPageActive && shouldRefreshStatus(at: now) { Task { await refreshStatus() } }
            return
        }
        currentLocation = location
        if speed >= 5 { stationaryShown = false }
        if let activeNotice = notice, activeNotice.kind != .stationary, state(activeNotice.meter, now: now) != .vacant {
            dismissNotice()
        }
        let candidates = index.nearby(location, radius: radius * 2)
        let visible = visibility.update(candidates: candidates, location: location, speed: speed, radius: radius, now: now)
        if visible != visibleMeters { visibleMeters = visible }
        var destinationMeters: [ParkingMeter] = []
        if let destination, !destinationHandled {
            let target = CLLocation(latitude: destination.coordinate.latitude, longitude: destination.coordinate.longitude)
            if location.distance(from: target) <= 2500 {
                refreshDestinationDistance(location: location, destination: destination, now: now)
            }
            if let routeDistance, let routeDate, now.timeIntervalSince(routeDate) <= 120, routeDistance <= 2000 {
                destinationMeters = index.nearby(target, radius: destinationRadius)
            }
        }
        if let destination {
            let target = CLLocation(latitude: destination.coordinate.latitude, longitude: destination.coordinate.longitude)
            let distance = location.distance(from: target)
            if distance < 30 {
                arrived = true; destinationHandled = true; destinationMeters = []
                defaults.set(destination.id.uuidString, forKey: "meterSuppressedDestination")
            }
            if arrived && distance > 500 {
                arrived = false; destinationHandled = false; routeDistance = nil; routeDate = nil
                defaults.removeObject(forKey: "meterSuppressedDestination")
            }
        }
        if isTestPageActive || !visible.isEmpty || !destinationMeters.isEmpty {
            if shouldRefreshStatus(at: now) { Task { await refreshStatus() } }
        }
        let nearby = index.nearby(location, radius: max(nearbyRadius, 10))
        if !canPresentNotices || isTestPageActive || selectedMeter != nil || vehicle == .unset || !visibility.speedAllowsDisplay {
            stationarySince = nil; stationaryAnchor = nil
            if !canPresentNotices || !visibility.speedAllowsDisplay { dismissNotice() }
            return
        }
        evaluateNotices(nearby: nearby, destinationMeters: destinationMeters, destinationName: destination?.name ?? "目的地",
                        location: location, speed: speed, now: now)
    }

    private func refreshDestinationDistance(location: CLLocation, destination: Destination, now: Date) {
        guard routeRequestToken == nil, now.timeIntervalSince(routeRequestDate ?? .distantPast) >= 60,
              now.timeIntervalSince(routeDate ?? .distantPast) >= 60 else { return }
        routeRequestDate = now
        let token = UUID()
        let requestedDestinationID = destination.id
        routeRequestToken = token
        DestinationManager.shared.requestRoute(from: location.coordinate, to: destination.coordinate) { [weak self] result in
            let distance = result?.route.distance
            Task { @MainActor in
                guard let self, self.routeRequestToken == token else { return }
                self.routeRequestToken = nil
                if let distance, let result {
                    self.updateRouteDistance(distance, destinationID: requestedDestinationID, calculatedAt: result.calculatedAt)
                }
            }
        }
    }

    func evaluateNotices(nearby: [ParkingMeter], destinationMeters: [ParkingMeter], destinationName: String,
                                 location: CLLocation, speed: Double, now: Date) {
        let close = nearby.filter { $0.location.distance(from: location) <= 10 && $0.bayType.accepts(vehicle) }
        if speed <= 0.5 && location.horizontalAccuracy <= 15 && !close.isEmpty {
            if stationaryAnchor == nil || stationaryAnchor!.distance(from: location) > 10 {
                stationaryAnchor = location; stationarySince = now
            }
        } else {
            stationarySince = nil; stationaryAnchor = nil
            if speed >= 5 { stationaryShown = false }
        }
        // Higher-priority notices replace lower-priority ones, never stack them.
        if !stationaryShown, let since = stationarySince, now.timeIntervalSince(since) >= 10,
           let meter = representative(close) {
            stationaryShown = true
            streetSuppression[meter.streetKey] = now
            notice = MeterNotice(kind: .stationary, meter: meter, count: 0, destinationName: "", expiresAt: now.addingTimeInterval(10))
            return
        }
        if notice?.kind == .stationary || notice?.kind == .nearby { return }
        let streetKeys = Set(nearby.map(\.streetKey))
        streetSuppression = streetSuppression.filter { streetKeys.contains($0.key) || now.timeIntervalSince($0.value) < 180 }
        let vacant = nearby.filter { $0.location.distance(from: location) <= nearbyRadius && state($0, now: now) == .vacant }
        if let meter = representative(vacant.filter { streetSuppression[$0.streetKey] == nil }) {
            for key in Set(vacant.map(\.streetKey)) { streetSuppression[key] = now }
            notice = MeterNotice(kind: .nearby, meter: meter, count: vacant.count, destinationName: "", expiresAt: now.addingTimeInterval(10))
            return
        }
        guard notice == nil, !destinationHandled else { return }
        let available = destinationMeters.filter { state($0, now: now) == .vacant }
        if let meter = representative(available) {
            destinationHandled = true
            if let destinationID { defaults.set(destinationID.uuidString, forKey: "meterSuppressedDestination") }
            notice = MeterNotice(kind: .destination, meter: meter, count: available.count, destinationName: destinationName,
                                 expiresAt: now.addingTimeInterval(10))
        }
    }
}
