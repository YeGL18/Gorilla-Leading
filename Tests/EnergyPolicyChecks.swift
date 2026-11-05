import Foundation
import CoreLocation

@main
struct EnergyPolicyChecks {
    static func main() {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message)
            checks += 1
        }
        check(!RouteRefreshPolicy.shouldRequest(age: 2, moved: 30, hasResult: true), "Two-second timer reuses the route")
        check(!RouteRefreshPolicy.shouldRequest(age: 29, moved: 50, hasResult: true), "Small GPS drift does not refresh")
        check(RouteRefreshPolicy.shouldRequest(age: 30, moved: 50, hasResult: true), "Normal refresh is thirty seconds")
        check(RouteRefreshPolicy.shouldRequest(age: 10, moved: 250, hasResult: true), "Large movement can refresh earlier")
        check(!RouteRefreshPolicy.shouldRequest(age: 9, moved: 1000, hasResult: true), "Large movement cannot flood requests")
        check(!RouteRefreshPolicy.shouldRequest(age: 9, moved: 0, hasResult: false), "Failed requests back off")
        check(RouteRefreshPolicy.shouldRequest(age: 10, moved: 0, hasResult: false), "Failure can retry after ten seconds")

        let now = Date()
        func fix(age: Double, speed: Double = 0, accuracy: Double = 5, offset: Double = 0) -> CLLocation {
            CLLocation(coordinate: .init(latitude: 22.32, longitude: 114.17 + offset / 103000), altitude: 0,
                       horizontalAccuracy: accuracy, verticalAccuracy: 5, course: 0, speed: speed,
                       timestamp: now.addingTimeInterval(-age))
        }
        // Samples are supplied in chronological order, ending at the current time.
        // Simulate that time at each fix through an injected validation date.
        var policy = LocationEnergyPolicy()
        check(policy.observe(fix(age: 0), captureActive: false) == .navigation, "Initial fix retains navigation precision")
        for second in 1...59 {
            check(policy.observe(fix(age: -Double(second)), captureActive: false, now: now.addingTimeInterval(Double(second))) == .navigation,
                  "Short stops and gates keep high precision")
        }
        check(policy.observe(fix(age: -60), captureActive: false, now: now.addingTimeInterval(60)) == .stationary,
              "A stable sixty-second stop lowers accuracy")
        check(policy.observe(fix(age: -61, speed: 1), captureActive: false, now: now.addingTimeInterval(61)) == .navigation,
              "Movement immediately restores navigation accuracy")
        check(policy.observe(fix(age: -62), captureActive: false, now: now.addingTimeInterval(62)) == .navigation,
              "Stopping again starts a new dwell window")
        check(policy.observe(fix(age: -130), captureActive: true, now: now.addingTimeInterval(130)) == .navigation,
              "Floor sampling always retains high accuracy")
        check(policy.observe(fix(age: -200, accuracy: 50), captureActive: false, now: now.addingTimeInterval(200)) == .navigation,
              "Weak GPS is not interpreted as parked")
        check(policy.observe(fix(age: -201, speed: -1), captureActive: false, now: now.addingTimeInterval(201)) == .navigation,
              "Unknown speed does not lower accuracy")
        policy.reset()
        _ = policy.observe(fix(age: -300), captureActive: false, now: now.addingTimeInterval(300))
        check(policy.observe(fix(age: -360, offset: 20), captureActive: false, now: now.addingTimeInterval(360)) == .navigation,
              "A change in position restarts the dwell window")
        check(policy.observe(fix(age: 100), captureActive: false) == .navigation, "Stale fixes do not reduce accuracy")
        policy.reset()
        _ = policy.observe(fix(age: -400), captureActive: false, now: now.addingTimeInterval(400))
        check(policy.observe(fix(age: -460), captureActive: false, now: now.addingTimeInterval(460)) == .navigation,
              "A gap in GPS fixes cannot be counted as sixty seconds of observed stability")
        policy.reset()
        for second in 0...60 {
            _ = policy.observe(fix(age: -Double(second)), captureActive: false, now: now.addingTimeInterval(Double(second)))
        }
        check(policy.observe(fix(age: -180), captureActive: false, now: now.addingTimeInterval(180)) == .stationary,
              "A sparse callback after a fully observed stop keeps the quiet sampling mode")
        check(policy.observe(fix(age: -181, speed: 3), captureActive: false, now: now.addingTimeInterval(181)) == .navigation,
              "Movement after quiet sampling restores full precision immediately")
        let parkedBackground = LocationSamplingPlan(mode: .stationary, background: true, captureActive: false)
        check(parkedBackground.distanceFilter == 20, "Confirmed background stops coalesce GPS callbacks")
        check(parkedBackground.accuracy == kCLLocationAccuracyNearestTenMeters, "Background stop keeps place-level accuracy")
        for mode in [LocationEnergyPolicy.Mode.navigation, .stationary] {
            check(LocationSamplingPlan(mode: mode, background: true, captureActive: true).distanceFilter == kCLDistanceFilterNone,
                  "Floor capture never filters location callbacks")
            check(LocationSamplingPlan(mode: mode, background: false, captureActive: false).distanceFilter == kCLDistanceFilterNone,
                  "Foreground watchdog always receives unfiltered callbacks")
        }
        check(LocationSamplingPlan(mode: .navigation, background: true, captureActive: false).accuracy == kCLLocationAccuracyBestForNavigation,
              "Driving in the background keeps navigation accuracy")
        var rest = BackgroundLocationRestPolicy()
        check(!rest.canRest(at: now, captureActive: false), "GPS silence alone never implies a long stop")
        rest.observe(stationary: true, at: now)
        check(!rest.canRest(at: now.addingTimeInterval(299), captureActive: false), "Brief stops retain existing precision")
        check(rest.canRest(at: now.addingTimeInterval(300), captureActive: false), "Reliable five-minute stationary evidence permits rest")
        check(!rest.canRest(at: now.addingTimeInterval(900), captureActive: true), "Active floor capture overrides long-rest mode")
        rest.observe(stationary: true, at: now.addingTimeInterval(400))
        check(rest.deadline == now.addingTimeInterval(300), "Repeated stationary events must not postpone rest")
        rest.observe(stationary: false, at: now.addingTimeInterval(401))
        check(!rest.canRest(at: now.addingTimeInterval(1000), captureActive: false), "Moving or uncertain motion clears rest evidence")
        let resting = LocationSamplingPlan(mode: .navigation, background: true, captureActive: false, resting: true)
        check(resting.accuracy == kCLLocationAccuracyHundredMeters && resting.distanceFilter == 50, "Long indoor stops can reduce GPS demand despite poor fixes")
        let floor = LocationSamplingPlan(mode: .navigation, background: true, captureActive: true, resting: true)
        check(floor.accuracy == kCLLocationAccuracyBestForNavigation && floor.distanceFilter == kCLDistanceFilterNone, "Floor ramps keep full sampling")
        check(LocationSamplingPlan(mode: .navigation, background: false, captureActive: false, resting: true).accuracy == kCLLocationAccuracyBestForNavigation,
              "Foreground returns to navigation precision")
        print("Energy policies: \(checks) checks passed")
    }
}
