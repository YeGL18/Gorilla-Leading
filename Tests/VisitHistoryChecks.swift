import Foundation

@main
enum VisitHistoryChecks {
    static func main() {
        typealias Visit = LocationManager.VisitRecord
        let manager = LocationManager()
        let arrival = Date(timeIntervalSince1970: 1_000_000)
        func visit(_ address: String, latitude: Double = 22.3, offset: Double = 0, departure: Double? = nil) -> Visit {
            Visit(id: UUID(), address: address, latitude: latitude, longitude: 114.17,
                  arrivalDate: arrival.addingTimeInterval(offset),
                  departureDate: departure.map { arrival.addingTimeInterval($0) }, transportType: "Driving")
        }
        let open = visit("West Kowloon", latitude: 22.303)
        let closed = visit("Kowloon", departure: 360)
        let merged = manager.dedupeVisits([open, closed])
        precondition(merged.count == 1 && merged[0].departureDate == closed.departureDate)
        precondition(manager.dedupeVisits(merged).count == 1)
        precondition(manager.dedupeVisits([closed, visit("Next", offset: 1260)]).count == 2)
        precondition(!Visit.matchesArrival(timeDifference: 60, distance: 400))
        precondition(!Visit.matchesArrival(timeDifference: 0, distance: 1000))

        let from = arrival.addingTimeInterval(360)
        let to = from.addingTimeInterval(1800)
        manager.motionSegments = [MotionSegment(id: UUID(), mode: "Driving", start: arrival, end: to)]
        let trip = manager.tripTimeline(from: from, to: to)
        precondition(trip.count == 1 && trip[0].resolvedEnd.timeIntervalSince(trip[0].start) == 1800)
        manager.motionSegments = [
            MotionSegment(id: UUID(), mode: "Driving", start: from, end: from.addingTimeInterval(1200)),
            MotionSegment(id: UUID(), mode: "Walking", start: from.addingTimeInterval(1200), end: to)
        ]
        let mixed = manager.tripTimeline(from: from, to: to)
        precondition(mixed.map(\.mode) == ["Driving", "Walking"])
        precondition(mixed.reduce(0) { $0 + $1.resolvedEnd.timeIntervalSince($1.start) } == 1800)

        // Recovering a closed historical segment must not leave the live segment closed.
        manager.motionSegments = [MotionSegment(id: UUID(), mode: "Driving", start: from, end: to)]
        manager.appendSegment(mode: "Driving", start: to, end: nil)
        precondition(manager.motionSegments.count == 1 && manager.motionSegments[0].end == nil)
        let store = ParkingFloorStore()
        store.lots = [LotFixture(preferredDisplayName: "Parking Name", radiusMeters: 180,
                                 points: [PointFixture(latitude: 22.3, longitude: 114.17, createdAt: arrival, address: "POI")])]
        precondition(store.displayName(for: closed) == "Parking Name")
        store.lots[0].preferredDisplayName = "Renamed Parking"
        precondition(store.displayName(for: closed) == "Renamed Parking")
        precondition(store.displayName(for: visit("Other Visit", offset: 3600)) == "Other Visit")
        store.lots[0].preferredDisplayName = nil
        precondition(store.displayName(for: closed) == "POI")
        let latestArrival = arrival.addingTimeInterval(7200)
        store.lots = [
            LotFixture(preferredDisplayName: "West Kowloon", radiusMeters: 180,
                       points: [PointFixture(latitude: 22.3, longitude: 114.17, createdAt: arrival, address: "Old")]),
            LotFixture(preferredDisplayName: "Silver Lake", radiusMeters: 180,
                       points: [PointFixture(latitude: 22.43, longitude: 114.2, createdAt: latestArrival, address: "Current")])
        ]
        store.activeLotID = store.lots[0].id
        precondition(store.currentSession?.locationName == "Silver Lake")
        store.lots[0].preferredDisplayName = "Hong Kong West Kowloon"
        precondition(store.currentSession?.locationName == "Silver Lake")
        precondition(store.session(forArrival: latestArrival)?.locationName == "Silver Lake")
        precondition(store.session(forArrival: arrival) == nil)
        store.lots.reverse()
        precondition(store.currentSession?.locationName == "Silver Lake")
        store.lots[0].preferredDisplayName = "Renamed Current Parking"
        precondition(store.currentSession?.locationName == "Renamed Current Parking")
        print("PASS: duplicate repair; bounded/mixed trips; live recovery; visit naming; historical rename, stale active ID and reordered lots never replace the current parking session")
    }
}
