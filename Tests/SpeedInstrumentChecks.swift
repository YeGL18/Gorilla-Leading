import Foundation

@main
struct SpeedInstrumentChecks {
    static func main() {
        func near(_ value: Double, _ expected: Double) { precondition(abs(value - expected) < 0.000001) }
        precondition(SpeedDrivingAction.accelerating.symbol == "chevron.up.2")
        precondition(SpeedDrivingAction.braking.symbol == "brakesignal")
        var trail = SpeedGForceTrail()
        for i in 0...180 {
            trail.append(SpeedGForce(lateral: Double(i) / 180, longitudinal: 0.1), at: Double(i) / 120)
        }
        precondition(trail.samples.count <= 90)
        precondition(!trail.visible(at: 1.6).isEmpty)
        precondition(trail.visible(at: 3).isEmpty)
        trail.append(nil, at: 1.7)
        precondition(trail.samples.isEmpty)
        trail.append(SpeedGForce(lateral: 0.2, longitudinal: 0), at: 2)
        trail.append(SpeedGForce(lateral: 0.3, longitudinal: 0), at: 3)
        precondition(trail.samples.count == 1)
        trail.append(SpeedGForce(lateral: .nan, longitudinal: 0), at: 3.1)
        precondition(trail.samples.isEmpty)
        let upright = SpeedGForce.project(acceleration: SIMD3(0.25, 0.8, -0.5), gravity: SIMD3(0, -1, 0), rotation: 0)!
        near(upright.lateral, 0.25)
        near(upright.longitudinal, 0.5)
        let flat = SpeedGForce.project(acceleration: SIMD3(0.25, 0.5, 0.8), gravity: SIMD3(0, 0, -1), rotation: 0)!
        near(flat.lateral, upright.lateral)
        near(flat.longitudinal, upright.longitudinal)
        let left = SpeedGForce.project(acceleration: SIMD3(-0.8, -0.25, -0.5), gravity: SIMD3(-1, 0, 0), rotation: .pi / 2)!
        let right = SpeedGForce.project(acceleration: SIMD3(0.8, 0.25, -0.5), gravity: SIMD3(1, 0, 0), rotation: -.pi / 2)!
        near(left.lateral, 0.25); near(right.lateral, 0.25)
        near(left.longitudinal, 0.5); near(right.longitudinal, 0.5)
        precondition(SpeedGForce.project(acceleration: SIMD3(0, 0, 0), gravity: SIMD3(0, 0, 0), rotation: 0) == nil)
        precondition(SpeedGForce.project(acceleration: SIMD3(0, 0, 0), gravity: SIMD3(1, 0, 0), rotation: 0) == nil)
        precondition(SpeedGForce.validated(lateral: .nan, longitudinal: 0) == nil)
        precondition(SpeedGForce.validated(lateral: 0, longitudinal: .infinity) == nil)
        precondition(SpeedGForce.validated(lateral: 0, longitudinal: 51) == nil)
        near(SpeedGForce(lateral: 3, longitudinal: 4).magnitude, 5)
        precondition(SpeedGForce(lateral: 3, longitudinal: 4).plotRange >= 5)
        precondition(SpeedGForce(lateral: 0.9, longitudinal: 0.9).plotRange >= hypot(0.9, 0.9))
        near(SpeedGForce(lateral: 0, longitudinal: 0).smoothed(towards: upright, alpha: 0.2).lateral, 0.05)
        // Exercise the sensor filter before the same 30 Hz publication used by the UI.
        for rate in [100.0, 120.0] {
            for frequency in [5.0, 10, 20, 30, 35, 49] {
                var filter = SpeedGForceFilter()
                var tracker = SpeedActionTracker()
                var maxResidual = 0.0
                var lastPublished = -1.0
                for i in 0...Int(rate * 8) {
                    let t = Double(i) / rate
                    let vibration = SpeedGForce(lateral: 0.12 * cos(2 * .pi * frequency * t),
                        longitudinal: 0.12 * sin(2 * .pi * frequency * t))
                    let output = filter.update(vibration, at: t)
                    if t - lastPublished >= 1 / 30 - 0.001 {
                        lastPublished = t
                        tracker.update(output, at: t)
                        precondition(tracker.action == .steady && tracker.lastCompleted == nil)
                    }
                    if t > 1, let output { maxResidual = max(maxResidual, output.magnitude) }
                }
                precondition(maxResidual < 0.015)
            }
        }
        var impulseFilter = SpeedGForceFilter()
        var impulseTracker = SpeedActionTracker()
        for i in 0...480 {
            let t = Double(i) / 120
            let output = impulseFilter.update(SpeedGForce(lateral: (120..<130).contains(i) ? 0.12 : 0,
                                                          longitudinal: 0), at: t)
            if i % 4 == 0 { impulseTracker.update(output, at: t) }
            precondition(impulseTracker.action == .steady && impulseTracker.lastCompleted == nil)
        }
        for (force, expected) in [(SpeedGForce(lateral: -0.08, longitudinal: 0), SpeedDrivingAction.left),
                                  (SpeedGForce(lateral: 0.08, longitudinal: 0), .right),
                                  (SpeedGForce(lateral: 0, longitudinal: 0.08), .accelerating),
                                  (SpeedGForce(lateral: 0, longitudinal: -0.08), .braking)] {
            var filter = SpeedGForceFilter()
            var tracker = SpeedActionTracker()
            var last: SpeedGForce?
            for i in 0...960 {
                let t = Double(i) / 120
                let active = t >= 1 && t < 5
                let output = filter.update(SpeedGForce(
                    lateral: (active ? force.lateral : 0) + 0.12 * sin(2 * .pi * 23 * t),
                    longitudinal: (active ? force.longitudinal : 0) + 0.12 * cos(2 * .pi * 31 * t)), at: t)
                if i % 4 == 0 { tracker.update(output, at: t) }
                if t == 2 {
                    precondition(tracker.action == expected)
                    precondition(abs(output!.lateral - force.lateral) < 0.005)
                    precondition(abs(output!.longitudinal - force.longitudinal) < 0.005)
                }
                last = output
            }
            precondition(tracker.lastCompleted?.action == expected)
            precondition(tracker.action == .steady)
            near(last!.magnitude, 0)
        }
        var filter = SpeedGForceFilter()
        for i in 0...240 {
            _ = filter.update(SpeedGForce(lateral: 0.3, longitudinal: 0), at: Double(i) / 120)
        }
        precondition(filter.update(SpeedGForce(lateral: 0, longitudinal: 0), at: 4) == nil)
        precondition(filter.update(SpeedGForce(lateral: .nan, longitudinal: 0), at: 4.1) == nil)
        for i in 0...120 {
            let output = filter.update(SpeedGForce(lateral: 0, longitudinal: 0), at: 5 + Double(i) / 120)
            if let output { near(output.magnitude, 0) }
        }
        for (width, height) in [(402.0, 740.0), (834, 1100), (720, 960)] {
            let layout = SpeedCardLayout(width: width, height: height, partiallyOpen: false)
            precondition(!layout.horizontal && layout.cardHeight > 0)
            near(layout.cardHeight * 3 + 24 + 24, layout.height)
        }
        for (width, height) in [(740.0, 350.0), (1194, 760), (1300, 780)] {
            precondition(SpeedCardLayout(width: width, height: height, partiallyOpen: false).horizontal)
        }
        let top = SpeedCardLayout(width: 720, height: 960, partiallyOpen: true)
        near(top.height, 480); near(top.width, 720)
        let leading = SpeedCardLayout(width: 1300, height: 780, partiallyOpen: true)
        near(leading.width, 650); near(leading.height, 780)
        precondition(!leading.horizontal)
        for (width, height, half) in [(402.0, 370.0, false), (402, 740, true), (720, 960, true), (740, 350, false)] {
            let layout = SpeedCardLayout(width: width, height: height, partiallyOpen: half)
            let contentHeight = layout.horizontal ? layout.cardHeight : layout.cardHeight * 3 + 24
            near(contentHeight + 24, layout.height)
        }
        var action = SpeedActionTracker()
        let leftTurn = SpeedGForce(lateral: -0.3, longitudinal: 0.02)
        action.update(leftTurn, at: 10)
        action.update(leftTurn, at: 10.1)
        precondition(action.action == .steady)
        action.update(leftTurn, at: 10.21)
        precondition(action.action == .left)
        near(action.duration(at: 10.4), 0.4)
        action.update(SpeedGForce(lateral: -0.43, longitudinal: 0), at: 10.4)
        near(action.peak, 0.43)
        action.update(leftTurn, at: 10.5)
        near(action.peak, 0.43)
        action.update(SpeedGForce(lateral: 0.4, longitudinal: 0), at: 11)
        action.update(SpeedGForce(lateral: 0.4, longitudinal: 0), at: 11.3)
        precondition(action.action == .right)
        near(action.peak, 0.4)
        near(action.duration(at: 11.5), 0.5)
        precondition(action.lastCompleted?.action == .left)
        precondition(action.completed(at: 11.5) == nil)
        action.update(nil, at: 11.6)
        near(action.peak, 0); near(action.duration(at: 12), 0)
        precondition(action.lastCompleted == nil)
        for (force, expected) in [(SpeedGForce(lateral: 0.01, longitudinal: 0.5), SpeedDrivingAction.accelerating),
                                  (SpeedGForce(lateral: 0.01, longitudinal: -0.5), .braking)] {
            action = SpeedActionTracker()
            action.update(force, at: 20); action.update(force, at: 20.3)
            precondition(action.action == expected)
            action.update(SpeedGForce(lateral: 0.01, longitudinal: 0.01), at: 20.7)
            precondition(action.action == expected)
            action.update(SpeedGForce(lateral: 0.01, longitudinal: 0.01), at: 21.05)
            precondition(action.action == .steady)
            near(action.peak, 0)
            precondition(action.lastCompleted?.action == expected)
            near(action.lastCompleted!.duration, 0.7)
            precondition(action.completed(at: 21.1) != nil)
            precondition(action.completed(at: 27) == nil)
        }
        func maneuver(peak: Double, abrupt: Bool, step: Double) -> SpeedActionTracker {
            var tracker = SpeedActionTracker()
            for i in 0...Int(4.4 / step) {
                let t = Double(i) * step
                let factor = abrupt ? (t >= 0.5 && t < 2.5 ? 1.0 : 0.0)
                    : min(1, max(0, t - 0.5), max(0, 3.5 - t))
                tracker.update(SpeedGForce(lateral: 0, longitudinal: -peak * factor), at: t)
            }
            return tracker
        }
        let smooth = maneuver(peak: 0.2, abrupt: false, step: 0.1)
        let abrupt = maneuver(peak: 0.2, abrupt: true, step: 0.1)
        let strong = maneuver(peak: 0.6, abrupt: false, step: 0.1)
        precondition(smooth.lastCompleted!.score > abrupt.lastCompleted!.score)
        precondition(smooth.lastCompleted!.score > strong.lastCompleted!.score)
        let fast = maneuver(peak: 0.2, abrupt: false, step: 0.02)
        precondition(abs(smooth.lastCompleted!.score - fast.lastCompleted!.score) <= 3)
        for result in [smooth, abrupt, strong, fast].compactMap(\.lastCompleted) {
            precondition((0...100).contains(result.score))
            precondition(result.action == .braking)
            precondition((result.score >= 85) == (result.feedback == "整體平順"))
        }
        action = SpeedActionTracker()
        action.update(leftTurn, at: 0); action.update(leftTurn, at: 0.3)
        action.update(leftTurn, at: 2)
        precondition(action.action == .steady && action.lastCompleted == nil)
        precondition(!action.isFresh(at: 3))
        action = SpeedActionTracker()
        action.update(leftTurn, at: 0); action.update(leftTurn, at: 0.21)
        action.update(SpeedGForce(lateral: 0, longitudinal: 0), at: 0.3)
        action.update(SpeedGForce(lateral: 0, longitudinal: 0), at: 0.65)
        precondition(action.lastCompleted == nil)
        action.update(SpeedGForce(lateral: .nan, longitudinal: 0), at: 0.7)
        precondition(action.action == .steady && action.lastCompleted == nil)
        print("PASS: G projection, 0.12G vibration rejection, gentle maneuvers, filter reset, action completion, smoothness scores, sample rates, gaps and card layout")
    }
}
