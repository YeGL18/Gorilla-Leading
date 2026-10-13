import Foundation
import CoreLocation
import MapKit

// Standalone macOS harness: the production Destination model imports iOS UI.
struct Destination {
    let id: UUID
    let name: String
    let coordinate: CLLocationCoordinate2D
}
// Route transport is covered in the native energy tests, not this notice-only harness.
@MainActor
final class DestinationManager {
    static let shared = DestinationManager()
    struct RouteResult { let route: MKRoute; let calculatedAt: Date }
    func requestRoute(from source: CLLocationCoordinate2D, to target: CLLocationCoordinate2D,
                      completion: @escaping (RouteResult?) -> Void) { completion(nil) }
}
extension CLLocationCoordinate2D {
    var wgs84ToGCJ02: CLLocationCoordinate2D { self }
}

@main
struct MeterNoticeChecks {
    @MainActor
    static func main() {
        let suite = "gorilla-meter-checks-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(MeterVehicle.privateCar.rawValue, forKey: "meterVehicle")
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message); checks += 1
        }
        let now = Date()
        let location = CLLocation(coordinate: .init(latitude: 22.3, longitude: 114.17), altitude: 0,
                                  horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: now)
        let meter = ParkingMeter(id: "1A", poleId: "1", district: "區", street: "街", streetKey: "street",
                                 latitude: 22.3, longitude: 114.17, bayType: .general, lpp: 120,
                                 operatingPeriod: "D", paymentUnit: 4, timeUnit: 15)
        let vacant = MeterStatus(isOperating: true, occupancy: "V", changedAt: "")
        let occupied = MeterStatus(isOperating: true, occupancy: "O", changedAt: "")
        let manager = ParkingMeterManager(defaults: defaults, initialMeters: [meter], initialStatuses: [meter.id: vacant], fetchedAt: now)
        check(manager.statusRefreshInterval == 60, "Existing users retain the one-minute refresh")
        defaults.set(120.0, forKey: "meterStatusRefreshInterval")
        check(manager.statusRefreshInterval == 120, "Setting changes apply immediately")
        defaults.set(0.0, forKey: "meterStatusRefreshInterval")
        check(manager.statusRefreshInterval == 30, "Invalid short intervals are clamped")
        defaults.set(1000.0, forKey: "meterStatusRefreshInterval")
        check(manager.statusRefreshInterval == 300, "Long intervals are bounded")
        defaults.removeObject(forKey: "meterStatusRefreshInterval")
        func evaluate(_ seconds: Double, nearby: [ParkingMeter] = [], target: [ParkingMeter] = [], speed: Double = 10) {
            manager.evaluateNotices(nearby: nearby, destinationMeters: target, destinationName: "學校",
                                    location: location, speed: speed, now: now.addingTimeInterval(seconds))
        }
        evaluate(0, target: [meter])
        check(manager.notice?.kind == .destination, "Destination opportunity must display")
        check(manager.notice?.count == 1, "Destination counts compatible vacancies")
        check(manager.notice?.expiresAt == now.addingTimeInterval(10), "Notice lasts ten seconds")
        manager.dismissNotice()
        evaluate(1, target: [meter])
        check(manager.notice == nil, "Cancelled destination notice must never repeat in same journey")
        evaluate(2, nearby: [meter])
        check(manager.notice?.kind == .nearby, "Nearby notice is independent of destination dismissal")
        manager.dismissNotice()
        evaluate(3, nearby: [meter])
        check(manager.notice == nil, "Nearby notice does not repeat on the same street")
        evaluate(4, nearby: [meter], speed: 0)
        evaluate(13, nearby: [meter], speed: 0)
        check(manager.notice == nil, "Stationary detection waits ten seconds")
        evaluate(14, nearby: [meter], speed: 0)
        check(manager.notice?.kind == .stationary, "Stationary notice overrides prior nearby suppression")
        manager.dismissNotice()
        evaluate(20, nearby: [meter], speed: 0)
        check(manager.notice == nil, "Stationary notice is once per stop")
        let occupiedManager = ParkingMeterManager(defaults: defaults, initialMeters: [meter], initialStatuses: [meter.id: occupied], fetchedAt: now)
        occupiedManager.evaluateNotices(nearby: [meter], destinationMeters: [], destinationName: "", location: location, speed: 0, now: now)
        occupiedManager.evaluateNotices(nearby: [meter], destinationMeters: [], destinationName: "", location: location, speed: 0, now: now.addingTimeInterval(10))
        check(occupiedManager.notice?.kind == .stationary, "Occupied bay can trigger parked-nearby payment notice")
        let uncertain = CLLocation(coordinate: location.coordinate, altitude: 0, horizontalAccuracy: 50, verticalAccuracy: 0, timestamp: now)
        let uncertainManager = ParkingMeterManager(defaults: defaults, initialMeters: [meter], initialStatuses: [meter.id: occupied], fetchedAt: now)
        uncertainManager.evaluateNotices(nearby: [meter], destinationMeters: [], destinationName: "", location: uncertain, speed: 0, now: now)
        uncertainManager.evaluateNotices(nearby: [meter], destinationMeters: [], destinationName: "", location: uncertain, speed: 0, now: now.addingTimeInterval(11))
        check(uncertainManager.notice == nil, "Inaccurate GPS cannot claim a ten-metre stop")
        defaults.set(MeterVehicle.coach.rawValue, forKey: "meterVehicle")
        let incompatible = ParkingMeterManager(defaults: defaults, initialMeters: [meter], initialStatuses: [meter.id: vacant], fetchedAt: now)
        incompatible.evaluateNotices(nearby: [meter], destinationMeters: [meter], destinationName: "", location: location, speed: 10, now: now)
        check(incompatible.notice == nil, "Incompatible vacancies are never automatically recommended")
        defaults.set(MeterVehicle.privateCar.rawValue, forKey: "meterVehicle")
        let expiring = ParkingMeterManager(defaults: defaults, initialMeters: [meter], initialStatuses: [meter.id: vacant], fetchedAt: now)
        expiring.evaluateNotices(nearby: [], destinationMeters: [meter], destinationName: "學校", location: location, speed: 10, now: now)
        expiring.tick(location: nil, speed: 0, destination: nil, now: now.addingTimeInterval(10))
        check(expiring.notice == nil, "Notice automatically expires without interaction")
        expiring.evaluateNotices(nearby: [], destinationMeters: [meter], destinationName: "學校", location: location, speed: 10, now: now.addingTimeInterval(11))
        check(expiring.notice == nil, "Timed-out destination notice must not repeat")
        let approaching = CLLocation(coordinate: .init(latitude: 22.31, longitude: 114.17), altitude: 0,
                                     horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: now)
        let destination = Destination(id: UUID(), name: "學校", coordinate: meter.coordinate)
        let cached = ParkingMeterManager(defaults: defaults, initialMeters: [meter], initialStatuses: [meter.id: vacant], fetchedAt: now)
        cached.tick(location: approaching, speed: 10, destination: destination, now: now)
        cached.updateRouteDistance(1500, destinationID: destination.id, calculatedAt: now.addingTimeInterval(-180))
        cached.tick(location: approaching, speed: 10, destination: destination, now: now)
        check(cached.notice == nil, "Reading a stale route cannot turn it into fresh destination distance")
        cached.updateRouteDistance(1500, destinationID: destination.id, calculatedAt: now)
        cached.tick(location: approaching, speed: 10, destination: destination, now: now)
        check(cached.notice?.kind == .destination, "A fresh shared route still triggers destination meter detection")
        print("PASS: \(checks) notice lifecycle, priority, vehicle and GPS checks")
    }
}
