import Foundation

@main
struct ParkingEntryClockChecks {
    static func main() {
        let suite = "gorilla.parking-entry-checks.\(ProcessInfo.processInfo.processIdentifier)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let arrival = Date(timeIntervalSince1970: 1_790_000_000)
        let now = arrival.addingTimeInterval(600)
        precondition(ParkingEntryClock.restoredEntry(for: arrival, defaults: defaults) == arrival)
        defaults.set(arrival, forKey: "parkingStartTime")
        precondition(ParkingEntryClock.restoredEntry(for: arrival, defaults: defaults) == arrival,
                     "Legacy installs must retain the real arrival")
        let adjusted = arrival.addingTimeInterval(-120)
        ParkingEntryClock.save(arrival: arrival, entry: adjusted, defaults: defaults)
        let reopened = UserDefaults(suiteName: suite)!
        var entry = ParkingEntryClock.restoredEntry(for: arrival, defaults: reopened)
        precondition(now.timeIntervalSince(entry) == 720, "Relaunch reset a 12-minute timer to ten minutes")
        precondition(ParkingEntryClock.adjustmentMinutes(entry: entry, arrival: arrival) == -2)
        precondition(reopened.object(forKey: "parkingStartTime") as? Date == arrival,
                     "An entry-time adjustment rewrote actual visit history")
        for _ in 0..<5 {
            entry = ParkingEntryClock.restoredEntry(for: arrival, defaults: reopened)
            precondition(entry == adjusted, "Foreground refresh lost the correction")
        }
        entry += 120
        ParkingEntryClock.save(arrival: arrival, entry: entry, defaults: reopened)
        precondition(now.timeIntervalSince(ParkingEntryClock.restoredEntry(for: arrival, defaults: reopened)) == 600)
        precondition(ParkingEntryClock.adjustmentMinutes(entry: entry, arrival: arrival) == 0,
                     "Adding two minutes after relaunch did not undo subtracting two minutes")
        let nextArrival = arrival.addingTimeInterval(3600)
        precondition(ParkingEntryClock.restoredEntry(for: nextArrival, defaults: reopened) == nextArrival,
                     "A new visit inherited a previous parking adjustment")
        ParkingEntryClock.save(arrival: nextArrival, entry: nextArrival, defaults: reopened)
        precondition(ParkingEntryClock.restoredEntry(for: nextArrival, defaults: reopened) == nextArrival)
        let manualStart = nextArrival.addingTimeInterval(900)
        defaults.set(manualStart, forKey: "manualParkingStartedAt")
        defaults.set(manualStart, forKey: "parkingVisitsDismissedThrough")
        ParkingEntryClock.save(arrival: manualStart, entry: manualStart, defaults: defaults)
        let relaunched = UserDefaults(suiteName: suite)!
        let dismissed = relaunched.object(forKey: "parkingVisitsDismissedThrough") as? Date
        precondition(ParkingEntryClock.ignoresVisit(arrival: arrival, dismissedThrough: dismissed))
        precondition(ParkingEntryClock.ignoresVisit(arrival: nextArrival, dismissedThrough: dismissed))
        precondition(!ParkingEntryClock.ignoresVisit(arrival: manualStart.addingTimeInterval(60), dismissedThrough: dismissed))
        precondition(ParkingEntryClock.restoredEntry(for: manualStart, defaults: relaunched) == manualStart)
        precondition(ParkingEntryClock.repeatInterval(heldFor: 0.5) > ParkingEntryClock.repeatInterval(heldFor: 2))
        precondition(ParkingEntryClock.repeatInterval(heldFor: 2) > ParkingEntryClock.repeatInterval(heldFor: 4))
        print("PASS: adjusted timer persistence, reload, repeated foreground refresh, inverse correction, new visit and unchanged actual arrival")
    }
}
