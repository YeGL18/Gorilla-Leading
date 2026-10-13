import Foundation
import CoreLocation
import MapKit

struct MapCameraMotion {
    static let drivingDistance: CLLocationDistance = 1800
    static let trackingPointDownshift: CGFloat = 60
    static let predictionHorizon: TimeInterval = 4
    static let meterOverviewDuration: TimeInterval = 2.4

    static func flightProgress(_ progress: Double) -> Double {
        let t = min(1, max(0, progress))
        return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }

    private static let staleGrace: TimeInterval = 2.5
    private(set) var sample: CLLocation?
    private var course: Double = 0
    private var speed: Double = 0
    private var cameraVelocity: Vector?
    private var correctionVelocity = Vector(east: 0, north: 0)
    private var isAcquiringTarget = true
    private var displayOffset = CLLocationCoordinate2D(latitude: 0, longitude: 0)

    private struct Vector {
        var east: Double
        var north: Double
    }

    mutating func update(_ location: CLLocation, displayCoordinate: CLLocationCoordinate2D? = nil) {
        guard CLLocationCoordinate2DIsValid(location.coordinate),
              location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 100,
              sample == nil || location.timestamp > sample!.timestamp else { return }
        var inferredSpeed = speed
        var inferredCourse = course
        if let previous = sample {
            let dt = location.timestamp.timeIntervalSince(previous.timestamp)
            if dt >= 0.2 && dt <= 3 {
                inferredSpeed = min(60, location.distance(from: previous) / dt)
                inferredCourse = Self.bearing(from: previous.coordinate, to: location.coordinate)
            }
        }
        speed = location.speed >= 0 ? min(60, location.speed) : inferredSpeed
        course = location.course >= 0 ? location.course : inferredCourse
        sample = location
        let display = displayCoordinate ?? location.coordinate
        displayOffset = .init(latitude: display.latitude - location.coordinate.latitude,
                              longitude: display.longitude - location.coordinate.longitude)
    }

    func coordinate(at date: Date) -> CLLocationCoordinate2D? {
        guard let sample else { return nil }
        // Normal GPS intervals must not brake the camera. Only stale fixes taper to a stop.
        let travelTime = Self.travelTime(age: date.timeIntervalSince(sample.timestamp))
        let angularDistance = speed * travelTime / 6_371_000
        let bearing = course * .pi / 180
        let lat = sample.coordinate.latitude * .pi / 180
        let lon = sample.coordinate.longitude * .pi / 180
        let projectedLat = asin(sin(lat) * cos(angularDistance) + cos(lat) * sin(angularDistance) * cos(bearing))
        let projectedLon = lon + atan2(sin(bearing) * sin(angularDistance) * cos(lat),
                                       cos(angularDistance) - sin(lat) * sin(projectedLat))
        // Convert once per fix; keep speed and distance in GPS space.
        return .init(latitude: projectedLat * 180 / .pi + displayOffset.latitude,
                     longitude: projectedLon * 180 / .pi + displayOffset.longitude)
    }

    mutating func resetCameraVelocity() {
        cameraVelocity = nil
        correctionVelocity = Vector(east: 0, north: 0)
        isAcquiringTarget = true
    }

