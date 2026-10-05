// Framework substitutes for the isolated manager tests; never linked into the app.
enum TestClock {
    static var now = Date(timeIntervalSince1970: 1_780_000_000)
    static var uptime = 100_000.0
}

final class UIApplication {
    enum State { case active, background }
    static let shared = UIApplication()
    static let didEnterBackgroundNotification = Notification.Name("test.background")
    var applicationState: State = .active
    var isProtectedDataAvailable = true
}

final class CMMotionActivity {
    enum Confidence { case low, medium, high }
    var stationary = true
    var walking = false
    var running = false
    var cycling = false
    var automotive = true
    var confidence: Confidence = .high
}

final class CMAltitudeData {
    let timestamp: Double
    let relativeAltitude: NSNumber
    let pressure: NSNumber
    init(altitude: Double) {
        timestamp = TestClock.uptime
        relativeAltitude = NSNumber(value: altitude)
        pressure = 100
    }
}

final class CMAltimeter {
    enum Authorization { case authorized, notDetermined, denied, restricted }
    static var latest: CMAltimeter!
    var starts = 0
    var stops = 0
    private var handler: ((CMAltitudeData?, Error?) -> Void)?
    init() { Self.latest = self }
    static func isRelativeAltitudeAvailable() -> Bool { true }
    static func authorizationStatus() -> Authorization { .authorized }
    func startRelativeAltitudeUpdates(to queue: OperationQueue,
                                     withHandler handler: @escaping (CMAltitudeData?, Error?) -> Void) {
        starts += 1
        self.handler = handler
    }
    func stopRelativeAltitudeUpdates() { stops += 1 }
    func emit(_ altitude: Double) { handler?(CMAltitudeData(altitude: altitude), nil) }
}
