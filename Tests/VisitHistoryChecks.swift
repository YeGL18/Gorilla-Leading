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
        let editedDuplicate = Visit(id: UUID(), address: "Walking Place", latitude: open.latitude,
            longitude: open.longitude, arrivalDate: open.arrivalDate, departureDate: closed.departureDate,
            transportType: "Walking", isAutomotive: false, transportManuallySet: true)
        for duplicates in [[open, editedDuplicate], [editedDuplicate, open]] {
            let repaired = manager.dedupeVisits(duplicates)
            precondition(repaired.count == 1 && repaired[0].transportManuallySet && !repaired[0].isAutomotive)
        }
        var legacyJSON = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(closed)) as! [String: Any]
        legacyJSON.removeValue(forKey: "transportManuallySet")
        precondition(!(try! JSONDecoder().decode(Visit.self, from: JSONSerialization.data(withJSONObject: legacyJSON))).transportManuallySet)
        precondition(!Visit.matchesArrival(timeDifference: 60, distance: 400))
        precondition(!Visit.matchesArrival(timeDifference: 0, distance: 1000))

        // Native sentinels must not create an ancient visit or erase a valid long stay.
        let ongoing = NativeVisitEvent(latitude: 22.3, longitude: 114.17, horizontalAccuracy: 20,
                                       arrival: arrival, departure: .distantFuture)
        precondition(ongoing.departure == nil && ongoing.arrival == arrival)
        let eventOpen = visit("Open")
        let departureOnly = NativeVisitEvent(latitude: 22.3, longitude: 114.17, horizontalAccuracy: 20,
                                             arrival: .distantPast, departure: arrival.addingTimeInterval(360))
        precondition(departureOnly.arrival == nil && Visit.matchingEvent(departureOnly, in: [eventOpen]) == 0)
        precondition(Visit.matchingEvent(departureOnly, in: []) == nil)
        let wrongLocation = NativeVisitEvent(latitude: 22.6, longitude: 114.17, horizontalAccuracy: 20,
                                             arrival: .distantPast, departure: arrival.addingTimeInterval(360))
        precondition(Visit.matchingEvent(wrongLocation, in: [eventOpen]) == nil)
        let newerVisit = visit("Return", offset: 300)
        precondition(Visit.matchingEvent(departureOnly, in: [eventOpen, newerVisit]) == 1)
        let historicalDeparture = NativeVisitEvent(latitude: 22.3, longitude: 114.17, horizontalAccuracy: 20,
                                                   arrival: .distantPast, departure: arrival.addingTimeInterval(250))
        precondition(Visit.matchingEvent(historicalDeparture, in: [eventOpen, newerVisit]) == 0)
        let longStay = NativeVisitEvent(latitude: 22.3, longitude: 114.17, horizontalAccuracy: 20,
                                        arrival: arrival, departure: arrival.addingTimeInterval(12 * 86400))
        precondition(longStay.departure != nil)
        let driftedDeparture = NativeVisitEvent(latitude: 22.308, longitude: 114.17, horizontalAccuracy: 1000,
                                                arrival: arrival, departure: arrival.addingTimeInterval(360))
        precondition(Visit.matchingEvent(driftedDeparture, in: [closed]) == 0)
        let ambiguousDrift = NativeVisitEvent(latitude: 22.308, longitude: 114.17, horizontalAccuracy: 1000,
                                              arrival: arrival.addingTimeInterval(60), departure: arrival.addingTimeInterval(360))
        precondition(Visit.matchingEvent(ambiguousDrift, in: [closed]) == nil)
        precondition(try! JSONDecoder().decode(NativeVisitEvent.self, from: JSONEncoder().encode(longStay)) == longStay)

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

        manager.motionSegments = [
            MotionSegment(id: UUID(), mode: "Driving", start: from, end: from.addingTimeInterval(600)),
            MotionSegment(id: UUID(), mode: "Stationary", start: from.addingTimeInterval(600), end: from.addingTimeInterval(620)),
            MotionSegment(id: UUID(), mode: "Unknown", start: from.addingTimeInterval(620), end: from.addingTimeInterval(640)),
            MotionSegment(id: UUID(), mode: "Driving", start: from.addingTimeInterval(640), end: to)
        ]
        let rawCount = manager.motionSegments.count
        let smooth = manager.tripDisplayTimeline(from: from, to: to)
        precondition(smooth.count == 1 && smooth[0].mode == "Driving")
        precondition(smooth[0].resolvedEnd.timeIntervalSince(smooth[0].start) == 1800)
        precondition(manager.motionSegments.count == rawCount)
        manager.motionSegments[3].mode = "Walking"
        let transfer = manager.tripDisplayTimeline(from: from, to: to)
        precondition(transfer.map(\.mode) == ["Driving", "Unknown", "Walking"])
        precondition(transfer.reduce(0) { $0 + $1.resolvedEnd.timeIntervalSince($1.start) } == 1800)
        manager.motionSegments[3].mode = "Driving"
        manager.motionSegments[2].end = from.addingTimeInterval(900)
        manager.motionSegments[3].start = from.addingTimeInterval(900)
        precondition(manager.tripDisplayTimeline(from: from, to: to).map(\.mode) == ["Driving", "Unknown", "Driving"])

        // Recovering a closed historical segment must not leave the live segment closed.
        manager.motionSegments = [MotionSegment(id: UUID(), mode: "Driving", start: from, end: to)]
        manager.appendSegment(mode: "Driving", start: to, end: nil)
        precondition(manager.motionSegments.count == 1 && manager.motionSegments[0].end == nil)
        manager.trimAndSaveMotionSegments()
        let savedMotion = try! JSONDecoder().decode([MotionSegment].self,
            from: manager.motionPreferences.data(forKey: manager.motionSegmentsKey)!)
        precondition(savedMotion.last?.end != nil && manager.motionSegments.last?.end == nil)
        manager.motionPreferences.set(try! JSONEncoder().encode([
            MotionSegment(id: UUID(), mode: "Driving", start: from, end: nil)
        ]), forKey: manager.motionSegmentsKey)
        manager.loadMotionSegments()
        precondition(manager.motionSegments[0].end == from)
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
        // The reported route: 36 minutes driving, then 14 minutes walking.
        let schoolArrival = from.addingTimeInterval(50 * 60)
        manager.motionSegments = [
            MotionSegment(id: UUID(), mode: "Driving", start: from, end: from.addingTimeInterval(36 * 60)),
            MotionSegment(id: UUID(), mode: "Walking", start: from.addingTimeInterval(36 * 60), end: schoolArrival)
        ]
        let schoolTrip = manager.classifyTrip(tripStart: from, arrival: schoolArrival)
        precondition(!schoolTrip.isAutomotive && schoolTrip.transportType == "Walking")
        precondition(manager.tripDisplayTimeline(from: from, to: schoolArrival).map { $0.resolvedEnd.timeIntervalSince($0.start) } == [2160, 840])
        let cachedSchool = Visit(id: UUID(), address: "School", latitude: 22.3, longitude: 114.17,
            arrivalDate: schoolArrival, departureDate: schoolArrival.addingTimeInterval(3300),
            transportType: "Driving", isAutomotive: true)
        manager.visits = [closed, cachedSchool]
        manager.motionHistoryFrom = from
        manager.motionHistoryThrough = schoolArrival
        ParkingFloorStore.shared.lots = [LotFixture(preferredDisplayName: "School", radiusMeters: 180,
            points: [PointFixture(latitude: 22.3, longitude: 114.17, createdAt: schoolArrival, address: "School")])]
        manager.reclassifyVisitsAfterMotionRecovery()
        precondition(manager.visits[1].transportType == "Walking" && !manager.visits[1].isAutomotive)
        precondition(manager.visits[1].arrivalDate == cachedSchool.arrivalDate && manager.visits[1].departureDate == cachedSchool.departureDate)
        precondition(ParkingFloorStore.shared.allPoints[0].isAutomotive == false)
        var photoPoint = ParkingFloorStore.shared.allPoints[0]
        photoPoint.isAutomotive = true
        photoPoint.llmSpotNumber = "A123"
        photoPoint.manualFloorIndex = 1
        let nearby = PointFixture(latitude: 22.3, longitude: 114.17,
            createdAt: schoolArrival.addingTimeInterval(20), address: "Other Point")
        let farAway = PointFixture(latitude: 23.3, longitude: 114.17, createdAt: schoolArrival, address: "Unrelated")
        ParkingFloorStore.shared.lots[0].points = [photoPoint, nearby, farAway]
        let correctedSchool = manager.visits[1]
        ParkingFloorStore.shared.updateAutomotiveFlags([correctedSchool])
        precondition(ParkingFloorStore.shared.allPoints.filter { !$0.isAutomotive }.count == 2)
        let retainedPhotoPoint = ParkingFloorStore.shared.allPoints.first { $0.id == photoPoint.id }!
        precondition(retainedPhotoPoint.llmSpotNumber == "A123" && retainedPhotoPoint.manualFloorIndex == 1)
        let saves = ParkingFloorStore.shared.persistCount
        ParkingFloorStore.shared.updateAutomotiveFlags([correctedSchool])
        precondition(ParkingFloorStore.shared.persistCount == saves)
        var manualSchool = cachedSchool
        manualSchool.transportManuallySet = true
        manager.visits[1] = manualSchool
        manager.reclassifyVisitsAfterMotionRecovery()
        precondition(manager.visits[1].isAutomotive)
        // A stale open intermediate visit must not block recovery of the real trip.
        manager.visits = [closed, visit("Stale intermediate", offset: 1200), cachedSchool]
        manager.reclassifyVisitsAfterMotionRecovery()
        precondition(manager.visits.last?.transportType == "Walking")
        manager.motionSegments.removeLast()
        precondition(manager.classifyTrip(tripStart: from, arrival: schoolArrival).transportType == "Unknown")
        precondition(!manager.classifyTrip(tripStart: nil, arrival: schoolArrival).isAutomotive)
        manager.motionSegments[0].end = schoolArrival
        precondition(manager.classifyTrip(tripStart: from, arrival: schoolArrival).isAutomotive)
        manager.motionSegments.append(MotionSegment(id: UUID(), mode: "Walking", start: from, end: schoolArrival))
        precondition(manager.classifyTrip(tripStart: from, arrival: schoolArrival).transportType == "Unknown")

        let rules = VisitTimelineRules()
        let shortStop = visit("Brief", departure: 6 * 60)
        precondition(VisitTimeline.make([shortStop], rules: rules, now: schoolArrival).isEmpty)
        let candidate = VisitTimeline.make([eventOpen], rules: rules, now: arrival.addingTimeInterval(6 * 60))
        precondition(candidate.count == 1 && candidate[0].candidate)
        precondition(candidate[0].record.arrivalDate == eventOpen.arrivalDate)
        let mature = VisitTimeline.make([eventOpen], rules: rules, now: arrival.addingTimeInterval(11 * 60))
        precondition(mature.count == 1 && !mature[0].candidate)
        let overnight = visit("Home", departure: 16 * 60)
        let returnHome = visit("GPS name drift", offset: 26 * 60, departure: 40 * 60)
        let joined = VisitTimeline.make([overnight, returnHome], rules: rules, now: arrival.addingTimeInterval(50 * 60))
        precondition(joined.count == 1 && joined[0].sourceIDs == [overnight.id, returnHome.id])
        precondition(joined[0].record.arrivalDate == overnight.arrivalDate && joined[0].record.departureDate == returnHome.departureDate)
        var unmergedRules = rules
        unmergedRules.mergeConsecutive = false
        precondition(VisitTimeline.make([overnight, returnHome], rules: unmergedRules, now: schoolArrival).count == 2)
        let staleShort = visit("Stale", offset: 500)
        let afterStale = visit("Other", latitude: 22.4, offset: 900, departure: 1800)
        precondition(!VisitTimeline.make([staleShort, afterStale], rules: rules, now: schoolArrival).contains { $0.sourceIDs.contains(staleShort.id) })

        let firstPlace = visit("First", departure: 960)
        let secondPlace = visit("Second", latitude: 22.3013, offset: 86400, departure: 86400 + 960)
        let overlapping = visit("Unstable label", latitude: 22.3007, offset: 172800, departure: 172800 + 720)
        let nearest = VisitTimeline.make([firstPlace, secondPlace, overlapping], rules: rules,
                                       now: arrival.addingTimeInterval(200000))
        precondition(nearest.last?.record.address == "Second")
        var activeRules = rules
        activeRules.activePlaceMinutes = 5
        let briefReturn = visit("Later", offset: 172800, departure: 172800 + 480)
        precondition(VisitTimeline.make([firstPlace, briefReturn], rules: activeRules, now: arrival.addingTimeInterval(200000)).count == 2)
        activeRules.deactivateDays = 1
        precondition(VisitTimeline.make([firstPlace, briefReturn], rules: activeRules, now: arrival.addingTimeInterval(200000)).count == 1)
        print("PASS: raw visit preservation; candidate/short/merged visits; nearest/expired active places; 36min driving + 14min walking; delayed reclassification and point synchronization; manual overrides; timers and names unchanged")
    }
}
