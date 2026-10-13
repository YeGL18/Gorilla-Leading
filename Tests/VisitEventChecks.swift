import Foundation

@main
struct VisitEventChecks {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("visit-event-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let arrival = Date(timeIntervalSince1970: 1_000_000)
        let open = LocationManager.VisitRecord(id: UUID(), address: "A", latitude: 22.3, longitude: 114.17,
            arrivalDate: arrival, transportType: "Driving")
        try JSONEncoder().encode([open]).write(to: root.appendingPathComponent("visits.json"))
        let departure = NativeVisitEvent(latitude: 22.3, longitude: 114.17, horizontalAccuracy: 20,
            arrival: .distantPast, departure: arrival.addingTimeInterval(720))

        // Background relaunch with locked protected stores: receive without hydrating or overwriting history.
        UIApplication.shared.isProtectedDataAvailable = false
        let locked = LocationManager(root: root)
        locked.prepare()
        locked.loadPendingVisitEvents()
        locked.pendingVisitEvents = [departure]
        locked.persistPendingVisitEvents()
        locked.drainPendingVisitEvents()
        precondition(locked.hydrationCalls == 0 && locked.visits.isEmpty)
        let persisted = try JSONDecoder().decode([LocationManager.VisitRecord].self,
            from: Data(contentsOf: root.appendingPathComponent("visits.json")))
        precondition(persisted.count == 1)

        // A fresh process restores the durable event after unlock, hydrates first, then closes the original ID.
        UIApplication.shared.isProtectedDataAvailable = true
        let resumed = LocationManager(root: root)
        resumed.prepare()
        precondition(resumed.visits.count == 1 && resumed.visits[0].id == open.id)
        precondition(resumed.visits[0].departureDate == departure.departure)
        precondition(resumed.pendingVisitEvents.isEmpty && resumed.manager.starts == 1)
        resumed.prepare()
        precondition(resumed.hydrationCalls == 1)

        // Departure delivered before arrival stays queued and resolves once the actual arrival is delivered.
        let second = NativeVisitEvent(latitude: 22.5, longitude: 114.17, horizontalAccuracy: 20,
            arrival: .distantPast, departure: arrival.addingTimeInterval(2400))
        resumed.pendingVisitEvents = [second]
        resumed.drainPendingVisitEvents()
        precondition(resumed.pendingVisitEvents == [second])
        let nextArrival = NativeVisitEvent(latitude: 22.5, longitude: 114.17, horizontalAccuracy: 20,
            arrival: arrival.addingTimeInterval(1800), departure: .distantFuture)
        resumed.pendingVisitEvents.append(nextArrival)
        resumed.drainPendingVisitEvents()
        precondition(resumed.pendingVisitEvents.isEmpty && resumed.visits.count == 2)
        precondition(resumed.visits.last?.departureDate == second.departure)
        precondition(resumed.visits.allSatisfy { $0.arrivalDate > .distantPast })

        // A second lock while the process lives still defers writes until protected data becomes available.
        UIApplication.shared.isProtectedDataAvailable = false
        resumed.pendingVisitEvents = [NativeVisitEvent(latitude: 22.6, longitude: 114.17, horizontalAccuracy: 20,
            arrival: arrival.addingTimeInterval(3000), departure: arrival.addingTimeInterval(15 * 86400))]
        resumed.persistPendingVisitEvents()
        resumed.drainPendingVisitEvents()
        precondition(resumed.visits.count == 2)
        UIApplication.shared.isProtectedDataAvailable = true
        resumed.prepare()
        precondition(resumed.visits.count == 3 && resumed.visits.last?.departureDate != nil)
        print("PASS: locked relaunch/restart queue, hydrate before merge, original IDs, departure-before-arrival, re-lock and 15-day stays")
    }
}
