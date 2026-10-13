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
        print("Energy policies: \(checks) checks passed")
    }
}
