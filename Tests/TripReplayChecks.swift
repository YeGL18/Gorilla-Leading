import Foundation
import CoreLocation

@main
struct TripReplayChecks {
    static let start = Date(timeIntervalSince1970: 1792670400)
    static func point(_ second: Double, speed: Double? = 36, altitude: Double? = 20,
                      latitude: Double? = nil, gap: Bool = false) -> TripReplayPoint {
        TripReplayPoint(time: start.addingTimeInterval(second), latitude: latitude ?? (22.3 + second * 0.00005),
            longitude: 114.1, accuracy: 5, speedKmh: speed, altitude: altitude,
            verticalAccuracy: altitude == nil ? nil : 5, breakBefore: gap)
    }
    static func near(_ a: Double, _ b: Double, tolerance: Double = 0.001) { precondition(abs(a - b) < tolerance, "\(a) != \(b)") }

    static func main() throws {
        var slow = ReplayScrubMotion(), fast = ReplayScrubMotion()
        slow.drag(to: 10, pointsPerSecond: 10)
        fast.drag(to: 10, pointsPerSecond: 2000)
        slow.step(1 / 120)
        fast.step(1 / 120)
        precondition(slow.position > fast.position && fast.position > 0 && slow.position < 10)
        let released = fast.position
        fast.release()
        near(fast.position, released)
        for _ in 0..<240 { fast.step(1 / 120) }
        precondition(fast.settled)
        near(fast.position, 10)
        var sixty = ReplayScrubMotion(), oneTwenty = ReplayScrubMotion()
        sixty.drag(to: 10, pointsPerSecond: 1000)
        oneTwenty.drag(to: 10, pointsPerSecond: 1000)
        for _ in 0..<30 { sixty.step(1 / 60) }
        for _ in 0..<60 { oneTwenty.step(1 / 120) }
        near(sixty.position, oneTwenty.position)
        let displayTrip = TripReplay(id: UUID(), points: [point(0), point(2), point(30, gap: true)], finished: true)
        near(displayTrip.displayCoordinate(at: start.addingTimeInterval(1))!.latitude, point(1).latitude)
        precondition(displayTrip.displayCoordinate(at: start.addingTimeInterval(15)) == nil)
        precondition(displayTrip.displayCoordinate(at: start.addingTimeInterval(-1)) == nil)
        let crossing = TripReplay(id: UUID(), points: [
            TripReplayPoint(time: start, latitude: 0, longitude: 179.9999, accuracy: 5),
            TripReplayPoint(time: start.addingTimeInterval(1), latitude: 0, longitude: -179.9999, accuracy: 5)
        ], finished: true)
        near(abs(crossing.displayCoordinate(at: start.addingTimeInterval(0.5))!.longitude), 180)
        var recorder = TripReplayRecorder()
        let named = TripReplayPlace(name: "Named Parking", latitude: 22.3, longitude: 114.1, radius: 100, priority: 0)
        let saved = TripReplayPlace(name: "Saved Destination", latitude: 22.3, longitude: 114.1, radius: 100, priority: 1)
        precondition(TripReplayPlace.name(near: point(0), places: [saved, named]) == "Named Parking")
        precondition(TripReplayPlace.name(near: point(1000), places: [named]) == nil)
        for i in 0..<2 { recorder.append(point(Double(i)), automotive: true, pedestrian: false) }
        precondition(!recorder.hasActiveTrip)
        recorder.append(point(2), automotive: true, pedestrian: false)
        precondition(recorder.current?.points.count == 3)
        recorder.attachPrediction(.init(createdAt: start, latitude: point(60).latitude, longitude: 114.1))
        for i in 3...20 { recorder.append(point(Double(i)), automotive: true, pedestrian: false) }
        let id = recorder.current!.id
        precondition(recorder.current!.topSpeed == 36)
        precondition(recorder.current!.highestAltitude == 20)
        precondition(recorder.current!.distanceMeters > 100)
        near(recorder.current!.drivingSeconds, 20)

        let count = recorder.current!.points.count
        recorder.append(point(20), automotive: true, pedestrian: false)
        recorder.append(point(19), automotive: true, pedestrian: false)
        precondition(recorder.current!.points.count == count)
        recorder.pause()
        recorder.append(point(60), automotive: true, pedestrian: false)
        precondition(recorder.current!.hasGaps)
        precondition(recorder.current!.point(at: start.addingTimeInterval(40)) == nil)
        near(recorder.current!.observedSeconds, 20)
        precondition(recorder.current!.routeSegments.count == 2)
        precondition(recorder.current!.points.last!.altitude == nil)

        // A one-fix teleport must not zoom the route out or inflate statistics.
        recorder.append(point(61, latitude: 25), automotive: true, pedestrian: false)
        precondition(recorder.current!.points.last!.time == start.addingTimeInterval(60))
        recorder.append(point(62), automotive: true, pedestrian: false)
        precondition(recorder.current!.points.last!.breakBefore)

        let event = TripReplayEvent(id: UUID(), start: start.addingTimeInterval(5), end: start.addingTimeInterval(8),
                                    action: .left, peakG: 0.2, score: 90)
        recorder.add(event)
        precondition(recorder.current!.events.count == 1)
        let origin = TripReplayVisit(id: UUID(), arrival: start.addingTimeInterval(-3600), departure: start,
                                    latitude: 22.3, longitude: 114.1, name: "Origin")
        let destination = TripReplayVisit(id: UUID(), arrival: start.addingTimeInterval(60), departure: nil,
                                         latitude: point(62).latitude, longitude: 114.1, name: "Destination")
        recorder.link(visits: [origin, destination])
        precondition(!recorder.hasActiveTrip)
        precondition(recorder.archive.trips[0].originVisitID == origin.id)
        precondition(recorder.archive.trips[0].destinationVisitID == destination.id)
        precondition(recorder.archive.trips[0].end == start.addingTimeInterval(60))
        precondition(recorder.archive.trips[0].isHabitualRoute)
        recorder.resolveNames(places: [named, saved])
        precondition(recorder.archive.trips[0].originName == "Origin")
        precondition(recorder.archive.trips[0].destinationName == "Destination")
        let ab = recorder.archive.trips[0]
        // Even stale visit IDs on B→C cannot override the actual A→B time window.
        var bc = TripReplay(id: UUID(), points: [point(3600), point(3660)], finished: true)
        bc.originVisitID = origin.id
        bc.destinationVisitID = destination.id
        precondition(TripReplay.matching(in: [bc, ab], origin: origin.id, destination: destination.id,
            departure: start, arrival: start.addingTimeInterval(60))?.id == ab.id)
        precondition(TripReplay.matching(in: [bc], origin: origin.id, destination: destination.id,
            departure: start, arrival: start.addingTimeInterval(60)) == nil)
        let overlappingNext = TripReplay(id: UUID(), points: [point(50), point(150)], finished: true)
        precondition(TripReplay.matching(in: [overlappingNext], origin: origin.id, destination: destination.id,
            departure: start, arrival: start.addingTimeInterval(60)) == nil)
        precondition(TripReplay.matching(in: [ab], origin: origin.id, destination: destination.id,
            departure: nil, arrival: start.addingTimeInterval(60)) == nil)
        var noPrediction = recorder.archive.trips[0]
        noPrediction.prediction = nil
        precondition(!noPrediction.isHabitualRoute)
        var wrongPrediction = recorder.archive.trips[0]
        wrongPrediction.prediction = .init(createdAt: start, latitude: 30, longitude: 120)
        precondition(!wrongPrediction.isHabitualRoute)
        _ = try recorder.archive.validated()
        let data = try JSONEncoder().encode(recorder.archive)
        let decoded = try JSONDecoder().decode(TripReplayArchive.self, from: data).validated()
        precondition(decoded.trips.first!.id == id && decoded.trips.first!.events.count == 1)
        precondition(decoded.trips.first!.isHabitualRoute)
        var legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var oldTrips = legacy["trips"] as! [[String: Any]]
        oldTrips[0].removeValue(forKey: "prediction")
        legacy["trips"] = oldTrips
        let oldData = try JSONSerialization.data(withJSONObject: legacy)
        let oldArchive = try JSONDecoder().decode(TripReplayArchive.self, from: oldData).validated()
        precondition(oldArchive.trips.first!.prediction == nil && !oldArchive.trips.first!.isHabitualRoute)
        recorder.delete(id)
        precondition(recorder.archive.trips.isEmpty)

        // Walking and stationary engine noise cannot start a car journey.
        for mode in 0...2 {
            recorder = TripReplayRecorder()
            for i in 0...20 {
                recorder.append(point(Double(i), speed: mode == 0 ? 0 : 10), automotive: mode == 0, pedestrian: mode == 1)
            }
            precondition(!recorder.hasActiveTrip)
        }
        recorder = TripReplayRecorder()
        for i in 0...10 { recorder.append(point(Double(i), speed: 25), automotive: false, pedestrian: false) }
        precondition(recorder.hasActiveTrip)
        for i in 11...315 { recorder.append(point(Double(i), speed: 0, latitude: point(10).latitude), automotive: true, pedestrian: false) }
        precondition(!recorder.hasActiveTrip)
        near(recorder.archive.trips.first!.duration, 10)

        // Weighted speeds include a valid zero, but never invalid/missing intervals.
        let stats = TripReplay(id: UUID(), points: [point(0, speed: 0, altitude: -10), point(2, speed: 36, altitude: 10),
            point(6, speed: 72, altitude: 20), point(20, speed: nil, altitude: nil)])
        near(stats.averageSpeed!, 42)
        near(stats.observedSeconds, 6)
        precondition(stats.highestAltitude == 20 && stats.lowestAltitude == -10)
        precondition(stats.topSpeed == 72 && stats.hasGaps)
        precondition(stats.point(at: start.addingTimeInterval(0))?.speedKmh == 0)
        precondition(stats.point(at: start.addingTimeInterval(18)) == nil)

        var altitudeFilter = ReplayAltitudeFilter()
        precondition(altitudeFilter.update(20, at: start, reset: true) == nil)
        precondition(altitudeFilter.update(20, at: start.addingTimeInterval(1), reset: false) == nil)
        near(altitudeFilter.update(20, at: start.addingTimeInterval(2), reset: false)!, 20)
        near(altitudeFilter.update(900, at: start.addingTimeInterval(3), reset: false)!, 20)
        near(altitudeFilter.update(20, at: start.addingTimeInterval(4), reset: false)!, 20)
        precondition(altitudeFilter.update(nil, at: start.addingTimeInterval(5), reset: false) == nil)
        precondition(altitudeFilter.update(100, at: start.addingTimeInterval(6), reset: false) == nil)

        let location = CLLocation(coordinate: .init(latitude: 22.3, longitude: 114.1), altitude: -5,
                                  horizontalAccuracy: 5, verticalAccuracy: 5, course: 0, speed: 10, timestamp: start)
        near(TripReplayPoint.capture(location, now: start)!.speedKmh!, 36)
        near(TripReplayPoint.capture(location, now: start)!.altitude!, -5)
        precondition(TripReplayPoint.capture(location, now: start.addingTimeInterval(20)) == nil)
        let poorAltitude = CLLocation(coordinate: location.coordinate, altitude: 900,
            horizontalAccuracy: 5, verticalAccuracy: -1, course: 0, speed: -1, timestamp: start)
        let poorPoint = TripReplayPoint.capture(poorAltitude, now: start)!
        precondition(poorPoint.altitude == nil && poorPoint.speedKmh == nil)
        let poorGPS = CLLocation(coordinate: location.coordinate, altitude: 20,
            horizontalAccuracy: 100, verticalAccuracy: 5, course: 0, speed: 10, timestamp: start)
        precondition(TripReplayPoint.capture(poorGPS, now: start) == nil)

        recorder = TripReplayRecorder(archive: decoded)
        recorder.prune(now: start.addingTimeInterval(86400 * 31), days: 30)
        precondition(recorder.archive.trips.isEmpty)
        var bad = decoded
        bad.trips[0].points.append(point(0))
        do { _ = try bad.validated(); preconditionFailure("Unordered replay accepted") } catch { }
        bad = decoded
        bad.version = 99
        do { _ = try bad.validated(); preconditionFailure("Unknown archive accepted") } catch { }
        recorder = TripReplayRecorder()
        for i in 0...5 { recorder.append(point(Double(i)), automotive: true, pedestrian: false) }
        let restored = TripReplayRecorder(archive: try JSONDecoder().decode(TripReplayArchive.self,
            from: JSONEncoder().encode(recorder.archive)))
        recorder = restored
        recorder.append(point(2000), automotive: true, pedestrian: false)
        precondition(recorder.archive.trips.first!.finished)
        print("PASS: automatic journeys, walking exclusion, GPS gaps/teleports, altitude quality/filtering, highest altitude, weighted stats, visits, retention, deletion and archive validation")
    }
}
