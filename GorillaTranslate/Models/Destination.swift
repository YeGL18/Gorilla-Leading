import Foundation
import SwiftUI
import CoreLocation
import MapKit

struct Destination: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    let coordinate: CLLocationCoordinate2D
    var colorHex: String
    var locality: String?  // 城市/地區名（用於篩選）

    // 路线相关信息
    var drivingDistance: Double? // 米
    var drivingTime: Double? // 秒

    static func == (lhs: Destination, rhs: Destination) -> Bool {
        lhs.id == rhs.id
    }

    enum CodingKeys: String, CodingKey {
        case id, name, latitude, longitude, colorHex, locality, drivingDistance, drivingTime
    }

    init(id: UUID = UUID(), name: String, coordinate: CLLocationCoordinate2D, colorHex: String, locality: String? = nil) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.colorHex = colorHex
        self.locality = locality
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        let lat = try container.decode(Double.self, forKey: .latitude)
        let lon = try container.decode(Double.self, forKey: .longitude)
        coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        drivingDistance = try container.decodeIfPresent(Double.self, forKey: .drivingDistance)
        drivingTime = try container.decodeIfPresent(Double.self, forKey: .drivingTime)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(coordinate.latitude, forKey: .latitude)
        try container.encode(coordinate.longitude, forKey: .longitude)
        try container.encode(colorHex, forKey: .colorHex)
        try container.encodeIfPresent(drivingDistance, forKey: .drivingDistance)
        try container.encodeIfPresent(drivingTime, forKey: .drivingTime)
    }
    
    var color: Color {
        Color(hex: colorHex) ?? .blue
    }
    
    // 格式化距离显示
    var formattedDistance: String? {
        guard let distance = drivingDistance else { return nil }
        if distance < 1000 {
            return String(format: "%.0f m", distance)
        } else {
            return String(format: "%.1f km", distance / 1000)
        }
    }
    
    // 格式化时间显示
    var formattedTime: String? {
        guard let time = drivingTime else { return nil }
        let minutes = time / 60
        if minutes < 60 {
            return String(format: "%.0f min", minutes)
        } else {
            let hours = Int(minutes / 60)
            let mins = Int(minutes.truncatingRemainder(dividingBy: 60))
            return "\(hours)h \(mins)m"
        }
    }
}

class DestinationManager: ObservableObject {
    nonisolated(unsafe) static let shared = DestinationManager()

    @Published var destinations: [Destination] = []
    @Published var selectedDestination: Destination? {
        didSet { if oldValue?.id != selectedDestination?.id { invalidateRoute() } }
    }

    private let destinationsKey = "saved_destinations"
    private var hasLoaded = false

    struct RouteResult {
        let route: MKRoute
        let source: CLLocationCoordinate2D
        let calculatedAt: Date
    }
    private var routeRequest: MKDirections?
    private var routeToken: UUID?
    private var routeTarget: CLLocationCoordinate2D?
    private var routeAttemptAt: Date?
    private var routeResult: RouteResult?
    private var routeCompletions: [(RouteResult?) -> Void] = []
    private var routeUpdatesActive = true
    private let calculateDirections: (MKDirections, @escaping (MKDirections.Response?, Error?) -> Void) -> Void

    init(calculateDirections: @escaping (MKDirections, @escaping (MKDirections.Response?, Error?) -> Void) -> Void = {
        $0.calculate(completionHandler: $1)
    }) {
        self.calculateDirections = calculateDirections
    }

    func prepare() {
        guard !hasLoaded, UIApplication.shared.isProtectedDataAvailable else { return }
        loadDestinations()
        hasLoaded = true
    }

    func reloadAfterRestore() {
        invalidateRoute()
        destinations = []
        selectedDestination = nil
        loadDestinations()
    }

    // MARK: - Trip Predictor integration helpers

