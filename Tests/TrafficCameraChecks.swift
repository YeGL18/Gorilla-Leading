import Foundation
import CoreLocation

@main enum CameraChecks {
    static func main() {
        struct Catalog: Decodable { let cameras: [TrafficCamera] }
        let catalog = try! JSONDecoder().decode(Catalog.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        precondition(!catalog.cameras.filter { $0.roadSpeedLimitKmh != nil }.isEmpty)
        let camera = TrafficCamera(id: "test", kind: "sec", name: "測試", english: "ROAD (NORTHBOUND)",
                                   latitude: 22.3, longitude: 114.17)
        let now = Date()
        precondition(camera.displayedSpeedLimitKmh == 50)
        precondition(catalog.cameras.allSatisfy { $0.displayedSpeedLimitKmh == ($0.roadSpeedLimitKmh ?? 50) })
        precondition(catalog.cameras.filter { $0.roadSpeedLimitKmh == nil }.allSatisfy { $0.displayedSpeedLimitKmh == 50 })
        let center = CLLocation(latitude: camera.latitude, longitude: camera.longitude)
        let inside = TrafficCamera(id: "inside", kind: "rlc", name: "", english: "",
                                   latitude: 22.317, longitude: 114.17)
        let outside = TrafficCamera(id: "outside", kind: "sec", name: "", english: "",
                                    latitude: 22.319, longitude: 114.17)
        let sites = [camera, inside, outside]
        precondition(CameraAlertSpeech.text(for: inside) == "Red-light camera ahead.")
        precondition(!CameraAlertSpeech.text(for: inside).contains("limit"))
        precondition(CameraAlertSpeech.text(for: camera) == "Speed limit is 50 kilometers per hour.")
        precondition(CameraAlertSpeech.text(for: nil).contains("80 kilometers per hour"))
        for speed in [0.0, 49, 50] {
            precondition(!CameraAlertSpeech.text(for: camera, speedKmh: speed).contains("Slow down"))
        }
        precondition(CameraAlertSpeech.text(for: camera, speedKmh: 51).hasPrefix("Slow down."))
        precondition(!CameraAlertSpeech.text(for: camera, speedKmh: 90, includeSlowDown: false).contains("Slow down"))
        precondition(CameraAlertSpeech.text(for: camera, format: .number, speedKmh: 90) == "50")
        precondition(CameraAlertSpeech.text(for: camera, format: .short) == "Speed limit is 50.")
        precondition(CameraAlertSpeech.text(for: camera, format: .beepOnly, speedKmh: 90).isEmpty)
        precondition(CameraAlertSpeech.text(for: inside, format: .beepOnly).isEmpty)
        precondition(CameraAlertSpeech.text(for: inside, format: .number) == "Red-light camera ahead.")
        precondition(CameraAlertSpeech.text(for: inside, announceRedLight: false).isEmpty)
        precondition(CameraMarkerPolicy.visible(sites, enabled: true, location: center, mode: .nearby).map(\.id) == ["test", "inside"])
        precondition(CameraMarkerPolicy.visible(sites, enabled: true, location: nil, mode: .nearby).isEmpty)
        precondition(CameraMarkerPolicy.visible(sites, enabled: false, location: center, mode: .nearby).isEmpty)
        precondition(CameraMarkerPolicy.visible(sites, enabled: false, location: nil, mode: .cameras).count == 3)
        precondition(CameraMarkerPolicy.visible(sites, enabled: true, location: center, mode: .meters).isEmpty)
        precondition(CameraMarkerPolicy.visible(sites, enabled: true, location: center, mode: .landmarks).isEmpty)
        precondition(CameraApproachPolicy.warningRadius(speed: 0) == 30)
        precondition(abs(CameraApproachPolicy.warningRadius(speed: 50 / 3.6) - 111.111) < 0.01)
        precondition(abs(CameraApproachPolicy.warningRadius(speed: 100 / 3.6) - 222.222) < 0.01)
        precondition(CameraApproachPolicy.warningRadius(speed: 50) == 300)
        print("PASS: nearby 2 km filtering, both camera types, overview isolation, disabled/no GPS, speed-based warning distances")
        func fix(_ metres: Double, _ seconds: Double, course: Double = 0, accuracy: Double = 5,
                 speed: Double = 30) -> CLLocation {
            CLLocation(coordinate: .init(latitude: 22.3 - metres / 111195, longitude: 114.17),
                       altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: 5,
                       course: course, speed: speed, timestamp: now.addingTimeInterval(seconds))
        }
        func run(_ first: CLLocation, _ second: CLLocation, driving: Bool = true) -> Bool {
            var policy = CameraApproachPolicy()
            _ = policy.update(location: first, cameras: [camera], driving: driving, now: first.timestamp)
            return policy.update(location: second, cameras: [camera], driving: driving,
                                 now: second.timestamp)?.shouldSound == true
        }
        precondition(run(fix(145, 0), fix(130, 1)))
        precondition(!run(fix(130, 0), fix(145, 1))) // Receding.
        precondition(!run(fix(-145, 0, course: 180), fix(-130, 1, course: 180))) // Opposite carriageway.
        precondition(!run(fix(145, 0, course: 180), fix(130, 1, course: 180)))
        precondition(!run(fix(145, 0), fix(130, 1), driving: false))
        precondition(!run(fix(145, 0, accuracy: 80), fix(130, 1, accuracy: 80)))
        precondition(!run(fix(145, 0, speed: 0), fix(130, 1, speed: 0)))
        precondition(!run(fix(145, 0, course: -1), fix(130, 1, course: -1)))
        precondition(!run(fix(145, 0), fix(130, 8))) // Gap cannot establish approach.
        precondition(!run(fix(145, 1), fix(130, 1))) // Duplicate timestamp.
        precondition(!run(fix(145, 2), fix(130, 1))) // Out of order.
        precondition(!run(fix(15, 0), fix(10, 1))) // Already at/past camera.
        precondition(camera.direction == 0)
        precondition(CameraApproachPolicy.angle(359, 1) == 2)
        let sideCamera = TrafficCamera(id: "side", kind: "rlc", name: "測試", english: "JUNCTION",
                                       latitude: 22.3, longitude: 114.1708)
        var sidePolicy = CameraApproachPolicy()
        _ = sidePolicy.update(location: fix(145, 0), cameras: [sideCamera], driving: true, now: now)
        precondition(sidePolicy.update(location: fix(130, 1), cameras: [sideCamera], driving: true,
                                       now: now.addingTimeInterval(1)) == nil)
        var policy = CameraApproachPolicy()
        precondition(policy.update(location: fix(145, 0), cameras: [camera], driving: true, now: now) == nil)
        precondition(policy.update(location: fix(130, 1), cameras: [camera], driving: true,
                                   now: now.addingTimeInterval(1))?.shouldSound == true)
        precondition(policy.update(location: fix(115, 2), cameras: [camera], driving: true,
                                   now: now.addingTimeInterval(2))?.shouldSound == false)
        _ = policy.update(location: fix(1000, 20), cameras: [camera], driving: true, now: now.addingTimeInterval(20))
        _ = policy.update(location: fix(145, 21), cameras: [camera], driving: true, now: now.addingTimeInterval(21))
        precondition(policy.update(location: fix(130, 22), cameras: [camera], driving: true,
                                   now: now.addingTimeInterval(22))?.shouldSound == true)
        precondition(policy.update(location: fix(120, 23), cameras: [camera], driving: true,
                                   now: now.addingTimeInterval(40)) == nil)
        print("PASS: approach, direction, motion, accuracy, stationary, stale fixes, cooldown and rearm")
    }
}
