import Foundation
import CoreLocation

@main
struct ParkingSessionChecks {
    static let base = Date(timeIntervalSince1970: 1_780_000_000)
    static let coordinate = CLLocationCoordinate2D(latitude: 22.3, longitude: 114.2)

    static func advance(_ second: Int) {
        TestClock.now = base.addingTimeInterval(Double(second))
        TestClock.uptime = 100_000 + Double(second)
    }

    static func drain() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }

    static func emit(_ manager: BarometerSessionManager, second: Int, altitude: Double, speed: Double) {
        advance(second)
        manager.updateDriving(speed: speed, timestamp: TestClock.now, coordinate: coordinate)
        CMAltimeter.latest.emit(altitude)
        drain()
    }

    static func main() {
        let suite = CommandLine.arguments[1]
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let manager = BarometerSessionManager()
        let hardware = CMAltimeter.latest!
        manager.updateMotion(CMMotionActivity())
        manager.updateDriving(speed: 30, timestamp: TestClock.now, coordinate: coordinate)
        precondition(hardware.starts == 0, "Normal driving must not start the barometer")
        for t in 1...3 { emit(manager, second: t, altitude: 0, speed: 10) }
        for t in 4...12 { emit(manager, second: t, altitude: -Double(t - 3), speed: 5) }
        let captureID = manager.captureID!
        for t in 13...23 { emit(manager, second: t, altitude: -9, speed: 0) }
        let firstPrompt = manager.stopConfirmationID!
        precondition(manager.isUpdating && manager.completedResult == nil && hardware.stops == 0,
                     "Ten seconds only asks: the real manager must not stop the hardware")
        manager.deferParkingConfirmation(captureID: captureID, promptID: firstPrompt)
        for t in 24...32 { emit(manager, second: t, altitude: -9, speed: 0) }
        precondition(manager.stopConfirmationID == nil && hardware.starts == 1 && hardware.stops == 0)
        emit(manager, second: 33, altitude: -9, speed: 0)
        let secondPrompt = manager.stopConfirmationID!
        for t in 34...44 { emit(manager, second: t, altitude: -9, speed: 0) }
        precondition(manager.stopConfirmationID != secondPrompt)
        precondition(manager.isUpdating && manager.samples.count == 44 && hardware.stops == 0)
        let stalePrompt = manager.stopConfirmationID!
        emit(manager, second: 45, altitude: -10, speed: 3)
        precondition(manager.stopConfirmationID == nil && manager.captureID == captureID)
        precondition(hardware.starts == 1 && hardware.stops == 0, "Passing a long gate must not restart the sensor")
        precondition(!manager.confirmParking(captureID: captureID, promptID: stalePrompt), "Stale question cannot stop a moving car")
        emit(manager, second: 46, altitude: -12, speed: 5)
        for t in 47...57 { emit(manager, second: t, altitude: -12, speed: 0) }
        precondition(manager.confirmParking(captureID: captureID, promptID: manager.stopConfirmationID!))
        precondition(!manager.isUpdating && hardware.stops == 1 && hardware.starts == 1)
        precondition(manager.completedResult?.deltaMeters == -12 && manager.samples.count == 57)
        emit(manager, second: 58, altitude: 6, speed: 0)
        precondition(manager.samples.count == 57 && manager.completedResult?.finalAltitude == -12,
                     "Queued updates and elevator movement cannot alter a frozen parking floor")
        manager.setFloor(-4, userConfirmed: true, captureID: captureID)
        precondition(manager.result(for: base.addingTimeInterval(47), coordinate: coordinate)?.selectedFloor == -4)
        advance(60)
        manager.updateDriving(speed: 30, timestamp: TestClock.now, coordinate: coordinate)
        precondition(manager.result(for: base.addingTimeInterval(47), coordinate: coordinate)?.selectedFloor == -4,
                     "Driving away must not erase a confirmed capture before a delayed visit arrives")
        print("Parking session checks passed: one continuous hardware session, repeated prompts, defer, resume, explicit stop and frozen floor")
    }
}
