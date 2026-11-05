import Foundation
import CoreLocation
import MapKit

@main
struct MapCameraMotionChecks {
    static func main() {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            checks += 1
        }
        let origin = CLLocationCoordinate2D(latitude: 22.3193, longitude: 114.1694)
        check(MapCameraMotion.drivingDistance == 1800, "Normal driving camera distance is 1800m")
        check(MapCameraMotion.trackingPointDownshift == 60, "Tracking point is shifted down 60pt")
        check(MapCameraMotion.meterOverviewDuration == 2.4, "Meter overview takes 2.4 seconds")
        check(MapCameraMotion.flightProgress(-1) == 0 && MapCameraMotion.flightProgress(2) == 1,
              "Flight progress clamps to its endpoints")
        check(MapCameraMotion.flightProgress(0.5) == 0.5, "Flight midpoint is centered")
        var previousProgress = 0.0
        for frame in 1...144 {
            let t = Double(frame) / 144
            let progress = MapCameraMotion.flightProgress(t)
            check(progress >= previousProgress && progress <= 1, "Flight never reverses or overshoots")
            check(abs(progress + MapCameraMotion.flightProgress(1 - t) - 1) < 1e-12,
                  "Flight accelerates and decelerates symmetrically")
            previousProgress = progress
        }
        check(MapCameraMotion.flightProgress(0.1) < 0.1 && MapCameraMotion.flightProgress(0.9) > 0.9,
              "Flight is slow at both ends, fast in the middle")
        let time = Date(timeIntervalSince1970: 1_000)
        func fix(_ coordinate: CLLocationCoordinate2D = origin, seconds: Double = 0,
                 speed: Double = 20, course: Double = 90, accuracy: Double = 5) -> CLLocation {
            CLLocation(coordinate: coordinate, altitude: 0, horizontalAccuracy: accuracy,
                       verticalAccuracy: 5, course: course, speed: speed,
                       timestamp: time.addingTimeInterval(seconds))
        }
        check(MapCameraMotion.isUsableAirportOrigin(fix(), at: time), "Fresh GPS can start the airport flight")
        check(!MapCameraMotion.isUsableAirportOrigin(fix(seconds: -31), at: time), "Old cached location cannot be a flight origin")
        check(!MapCameraMotion.isUsableAirportOrigin(fix(accuracy: 1500), at: time), "Coarse startup fixes must wait")
        check(!MapCameraMotion.isUsableAirportOrigin(fix(accuracy: -1), at: time), "Invalid accuracy cannot start a flight")
        check(!MapCameraMotion.isUsableAirportOrigin(fix(.init(latitude: 0, longitude: 0)), at: time), "Unknown origin cannot fly from the equator")
        check(!MapCameraMotion.isUsableAirportOrigin(fix(seconds: 60), at: time), "Future timestamps cannot satisfy readiness")
        var motion = MapCameraMotion()
        var mainland = MapCameraMotion()
        let raw = CLLocationCoordinate2D(latitude: 22.5431, longitude: 114.0579)
        let displayed = CLLocationCoordinate2D(latitude: 22.5405, longitude: 114.0630)
        mainland.update(fix(raw, speed: 0), displayCoordinate: displayed)
        let mapTarget = mainland.coordinate(at: time)!
        check(abs(mapTarget.latitude - displayed.latitude) < 1e-10 &&
              abs(mapTarget.longitude - displayed.longitude) < 1e-10,
              "Mainland camera uses the same display frame as annotations")
        check(mainland.sample!.coordinate.longitude == raw.longitude,
              "GPS distance calculations retain the raw coordinate")
        check(motion.coordinate(at: time) == nil, "No invented position before the first fix")
        motion.update(fix())
        var previous = origin
        for frame in 1...90 {
            let next = motion.coordinate(at: time.addingTimeInterval(Double(frame) / 60))!
            check(next.longitude > previous.longitude, "Tracking progresses between one-second GPS fixes")
            check(CLLocation(latitude: next.latitude, longitude: next.longitude)
                .distance(from: CLLocation(latitude: previous.latitude, longitude: previous.longitude)) < 0.4,
                  "No frame-sized jump while coasting")
            previous = next
        }
        let stopped = motion.coordinate(at: time.addingTimeInterval(MapCameraMotion.predictionHorizon))!
        let tunnel = motion.coordinate(at: time.addingTimeInterval(120))!
        check(abs(stopped.longitude - tunnel.longitude) < 1e-12, "Stale GPS stops rather than drifting through a tunnel")
        check(fix(stopped).distance(from: fix()) < 65.3, "Prediction remains bounded after GPS loss")
        motion.update(fix(seconds: -1))
        check(motion.sample?.timestamp == time, "Out-of-order fixes cannot rewind the target")
        motion.update(fix(seconds: 1, accuracy: -1))
        check(motion.sample?.timestamp == time, "Invalid fixes are ignored")
        motion.update(fix(seconds: 2, speed: 0))
        check(motion.coordinate(at: time.addingTimeInterval(3))!.longitude == origin.longitude,
              "A stationary vehicle does not coast")
        check(abs(MapCameraMotion.headingDelta(from: 359, to: 1) - 2) < 1e-8, "Heading takes the short route through north")
        check(abs(MapCameraMotion.headingDelta(from: 1, to: 359) + 2) < 1e-8, "Reverse north crossing also takes the short route")
        let at60 = pow(1 - MapCameraMotion.response(frameDuration: 1 / 60.0, soft: true), 60)
        let at30 = pow(1 - MapCameraMotion.response(frameDuration: 1 / 30.0, soft: true), 30)
        let responseAt120 = pow(1 - MapCameraMotion.response(frameDuration: 1 / 120.0, soft: true), 120)
        check(abs(at60 - at30) < 1e-8 && abs(at60 - responseAt120) < 1e-8,
              "Tracking response is independent of 30/60/120 Hz refresh rates")
        for meter in [
            CLLocationCoordinate2D(latitude: origin.latitude, longitude: origin.longitude + 0.001),
            CLLocationCoordinate2D(latitude: origin.latitude + 0.02, longitude: origin.longitude),
            origin
        ] {
            let rect = MapCameraMotion.overviewRect(user: origin, meter: meter)
            check(rect.contains(MKMapPoint(origin)) && rect.contains(MKMapPoint(meter)),
                  "Overview includes both the driver and the meter")
            check(rect.width > 0 && rect.height > 0, "Coincident and aligned points still produce a usable viewport")
        }

