import Foundation
import CoreLocation

enum ParkingReminderPolicy {
    struct Session {
        let arrival: Date
        let departure: Date?
        let coordinate: CLLocationCoordinate2D
        let automotive: Bool
    }

    static let longStaySeconds: TimeInterval = 3.5 * 3600
    struct Reminder {
        let minute: Int
        let delay: TimeInterval
    }

    static func schedule(entry: Date, now: Date, suppress: Bool) -> [Reminder] {
        guard !suppress else { return [] }
        return stride(from: 25, through: 175, by: 30).compactMap { minute in
            let delay = entry.addingTimeInterval(Double(minute) * 60).timeIntervalSince(now)
            return delay.isFinite && delay > 10 ? Reminder(minute: minute, delay: delay) : nil
        }
    }

    static func isLongStayPlace(at coordinate: CLLocationCoordinate2D, before arrival: Date,
                               sessions: [Session]) -> Bool {
        guard CLLocationCoordinate2DIsValid(coordinate) else { return false }
        let anchor = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let durations = sessions.sorted { $0.arrival > $1.arrival }.compactMap { session -> TimeInterval? in
            guard session.automotive, session.arrival < arrival,
                  let departure = session.departure, departure <= arrival, departure > session.arrival,
                  CLLocationCoordinate2DIsValid(session.coordinate),
                  anchor.distance(from: CLLocation(latitude: session.coordinate.latitude,
                                                   longitude: session.coordinate.longitude)) <= 100 else { return nil }
            let duration = departure.timeIntervalSince(session.arrival)
            return duration.isFinite ? duration : nil
        }.prefix(5)
        guard !durations.isEmpty else { return false }
        return durations.reduce(0, +) / Double(durations.count) >= longStaySeconds
    }
}
