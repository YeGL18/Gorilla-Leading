import Foundation
import simd

struct SpeedGForce: Equatable {
    let lateral: Double
    let longitudinal: Double

    var magnitude: Double { hypot(lateral, longitudinal) }
    var plotRange: Double {
        let peak = magnitude
        return peak <= 1 ? 1 : peak <= 2 ? 2 : peak <= 4 ? 4 : max(8, ceil(peak))
    }

    static func validated(lateral: Double, longitudinal: Double) -> Self? {
        guard lateral.isFinite, longitudinal.isFinite,
              abs(lateral) <= 50, abs(longitudinal) <= 50 else { return nil }
        return Self(lateral: lateral, longitudinal: longitudinal)
    }

    // Project gravity-free device acceleration onto the horizontal screen-right /
    // forward plane. No visual gain, dead zone or clamping is applied to readings.
    static func project(acceleration: SIMD3<Double>, gravity: SIMD3<Double>, rotation: Double) -> Self? {
        guard acceleration.x.isFinite, acceleration.y.isFinite, acceleration.z.isFinite,
              gravity.x.isFinite, gravity.y.isFinite, gravity.z.isFinite,
              rotation.isFinite, simd_length(gravity) > 0.5 else { return nil }
        let down = simd_normalize(gravity)
        let screenRight = SIMD3<Double>(cos(rotation), -sin(rotation), 0)
        let horizontalRight = screenRight - simd_dot(screenRight, down) * down
        guard simd_length(horizontalRight) > 0.15 else { return nil }
        let right = simd_normalize(horizontalRight)
        let forward = simd_cross(right, down)
        return validated(lateral: simd_dot(acceleration, right),
                         longitudinal: simd_dot(acceleration, forward))
    }

    func smoothed(towards next: Self, alpha: Double) -> Self {
        Self(lateral: lateral + (next.lateral - lateral) * alpha,
             longitudinal: longitudinal + (next.longitudinal - longitudinal) * alpha)
    }
}

struct SpeedGForceTrail {
    struct Sample {
        let force: SpeedGForce
        let time: TimeInterval
    }

    static let lifetime: TimeInterval = 1.2
    private(set) var samples: [Sample] = []

    mutating func append(_ force: SpeedGForce?, at time: TimeInterval) {
        guard time.isFinite, let force,
              SpeedGForce.validated(lateral: force.lateral, longitudinal: force.longitudinal) != nil else {
            samples.removeAll()
            return
        }
        if let last = samples.last, time <= last.time || time - last.time > 0.25 {
            samples.removeAll()
        }
        samples.removeAll { time - $0.time >= Self.lifetime }
        samples.append(Sample(force: force, time: time))
        if samples.count > 90 { samples.removeFirst(samples.count - 90) }
    }

    func visible(at time: TimeInterval) -> [Sample] {
        samples.filter { time >= $0.time && time - $0.time < Self.lifetime }
    }
}

struct SpeedGForceFilter {
    private var first = SpeedGForce(lateral: 0, longitudinal: 0)
    private var second = SpeedGForce(lateral: 0, longitudinal: 0)
    private var previousTime: TimeInterval?
    private var startedAt: TimeInterval?

    // Two 1.5 Hz poles suppress alternating mount/engine vibration before the
    // UI is downsampled. Sustained gentle forces retain their original scale.
    mutating func update(_ sample: SpeedGForce?, at now: TimeInterval) -> SpeedGForce? {
        guard now.isFinite, let sample,
              SpeedGForce.validated(lateral: sample.lateral, longitudinal: sample.longitudinal) != nil else {
            self = Self()
            return nil
        }
        if let previousTime, now <= previousTime { return nil }
        if let previousTime, now - previousTime > 0.25 { self = Self() }
        let dt = previousTime.map { now - $0 } ?? 0
        previousTime = now
        if startedAt == nil { startedAt = now }
        let alpha = 1 - exp(-2 * Double.pi * 1.5 * dt)
        first = first.smoothed(towards: sample, alpha: alpha)
        second = second.smoothed(towards: first, alpha: alpha)
        guard let startedAt, now - startedAt >= 0.35 else { return nil }
        return SpeedGForce(lateral: abs(second.lateral) < 0.015 ? 0 : second.lateral,
                           longitudinal: abs(second.longitudinal) < 0.015 ? 0 : second.longitudinal)
    }
}

struct SpeedCardLayout {
    let width: Double
    let height: Double
    let horizontal: Bool
    let cardHeight: Double

    init(width: Double, height: Double, partiallyOpen: Bool) {
        let landscape = width > height
        self.width = partiallyOpen && landscape ? width / 2 : width
        self.height = partiallyOpen && !landscape ? height / 2 : height
        horizontal = self.width >= 640 && self.width > self.height
        let available = max(0, self.height - 24)
        cardHeight = horizontal ? available : max(0, (available - 24) / 3)
    }
}

enum SpeedDrivingAction: String, Codable, Equatable, Sendable {
    case steady, left, right, accelerating, braking

    var title: String {
        switch self {
        case .steady: return "穩定行駛"
        case .left: return "左轉中"
        case .right: return "右轉中"
        case .accelerating: return "加速中"
        case .braking: return "煞車中"
        }
    }

    var symbol: String {
        switch self {
        case .steady: return "arrow.up"
        case .left: return "arrow.turn.up.left"
        case .right: return "arrow.turn.up.right"
        case .accelerating: return "chevron.up.2"
        case .braking: return "brakesignal"
        }
    }

