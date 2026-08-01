import Foundation
import CoreLocation

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private(set) var manager = CLLocationManager()
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
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var gpsQuality: GPSQuality = .unknown
    @Published var currentAddress: String = ""
    @Published var visits: [VisitRecord] = []
    @Published var lastLocation: CLLocation?
    @Published var heading: Double = 0

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
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
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
            self.lastLocation = location
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
                    departureDate: (record.departureDate != nil && record.departureDate!.timeIntervalSince(record.arrivalDate) < 7 * 24 * 3600) ? record.departureDate : nil,
                    transportType: record.transportType
                )
                self.visits.insert(updated, at: 0)
                self.visits.sort { $0.arrivalDate > $1.arrivalDate }
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
        }
    }

    private func loadVisits() {
        guard let data = UserDefaults.standard.data(forKey: visitsKey),
              let decoded = try? JSONDecoder().decode([VisitRecord].self, from: data) else { return }
        visits = decoded.sorted { $0.arrivalDate > $1.arrivalDate }
    }

    func clearVisits() {
        visits = []
        UserDefaults.standard.removeObject(forKey: visitsKey)
    }
}