    mutating func cameraCoordinate(from center: CLLocationCoordinate2D, at date: Date,
                                   frameDuration: Double, soft: Bool) -> CLLocationCoordinate2D? {
        guard let sample, let target = coordinate(at: date) else { return nil }
        let dt = min(0.1, max(0, frameDuration))
        let age = max(0, date.timeIntervalSince(sample.timestamp))
        let factor = max(0, min(1, (Self.predictionHorizon - age) / (Self.predictionHorizon - Self.staleGrace)))
        let radians = course * .pi / 180
        let desired = Vector(east: sin(radians) * speed * factor,
                             north: cos(radians) * speed * factor)
        let blend = 1 - exp(-dt / (soft ? 0.35 : 0.2))
        var velocity = cameraVelocity ?? desired
        velocity.east += (desired.east - velocity.east) * blend
        velocity.north += (desired.north - velocity.north) * blend
        cameraVelocity = velocity

        // Feed forward vehicle motion; position correction is separate, not a new easing per fix.
        let advanced = Self.translate(center, east: velocity.east * dt, north: velocity.north * dt)
        let error = Self.offset(from: advanced, to: target)
        if isAcquiringTarget && hypot(error.east, error.north) <= 2 {
            isAcquiringTarget = false
        }
        // Acquire quickly once; later GPS noise must not re-enable the faster correction.
        let acquiring = isAcquiringTarget && age <= Self.staleGrace
        let correctionTime = acquiring ? (soft ? 0.5 : 0.35) : (soft ? 1.2 : 0.8)
        let east = error.east / correctionTime, north = error.north / correctionTime
        let length = hypot(east, north)
        let limit = acquiring ? max(15, speed) : max(5, speed * 0.35)
        let scale = length > limit && length > 0 ? limit / length : 1
        let correctionBlend = 1 - exp(-dt / (correctionTime / 4))
        correctionVelocity.east += (east * scale - correctionVelocity.east) * correctionBlend
        correctionVelocity.north += (north * scale - correctionVelocity.north) * correctionBlend
        return Self.translate(advanced, east: correctionVelocity.east * dt, north: correctionVelocity.north * dt)
    }

    private static func travelTime(age: Double) -> Double {
        let age = max(0, age)
        let taperDuration = predictionHorizon - staleGrace
        let tail = min(taperDuration, max(0, age - staleGrace))
        return min(age, staleGrace) + tail - tail * tail / (2 * taperDuration)
    }

    private static func translate(_ coordinate: CLLocationCoordinate2D, east: Double, north: Double) -> CLLocationCoordinate2D {
        let latitude = coordinate.latitude + north / 6_371_000 * 180 / .pi
        let longitude = coordinate.longitude + east / (6_371_000 * cos(coordinate.latitude * .pi / 180)) * 180 / .pi
        return .init(latitude: latitude, longitude: longitude)
    }

    private static func offset(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Vector {
        let radians = Double.pi / 180
        return Vector(east: (to.longitude - from.longitude) * radians * 6_371_000 * cos(from.latitude * radians),
                      north: (to.latitude - from.latitude) * radians * 6_371_000)
    }

    static func response(frameDuration: Double, soft: Bool) -> Double {
        1 - exp(-min(0.1, max(0, frameDuration)) / (soft ? 0.28 : 0.16))
    }

    static func headingDelta(from: Double, to: Double) -> Double {
        atan2(sin((to - from) * .pi / 180), cos((to - from) * .pi / 180)) * 180 / .pi
    }

    static func overviewRect(user: CLLocationCoordinate2D, meter: CLLocationCoordinate2D) -> MKMapRect {
        let a = MKMapPoint(user), b = MKMapPoint(meter)
        let padding = 100 / MKMetersPerMapPointAtLatitude(user.latitude)
        return MKMapRect(x: min(a.x, b.x), y: min(a.y, b.y),
                         width: abs(a.x - b.x), height: abs(a.y - b.y))
            .insetBy(dx: -padding, dy: -padding)
    }

    private static func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let a = from.latitude * .pi / 180, b = to.latitude * .pi / 180
        let delta = (to.longitude - from.longitude) * .pi / 180
        return atan2(sin(delta) * cos(b), cos(a) * sin(b) - sin(a) * cos(b) * cos(delta)) * 180 / .pi
    }
}

/// Same exponential response while held and after release; speed falls with distance.
enum ParkingMarkerMotion {
    static func advance(from current: CLLocationCoordinate2D, to target: CLLocationCoordinate2D,
                        frameDuration: TimeInterval = 1.0 / 60.0) -> CLLocationCoordinate2D {
        let response = 1 - pow(1 - 0.18, max(0, frameDuration) * 60)
        return CLLocationCoordinate2D(
            latitude: current.latitude + (target.latitude - current.latitude) * response,
            longitude: current.longitude + (target.longitude - current.longitude) * response)
    }
}
