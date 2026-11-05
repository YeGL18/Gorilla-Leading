import Foundation
import CoreLocation

@main
struct ParkingAltitudeChecks {
    static let start = Date(timeIntervalSince1970: 1_780_000_000)
    static func sample(_ second: Double, _ altitude: Double, speed: Double = 0) -> BarometerSample {
        BarometerSample(timestamp: start.addingTimeInterval(second), relativeAltitude: altitude,
                        pressure: 100, speedKmh: speed)
    }

    static func main() throws {
        precondition(ParkingCaptureEndPolicy.decision(age: 89, stableAge: 89, hasStableCandidate: true, stationaryEvidence: true, manual: false) == .keepSampling,
                     "A short gate stop must preserve the floor reference")
        precondition(ParkingCaptureEndPolicy.decision(age: 120, stableAge: 90, hasStableCandidate: true, stationaryEvidence: true, manual: false) == .finishStableStop,
                     "A long stable stop can freeze its result without waiting indefinitely for CLVisit")
        precondition(ParkingCaptureEndPolicy.decision(age: 120, stableAge: 90, hasStableCandidate: false, stationaryEvidence: true, manual: false) == .keepSampling)
        precondition(ParkingCaptureEndPolicy.decision(age: 120, stableAge: 90, hasStableCandidate: true, stationaryEvidence: false, manual: false) == .keepSampling)
        precondition(ParkingCaptureEndPolicy.decision(age: 900, stableAge: 0, hasStableCandidate: false, stationaryEvidence: false, manual: false) == .timeout,
                     "Unresolved sampling has a finite lifetime and cannot invent a floor")
        precondition(ParkingCaptureEndPolicy.decision(age: 1000, stableAge: 900, hasStableCandidate: true, stationaryEvidence: true, manual: true) == .keepSampling,
                     "An explicit manual capture remains user-controlled")
        var capture = ParkingAltitudeCapture()
        for t in 0...5 { precondition(!capture.append(sample(Double(t), 0)), "Five seconds must keep sampling") }
        precondition(capture.append(sample(6, 0)), "Five plus one stable seconds may ask, not stop the sensor")
        precondition(!capture.append(sample(6, 0)), "Repeated sensor event must not advance time")

        var prompt = ParkingStopConfirmation()
        prompt.update(stableStop: true, at: start.addingTimeInterval(10))
        let firstPrompt = prompt.promptID
        precondition(firstPrompt != nil)
        prompt.update(stableStop: true, at: start.addingTimeInterval(19))
        precondition(prompt.promptID == firstPrompt, "Never ask more often than every ten seconds")
        prompt.update(stableStop: true, at: start.addingTimeInterval(20))
        precondition(prompt.promptID == firstPrompt, "Keep the prompt stable so its automatic confirmation can complete")
        prompt.deferPrompt(at: start.addingTimeInterval(21))
        precondition(prompt.promptID == nil, "Not parked dismisses only the question")
        prompt.update(stableStop: false, at: start.addingTimeInterval(22))
        prompt.update(stableStop: true, at: start.addingTimeInterval(30))
        precondition(prompt.promptID == nil, "Height noise must not bypass the user's ten-second deferral")
        prompt.update(stableStop: true, at: start.addingTimeInterval(31))
        precondition(prompt.promptID != nil)
        prompt.update(stableStop: false, isStopped: false, at: start.addingTimeInterval(32))
        precondition(prompt.promptID == nil && prompt.nextPromptAt == nil, "Resuming driving dismisses the question")

        var longGate = ParkingAltitudeCapture()
        for t in 0...40 { _ = longGate.append(sample(Double(t), 0)) }
        precondition(longGate.samples.count == 41 && longGate.referenceAltitude == 0,
                     "Waiting at a gate must keep the same capture and reference")
        precondition(longGate.resumedAfterBriefStop(speed: 3, at: start.addingTimeInterval(41)))
        _ = longGate.append(sample(41, -0.1, speed: 3))
        _ = longGate.append(sample(42, -2, speed: 5))
        precondition(longGate.samples.count == 43 && longGate.referenceAltitude == 0,
                     "Passing the gate must preserve the continuous curve")

        var gate = ParkingAltitudeCapture()
        for t in 0...5 { precondition(!gate.append(sample(Double(t), 0))) }
        precondition(gate.resumedAfterBriefStop(speed: 3, at: start.addingTimeInterval(9)))
        precondition(!gate.resumedAfterBriefStop(speed: 0, at: start.addingTimeInterval(9)))
        precondition(!gate.append(sample(9, 0, speed: 3)))
        for t in 10...15 { precondition(!gate.append(sample(Double(t), 0))) }
        precondition(gate.append(sample(16, 0)), "Resuming at a gate must restart the stopped clock")

        var unstable = ParkingAltitudeCapture()
        for t in 0...20 {
            precondition(!unstable.append(sample(Double(t), Double(t % 2))), "Unstable height must not freeze")
        }

        var staleGPS = ParkingAltitudeCapture()
        for t in 0...20 { precondition(!staleGPS.append(sample(Double(t), 0, speed: -1))) }
        var motionCorroborated = ParkingAltitudeCapture()
        for t in 0...5 { precondition(!motionCorroborated.append(sample(Double(t), 0, speed: -1), stationaryEvidence: true)) }
        precondition(motionCorroborated.append(sample(6, 0, speed: -1), stationaryEvidence: true))

        var gap = ParkingAltitudeCapture()
        precondition(!gap.append(sample(0, 0)))
        precondition(!gap.append(sample(20, 0)), "A data gap is not twenty seconds of stopped evidence")
        precondition(gap.hasSamplingGap, "A later stable stop cannot erase missing ramp samples")

        var descent = ParkingAltitudeCapture()
        for t in 0...2 { _ = descent.append(sample(Double(t), 0, speed: 12)) }
        for t in 3...11 { _ = descent.append(sample(Double(t), -Double(t - 2), speed: 5)) }
        for t in 12...17 { precondition(!descent.append(sample(Double(t), -9))) }
        precondition(descent.append(sample(18, -9)))
        precondition(descent.referenceAltitude == 0)
        precondition(descent.finalAltitude == -9, "Do not subtract the parking height from itself")

        var result = ParkingAltitudeResult(id: UUID(), startedAt: start, stoppedAt: start.addingTimeInterval(22),
            arrivalDate: start.addingTimeInterval(12), latitude: 22.3, longitude: 114.2,
            referenceAltitude: 0, finalAltitude: -9, pressure: 100, sampleCount: 23)
        result.selectFloor(-3, confirmedByUser: false)
        precondition(result.selectedFloor == -3 && !result.userConfirmed, "Auto tick must not train")
        result.selectFloor(-4, confirmedByUser: true)
        result.selectFloor(-4, confirmedByUser: false)
        precondition(result.selectedFloor == -4 && result.userConfirmed, "A change saves before tick and survives auto tick")
        let decoded = try JSONDecoder().decode(ParkingAltitudeResult.self, from: JSONEncoder().encode(result))
        precondition(decoded == result, "Frozen selection must survive restart")
        let coordinate = CLLocationCoordinate2D(latitude: 22.3, longitude: 114.2)
        precondition(result.matches(arrival: start.addingTimeInterval(12), coordinate: coordinate))
        precondition(!result.matches(arrival: start.addingTimeInterval(-3600), coordinate: coordinate), "Never overwrite an old parking point")
        precondition(!result.matches(arrival: start.addingTimeInterval(12), coordinate: CLLocationCoordinate2D(latitude: 22.4, longitude: 114.2)))
        print("Parking altitude checks passed: continuous gate capture, repeated/deferred prompts, movement reset, stability, stale GPS and saved floor selection")
    }
}
