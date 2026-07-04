import Foundation
import CoreLocation

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var recentQualities: [GPSQuality] = []
    private let requiredSamples = 5
    private var lastGeocodeLocation: CLLocation?

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
            guard let departure = departureDate else { return "ongoing" }
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
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var gpsQuality: GPSQuality = .unknown
    @Published var currentAddress: String = ""
    @Published var visits: [VisitRecord] = []

    private let visitsKey = "visit_records"

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        manager.startMonitoringVisits()
        loadVisits()
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
            if location.speed >= 0 {
                self.speed = location.speed * 3.6
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
        let transport: String
        switch visit.departureDate.timeIntervalSince(visit.arrivalDate) {
        case ..<120:
            transport = "Passing"
        default:
            switch Int.random(in: 0...4) {
            case 0: transport = "Walking"
            case 1: transport = "Driving"
            case 2: transport = "Train"
            case 3: transport = "Airplane"
            default: transport = "Cycling"
            }
        }

        let record = VisitRecord(
            id: UUID(),
            address: "",
            latitude: visit.coordinate.latitude,
            longitude: visit.coordinate.longitude,
            arrivalDate: visit.arrivalDate,
            departureDate: visit.departureDate,
            transportType: transport
        )

        let location = CLLocation(latitude: visit.coordinate.latitude, longitude: visit.coordinate.longitude)
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let self = self else { return }
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
                var updated = record
                updated = VisitRecord(
                    id: record.id,
                    address: addr.isEmpty ? "Unknown" : addr,
                    latitude: record.latitude,
                    longitude: record.longitude,
                    arrivalDate: record.arrivalDate,
                    departureDate: record.departureDate,
                    transportType: record.transportType
                )
                self.visits.insert(updated, at: 0)
                self.saveVisits()
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

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
                self.gpsQuality = .unknown
            } else {
                self.gpsQuality = .bad
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }

    private func saveVisits() {
        if let data = try? JSONEncoder().encode(visits) {
            UserDefaults.standard.set(data, forKey: visitsKey)
        }
    }

    private func loadVisits() {
        guard let data = UserDefaults.standard.data(forKey: visitsKey),
              let decoded = try? JSONDecoder().decode([VisitRecord].self, from: data) else { return }
        visits = decoded
    }
}