        let drivingSpeed = 50.0 / 3.6
        func routePosition(seconds: Double, jitter: Double = 0) -> CLLocationCoordinate2D {
            .init(latitude: origin.latitude,
                  longitude: origin.longitude + (drivingSpeed * seconds + jitter) / (6_371_000 * cos(origin.latitude * .pi / 180)) * 180 / .pi)
        }
        func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
            CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
        }

        // Exercise the exact camera-center function, not only the GPS prediction target.
        for soft in [false, true] {
            for fps in [30, 60, 120] {
                for interval in [1.0, 2.0] {
                    var tracker = MapCameraMotion()
                    tracker.update(fix(speed: drivingSpeed))
                    var camera = origin
                    var nextFix = interval
                    var minimumSpeed = Double.greatestFiniteMagnitude, maximumSpeed = 0.0
                    for frame in 1...(fps * 30) {
                        let seconds = Double(frame) / Double(fps)
                        if seconds >= nextFix + 0.35 {
                            tracker.update(fix(routePosition(seconds: nextFix), seconds: nextFix, speed: drivingSpeed))
                            nextFix += interval
                        }
                        let next = tracker.cameraCoordinate(from: camera, at: time.addingTimeInterval(seconds),
                                                            frameDuration: 1 / Double(fps), soft: soft)!
                        let actualSpeed = distance(camera, next) * Double(fps)
                        minimumSpeed = min(minimumSpeed, actualSpeed)
                        maximumSpeed = max(maximumSpeed, actualSpeed)
                        camera = next
                    }
                    check(abs(minimumSpeed - drivingSpeed) < 0.15 && abs(maximumSpeed - drivingSpeed) < 0.15,
                          "50 km/h camera stays at 50 km/h across delayed one/two-second GPS fixes")
                    check(maximumSpeed - minimumSpeed < 0.05,
                          "Constant driving cannot repeatedly accelerate/decelerate between fixes")
                }
            }
        }

        for soft in [false, true] {
            for fps in [30, 60, 120] {
                for initialGap in [20.0, 60.0] {
                    var tracker = MapCameraMotion()
                    tracker.update(fix(speed: drivingSpeed))
                    tracker.resetCameraVelocity()
                    var camera = routePosition(seconds: 0, jitter: -initialGap)
                    var nextFix = 1.0
                    var caughtUpAt: Double?
                    var steadyMinimumSpeed = Double.greatestFiniteMagnitude, steadyMaximumSpeed = 0.0
                    for frame in 1...(fps * 12) {
                        let seconds = Double(frame) / Double(fps)
                        if seconds >= nextFix + 0.35 {
                            tracker.update(fix(routePosition(seconds: nextFix), seconds: nextFix, speed: drivingSpeed))
                            nextFix += 1
                        }
                        let next = tracker.cameraCoordinate(from: camera, at: time.addingTimeInterval(seconds),
                                                            frameDuration: 1 / Double(fps), soft: soft)!
                        let step = distance(camera, next)
                        check(step < 1.1, "Startup acquisition remains continuous rather than jumping to the blue dot")
                        if caughtUpAt == nil && distance(next, routePosition(seconds: seconds)) <= 2 {
                            caughtUpAt = seconds
                        }
                        if seconds >= 10 {
                            steadyMinimumSpeed = min(steadyMinimumSpeed, step * Double(fps))
                            steadyMaximumSpeed = max(steadyMaximumSpeed, step * Double(fps))
                        }
                        camera = next
                    }
                    let deadline = initialGap <= 20 ? 2.5 : 5.5
                    check(caughtUpAt != nil && caughtUpAt! <= deadline,
                          "A 20/60m startup gap is recovered within 2.5/5.5 seconds")
                    check(abs(steadyMinimumSpeed - drivingSpeed) < 0.15 && abs(steadyMaximumSpeed - drivingSpeed) < 0.15,
                          "After acquisition, regular constant-speed tracking is unchanged")
                    print("Startup \(Int(initialGap))m / \(fps)fps / \(soft ? "soft" : "standard"): \(String(format: "%.2f", caughtUpAt ?? -1))s to within 2m")
                }
            }
        }

        var flight = MapCameraMotion()
        flight.update(fix(speed: drivingSpeed))
        for second in 1...4 {
            flight.update(fix(routePosition(seconds: Double(second)), seconds: Double(second), speed: drivingSpeed))
        }
        let liveFlightEnd = flight.coordinate(at: time.addingTimeInterval(4.5))!
        check(distance(liveFlightEnd, routePosition(seconds: 4.5)) < 0.1,
              "The entry flight can end at the current moving position rather than its 4.5-second-old start fix")

        var noisy = MapCameraMotion()
        noisy.update(fix(speed: drivingSpeed))
        var camera = origin, lastFrameSpeed = drivingSpeed
        for frame in 1...1200 {
            let seconds = Double(frame) / 60
            if frame % 60 == 0 {
                let jitter = frame % 120 == 0 ? 3.0 : -3.0
                noisy.update(fix(routePosition(seconds: seconds, jitter: jitter), seconds: seconds, speed: drivingSpeed))
            }
            let next = noisy.cameraCoordinate(from: camera, at: time.addingTimeInterval(seconds), frameDuration: 1 / 60, soft: true)!
            let actualSpeed = distance(camera, next) * 60
            check(abs(actualSpeed - lastFrameSpeed) < 0.5, "GPS corrections cannot introduce frame-sized velocity jumps")
            check(actualSpeed > drivingSpeed * 0.7, "Position noise cannot make a moving camera almost stop")
            camera = next
            lastFrameSpeed = actualSpeed
        }
        let lastFix = noisy.sample!.timestamp
        var settled: CLLocationCoordinate2D?
        for frame in 1...1200 {
            camera = noisy.cameraCoordinate(from: camera, at: lastFix.addingTimeInterval(Double(frame) / 60), frameDuration: 1 / 60, soft: true)!
            if frame == 900 { settled = camera }
        }
        check(distance(settled!, camera) < 0.05, "The camera itself settles after GPS loss")
        check(distance(camera, noisy.coordinate(at: lastFix.addingTimeInterval(120))!) < 0.1,
              "Stale camera stops at the bounded predicted endpoint")
        // Releasing a dragged marker must continue forward without a snap,
        // then approach the exact drop point with monotonically falling speed.
        let drop = CLLocationCoordinate2D(latitude: origin.latitude + 0.001, longitude: origin.longitude)
        var dragged = origin
        var previousStep = Double.greatestFiniteMagnitude
        for _ in 0..<60 {
            let next = ParkingMarkerMotion.advance(from: dragged, to: drop)
            let step = distance(dragged, next)
            check(step > 0 && step < previousStep, "Released marker must decelerate instead of snapping or stopping")
            check(next.latitude < drop.latitude, "Marker cannot overshoot the drop location")
            previousStep = step
            dragged = next
        }
        check(distance(dragged, drop) < 0.001, "Settling must reach the intended drop point")
        let dragAt60 = ParkingMarkerMotion.advance(from: origin, to: drop)
        let at120 = ParkingMarkerMotion.advance(from: ParkingMarkerMotion.advance(from: origin, to: drop,
                                                                                 frameDuration: 1 / 120),
                                               to: drop, frameDuration: 1 / 120)
        check(distance(dragAt60, at120) < 0.00001, "Drag response is independent of frame duration")
        print("PASS: \(checks) constant-speed camera, GPS jitter, stale fixes, heading and meter framing checks")
    }
}