    @discardableResult
    @MainActor
    func findOrCreateDestination(for place: PlaceInfo) -> Destination {
        let coord = place.coordinate
        // 1. exact name match
        if let m = destinations.first(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == place.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }) {
            return m
        }
        // 2. nearest within 200m and name contains the place prefix
        let nearby = destinations
            .map { ($0, CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
                .distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))) }
            .filter { $0.1 <= 200 }
            .sorted { $0.1 < $1.1 }
        if let nb = nearby.first { return nb.0 }
        // 3. create new with default ocean color
        let d = Destination(
            name: place.displayName,
            coordinate: coord,
            colorHex: "#0098FF"
        )
        addDestination(d)
        return d
    }

    @discardableResult
    @MainActor
    func applyAutoPrediction(_ prediction: PendingTripPrediction) -> Destination {
        let dest = findOrCreateDestination(for: prediction.predicted)
        selectDestination(dest)
        return dest
    }

    func addDestination(_ destination: Destination) {
        destinations.append(destination)
        saveDestinations()
    }
    
    func updateDestination(_ destination: Destination) {
        if let index = destinations.firstIndex(where: { $0.id == destination.id }) {
            destinations[index] = destination
            saveDestinations()
        }
    }
    
    func deleteDestination(_ destination: Destination) {
        destinations.removeAll { $0.id == destination.id }
        if selectedDestination?.id == destination.id {
            selectedDestination = nil
        }
        saveDestinations()
    }
    
    func selectDestination(_ destination: Destination) {
        selectedDestination = destination
        saveDestinations()
    }
    
    // 计算从当前位置到目的地的路线
    /// The phone UI owns route refreshes; background visit detection never needs them.
    func setRouteUpdatesActive(_ active: Bool) {
        guard routeUpdatesActive != active else { return }
        routeUpdatesActive = active
        if !active { invalidateRoute() }
    }

    func invalidateRoute() {
        routeRequest?.cancel()
        routeRequest = nil
        routeToken = nil
        routeTarget = nil
        routeAttemptAt = nil
        routeResult = nil
        let callbacks = routeCompletions
        routeCompletions = []
        callbacks.forEach { $0(nil) }
    }

    func calculateRoute(from source: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D,
                        completion: @escaping (Double?, Double?) -> Void) {
        // Adding a saved place is an independent, explicit lookup. It must not
        // cancel or replace the route for the currently selected destination.
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: source.wgs84ToGCJ02))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.wgs84ToGCJ02))
        request.transportType = .automobile
        request.requestsAlternateRoutes = false
        calculateDirections(MKDirections(request: request)) { response, error in
            DispatchQueue.main.async {
                let route = error == nil ? response?.routes.first : nil
                completion(route?.distance, route?.expectedTravelTime)
            }
        }
    }

    // One request serves both the ETA and the visible route. Cached timestamps
    // remain unchanged, so distance interpolation is not restarted on every fix.
    func requestRoute(from currentLocation: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D,
                      force: Bool = false, completion: @escaping (RouteResult?) -> Void) {
        guard routeUpdatesActive else { completion(nil); return }
        let sameTarget = routeTarget?.latitude == destination.latitude && routeTarget?.longitude == destination.longitude
        if !sameTarget { invalidateRoute(); routeTarget = destination }
        if routeRequest != nil {
            // Do not queue another callback for every GPS fix. Explicit route
            // actions join the one request; automatic callers reuse its last result.
            if force { routeCompletions.append(completion) }
            else { completion(routeResult) }
            return
        }
        let now = Date()
        let moved = routeResult.map {
            CLLocation(latitude: $0.source.latitude, longitude: $0.source.longitude)
                .distance(from: CLLocation(latitude: currentLocation.latitude, longitude: currentLocation.longitude))
        } ?? 0
        if !force, let attempt = routeAttemptAt,
           !RouteRefreshPolicy.shouldRequest(age: now.timeIntervalSince(attempt), moved: moved, hasResult: routeResult != nil) {
            completion(routeResult)
            return
        }
        routeAttemptAt = now
        let request = MKDirections.Request()
        // 与其他路线请求保持一致：存储的是 WGS-84，中国大陆需转 GCJ-02
        // (Consistent with the other MKDirections call sites: stored coords are
        // WGS-84; convert to GCJ-02 for mainland China — no-op elsewhere.)
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: currentLocation.wgs84ToGCJ02))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.wgs84ToGCJ02))
        request.transportType = .automobile
        
        request.requestsAlternateRoutes = false
        let directions = MKDirections(request: request)
        let token = UUID()
        routeToken = token
        routeRequest = directions
        routeCompletions = [completion]
        calculateDirections(directions) { [weak self] response, error in
            DispatchQueue.main.async {
                guard let self, self.routeToken == token else { return }
                self.routeRequest = nil
                if let route = response?.routes.first, error == nil {
                    self.routeResult = RouteResult(route: route, source: currentLocation, calculatedAt: Date())
                }
                let callbacks = self.routeCompletions
                self.routeCompletions = []
                callbacks.forEach { $0(self.routeResult) }
            }
        }
    }
    
    private func saveDestinations() {
        if let data = try? JSONEncoder().encode(destinations) {
            UserDefaults.standard.set(data, forKey: destinationsKey)
        }
        if let selected = selectedDestination,
           let selectedData = try? JSONEncoder().encode(selected.id.uuidString) {
            UserDefaults.standard.set(selectedData, forKey: "selected_destination_id")
        }
    }
    
    private func loadDestinations() {
        guard let data = UserDefaults.standard.data(forKey: destinationsKey),
              let decoded = try? JSONDecoder().decode([Destination].self, from: data) else { return }
        destinations = decoded
        
        // 加载选中的目的地
        if let selectedIdData = UserDefaults.standard.data(forKey: "selected_destination_id"),
           let selectedIdString = try? JSONDecoder().decode(String.self, from: selectedIdData),
           let selectedId = UUID(uuidString: selectedIdString),
           let selected = destinations.first(where: { $0.id == selectedId }) {
            selectedDestination = selected
        }
    }
}

enum RouteRefreshPolicy {
    static func shouldRequest(age: TimeInterval, moved: CLLocationDistance, hasResult: Bool) -> Bool {
        age >= (hasResult ? 30 : 10) || (hasResult && age >= 10 && moved >= 250)
    }
}