    var resultTitle: String {
        switch self {
        case .steady: return "暫無動作"
        case .left: return "左轉"
        case .right: return "右轉"
        case .accelerating: return "加速"
        case .braking: return "煞車"
        }
    }

    func force(_ reading: SpeedGForce) -> Double {
        abs(signedForce(reading))
    }

    func signedForce(_ reading: SpeedGForce) -> Double {
        switch self {
        case .left, .right: return reading.lateral
        case .accelerating, .braking: return reading.longitudinal
        case .steady: return reading.magnitude
        }
    }
}

struct SpeedActionResult {
    let action: SpeedDrivingAction
    let duration: TimeInterval
    let peak: Double
    let endedAt: TimeInterval
    let score: Int
    let feedback: String
}

private struct SpeedActionSamples {
    let action: SpeedDrivingAction
    let startedAt: TimeInterval
    var peak = 0.0
    var previous: (force: Double, time: TimeInterval)?
    var jerkEnergy = 0.0
    var observedTime = 0.0

    mutating func record(_ reading: SpeedGForce, at now: TimeInterval) {
        let force = action.signedForce(reading)
        peak = max(peak, abs(force))
        if let previous {
            let dt = now - previous.time
            if dt > 0, dt <= 0.75 {
                let jerk = min(5, abs(force - previous.force) / dt)
                jerkEnergy += jerk * jerk * dt
                observedTime += dt
            }
        }
        previous = (force, now)
    }

    func result(endedAt: TimeInterval) -> SpeedActionResult? {
        let duration = max(0, endedAt - startedAt)
        guard duration >= 0.6, observedTime >= 0.4 else { return nil }
        // Local comfort heuristic, not a validated safety or insurance rating.
        // Time weighting avoids rewarding a lower sensor/telemetry sample rate.
        let intensity = min(1, max(0, (peak - 0.12) / 0.53))
        let rmsJerk = sqrt(jerkEnergy / observedTime)
        let abruptness = min(1, max(0, (rmsJerk - 0.15) / 1.35))
        let score = max(0, min(100, Int((100 - 70 * intensity - 30 * abruptness).rounded())))
        let feedback: String
        if score >= 85 { feedback = "整體平順" }
        else if abruptness > intensity { feedback = "力度變化較急促" }
        else { feedback = "力度較明顯" }
        return SpeedActionResult(action: action, duration: duration, peak: peak,
                                 endedAt: endedAt, score: score, feedback: feedback)
    }
}

struct SpeedActionTracker {
    private(set) var action: SpeedDrivingAction = .steady
    private(set) var lastCompleted: SpeedActionResult?
    private var active: SpeedActionSamples?
    private var pending: SpeedActionSamples?
    private var quietSince: TimeInterval?
    private var previous: (reading: SpeedGForce, time: TimeInterval)?

    var peak: Double { active?.peak ?? 0 }

    func isFresh(at now: TimeInterval) -> Bool {
        guard let previous else { return false }
        return now >= previous.time && now - previous.time <= 0.75
    }

    func duration(at now: TimeInterval) -> TimeInterval {
        active.map { max(0, (quietSince ?? now) - $0.startedAt) } ?? 0
    }

    func completed(at now: TimeInterval) -> SpeedActionResult? {
        guard action == .steady, let lastCompleted,
              now >= lastCompleted.endedAt, now - lastCompleted.endedAt <= 6 else { return nil }
        return lastCompleted
    }

    private mutating func finish(at now: TimeInterval) {
        if let result = active?.result(endedAt: now) { lastCompleted = result }
        active = nil
        action = .steady
        quietSince = nil
    }

    mutating func update(_ reading: SpeedGForce?, at now: TimeInterval) {
        guard now.isFinite, let reading,
              SpeedGForce.validated(lateral: reading.lateral, longitudinal: reading.longitudinal) != nil else {
            self = Self()
            return
        }
        if let previous {
            guard now > previous.time else { return }
            // Missing data/backgrounding is not a completed, scoreable maneuver.
            if now - previous.time > 0.75 { self = Self() }
        }
        let previous = self.previous
        defer { self.previous = (reading, now) }
        let strongest = max(abs(reading.lateral), abs(reading.longitudinal))
        let next: SpeedDrivingAction
        if strongest < (action == .steady ? 0.06 : 0.04) { next = .steady }
        else {
            next = abs(reading.lateral) > abs(reading.longitudinal)
                ? (reading.lateral < 0 ? .left : .right)
                : (reading.longitudinal < 0 ? .braking : .accelerating)
        }
        if next == .steady {
            pending = nil
            guard active != nil else { return }
            if quietSince == nil {
                active?.record(reading, at: now)
                quietSince = now
            } else if let quietSince, now - quietSince >= 0.3 {
                finish(at: quietSince)
            }
            return
        }
        quietSince = nil
        if next == action {
            pending = nil
            active?.record(reading, at: now)
        } else {
            if pending?.action != next {
                pending = SpeedActionSamples(action: next, startedAt: now,
                    previous: previous.map { (next.signedForce($0.reading), $0.time) })
            }
            pending?.record(reading, at: now)
            if let pending, now - pending.startedAt >= 0.2 {
                finish(at: pending.startedAt)
                active = pending
                action = next
                self.pending = nil
            }
        }
    }
}
