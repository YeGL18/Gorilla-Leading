import Foundation
import CoreLocation

struct TripReplayPoint: Codable, Identifiable, Equatable, Sendable {
    var id: Date { time }
    let time: Date
    let latitude: Double
    let longitude: Double
    let accuracy: Double
    var speedKmh: Double?
    var altitude: Double?
    var verticalAccuracy: Double?
    var lateralG: Double?
    var longitudinalG: Double?
    var breakBefore = false
    var driving = false

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var isValid: Bool {
        time.timeIntervalSinceReferenceDate.isFinite && CLLocationCoordinate2DIsValid(coordinate)
            && accuracy.isFinite && (0...50).contains(accuracy)
            && [speedKmh, altitude, verticalAccuracy, lateralG, longitudinalG].allSatisfy { $0?.isFinite ?? true }
            && (speedKmh.map { (0...350).contains($0) } ?? true)
            && (altitude.map { (-500...10000).contains($0) } ?? true)
            && (verticalAccuracy.map { (0...20).contains($0) } ?? true)
            && (lateralG.map { abs($0) <= 50 } ?? true) && (longitudinalG.map { abs($0) <= 50 } ?? true)
    }

    func distance(to next: Self) -> Double {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: next.latitude, longitude: next.longitude))
    }

    func connects(to next: Self) -> Bool {
        let dt = next.time.timeIntervalSince(time)
        return !next.breakBefore && dt > 0 && dt <= 12
            && distance(to: next) <= max(80, dt * 100 + accuracy + next.accuracy)
    }

    static func capture(_ location: CLLocation, now: Date) -> Self? {
        guard abs(location.timestamp.timeIntervalSince(now)) <= 10 else { return nil }
        let speed = location.speed >= 0 && location.speed <= 350 / 3.6
            && (location.speedAccuracy < 0 || location.speedAccuracy <= 5) ? location.speed * 3.6 : nil
        let altitudeValid = location.verticalAccuracy.isFinite && (0...20).contains(location.verticalAccuracy)
            && location.altitude.isFinite && (-500...10000).contains(location.altitude)
        let point = Self(time: location.timestamp, latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude, accuracy: location.horizontalAccuracy,
            speedKmh: speed, altitude: altitudeValid ? location.altitude : nil,
            verticalAccuracy: altitudeValid ? location.verticalAccuracy : nil)
        return point.isValid ? point : nil
    }
}

struct TripReplayEvent: Codable, Identifiable, Sendable {
    let id: UUID
    let start: Date
    let end: Date
    let action: SpeedDrivingAction
    let peakG: Double
    let score: Int
    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

struct TripReplayVisit: Equatable {
    let id: UUID
    let arrival: Date
    let departure: Date?
    let latitude: Double
    let longitude: Double
    let name: String
    func distance(to point: TripReplayPoint) -> Double {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: point.latitude, longitude: point.longitude))
    }
}

struct TripReplayPlace: Equatable {
    let name: String
    let latitude: Double
    let longitude: Double
    let radius: Double
    let priority: Int

    static func name(near point: TripReplayPoint, places: [Self]) -> String? {
        places.compactMap { place -> (Self, Double)? in
            guard place.radius.isFinite, (0...500).contains(place.radius),
                  !place.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  CLLocationCoordinate2DIsValid(.init(latitude: place.latitude, longitude: place.longitude)) else { return nil }
            let distance = CLLocation(latitude: place.latitude, longitude: place.longitude)
                .distance(from: CLLocation(latitude: point.latitude, longitude: point.longitude))
            return distance <= place.radius ? (place, distance) : nil
        }.sorted {
            $0.0.priority == $1.0.priority ? $0.1 < $1.1 : $0.0.priority < $1.0.priority
        }.first.map { String($0.0.name.prefix(512)) }
    }
}

struct TripReplayPrediction: Codable, Sendable {
    let createdAt: Date
    let latitude: Double
    let longitude: Double
    var isValid: Bool {
        createdAt.timeIntervalSinceReferenceDate.isFinite
            && CLLocationCoordinate2DIsValid(.init(latitude: latitude, longitude: longitude))
    }
}

struct TripReplay: Codable, Identifiable, Sendable {
    let id: UUID
    var points: [TripReplayPoint]
    var events: [TripReplayEvent] = []
    var originVisitID: UUID?
    var destinationVisitID: UUID?
    var originName: String?
    var destinationName: String?
    var prediction: TripReplayPrediction?
    var finished = false
    var isHabitualRoute: Bool {
        guard finished, let prediction, prediction.isValid, let last = points.last,
              abs(prediction.createdAt.timeIntervalSince(start)) <= 600 else { return false }
        return CLLocation(latitude: prediction.latitude, longitude: prediction.longitude)
            .distance(from: CLLocation(latitude: last.latitude, longitude: last.longitude)) <= 180
    }
    var start: Date { points.first?.time ?? .distantPast }
    var end: Date { points.last?.time ?? start }
    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
    var hasGaps: Bool { zip(points, points.dropFirst()).contains { !$0.connects(to: $1) } }
    var topSpeed: Double? { points.compactMap(\.speedKmh).max() }
    var highestAltitude: Double? { points.compactMap(\.altitude).max() }
    var lowestAltitude: Double? { points.compactMap(\.altitude).min() }
    var peakG: Double? {
        (points.compactMap { p in
            p.lateralG.flatMap { x in p.longitudinalG.map { hypot(x, $0) } }
        } + events.map(\.peakG)).max()
    }
    var distanceMeters: Double {
        zip(points, points.dropFirst()).reduce(0) { total, pair in
            let (a, b) = pair
            guard a.connects(to: b) else { return total }
            // Do not count stationary GPS wander as travelled distance.
            if let x = a.speedKmh, let y = b.speedKmh, max(x, y) < 2 { return total }
            return total + a.distance(to: b)
        }
    }
    var averageSpeed: Double? {
        var weighted = 0.0, seconds = 0.0
        for (a, b) in zip(points, points.dropFirst()) {
            guard a.connects(to: b), let x = a.speedKmh, let y = b.speedKmh else { continue }
            let dt = b.time.timeIntervalSince(a.time)
            weighted += (x + y) / 2 * dt
            seconds += dt
        }
        return seconds > 0 ? weighted / seconds : nil
    }
    var observedSeconds: TimeInterval {
        zip(points, points.dropFirst()).reduce(0) { $0 + ($1.0.connects(to: $1.1) ? $1.1.time.timeIntervalSince($1.0.time) : 0) }
    }
    var drivingSeconds: TimeInterval {
        zip(points, points.dropFirst()).reduce(0) { total, pair in
            total + (pair.0.connects(to: pair.1) && pair.0.driving && pair.1.driving
                ? pair.1.time.timeIntervalSince(pair.0.time) : 0)
        }
    }
    var routeSegments: [[TripReplayPoint]] {
        var segments: [[TripReplayPoint]] = []
        for point in points {
            if let last = segments.last?.last, last.connects(to: point) {
                segments[segments.count - 1].append(point)
            } else { segments.append([point]) }
        }
        return segments
    }

    // No interpolation through missing data, including background gaps.
    func displayCoordinate(at date: Date) -> CLLocationCoordinate2D? {
        guard let first = points.first, date >= first.time, date <= end else { return nil }
        var low = 0, high = points.count
        while low < high {
            let middle = (low + high) / 2
            if points[middle].time <= date { low = middle + 1 } else { high = middle }
        }
        let previous = points[max(0, low - 1)]
        if previous.time == date { return previous.coordinate }
        guard low < points.count, previous.connects(to: points[low]) else { return nil }
        let next = points[low]
        let fraction = date.timeIntervalSince(previous.time) / next.time.timeIntervalSince(previous.time)
        let longitudeDelta = (next.longitude - previous.longitude + 540).truncatingRemainder(dividingBy: 360) - 180
        let longitude = (previous.longitude + longitudeDelta * fraction + 540).truncatingRemainder(dividingBy: 360) - 180
        return .init(latitude: previous.latitude + (next.latitude - previous.latitude) * fraction, longitude: longitude)
    }

    func point(at date: Date) -> TripReplayPoint? {
        guard let first = points.first, date >= first.time, date <= end else { return nil }
        var low = 0, high = points.count
        while low < high {
            let middle = (low + high) / 2
            if points[middle].time <= date { low = middle + 1 } else { high = middle }
        }
        let previous = points[max(0, low - 1)]
        if abs(previous.time.timeIntervalSince(date)) < 0.05 { return previous }
        guard low < points.count, previous.connects(to: points[low]) else { return nil }
        let next = points[low]
        return date.timeIntervalSince(previous.time) <= next.time.timeIntervalSince(date) ? previous : next
    }
}

struct ReplayScrubMotion {
    private(set) var position: Double = 0
    private(set) var target: Double = 0
    private var response = 0.02
    var settled: Bool { abs(position - target) < 0.002 }

    mutating func seek(_ value: Double) {
        guard value.isFinite else { return }
        position = value
        target = value
    }

    mutating func drag(to value: Double, pointsPerSecond: Double) {
        guard value.isFinite, pointsPerSecond.isFinite else { return }
        target = value
        response = 0.018 + min(1, abs(pointsPerSecond) / 1000) * 0.26
    }

    mutating func release() { response = min(response, 0.08) }

    mutating func step(_ dt: Double) {
        guard dt.isFinite, dt > 0 else { return }
        position += (target - position) * (1 - exp(-min(dt, 0.1) / response))
        if settled { position = target }
    }
}

struct ReplayAltitudeFilter {
    private var window: [Double] = []
    private var previous: (time: Date, value: Double)?

    mutating func update(_ value: Double?, at time: Date, reset: Bool) -> Double? {
        if reset { self = Self() }
        guard let value else { self = Self(); return nil }
        window.append(value)
        if window.count > 3 { window.removeFirst() }
        guard window.count == 3 else { return nil }
        let median = window.sorted()[1]
        if let previous {
            let dt = time.timeIntervalSince(previous.time)
            guard dt > 0, abs(median - previous.value) <= max(15, dt * 6) else { return nil }
            let alpha = 1 - exp(-dt / 2)
            let result = previous.value + alpha * (median - previous.value)
            self.previous = (time, result)
            return result
        }
        previous = (time, median)
        return median
    }
}

struct TripReplayArchive: Codable, Sendable {
    var version = 1
    var trips: [TripReplay] = []
    var activeID: UUID?

    func validated() throws -> Self {
        guard version == 1, trips.count <= 100, trips.reduce(0, { $0 + $1.points.count }) <= 60000,
              Set(trips.map(\.id)).count == trips.count,
              activeID == nil || trips.contains(where: { $0.id == activeID && !$0.finished }) else {
            throw CocoaError(.coderReadCorrupt)
        }
        for trip in trips {
            guard !trip.points.isEmpty, trip.points.count <= 14400, trip.events.count <= 2000,
                  (trip.originName?.count ?? 0) <= 512, (trip.destinationName?.count ?? 0) <= 512,
                  trip.prediction?.isValid ?? true,
                  Set(trip.events.map(\.id)).count == trip.events.count,
                  trip.points.allSatisfy(\.isValid),
                  zip(trip.points, trip.points.dropFirst()).allSatisfy({ $0.time < $1.time }),
                  trip.events.allSatisfy({ $0.start >= trip.start && $0.end <= trip.end
                      && $0.end >= $0.start && $0.peakG.isFinite && (0...50).contains($0.peakG)
                      && (0...100).contains($0.score) && $0.action != .steady }) else {
                throw CocoaError(.coderReadCorrupt)
            }
        }
        return self
    }
}

struct TripReplayRecorder {
    private(set) var archive: TripReplayArchive
    private var preRoll: [TripReplayPoint] = []
    private var candidateSince: Date?
    private var lastMoving: Date?
    private var needsBreak = true
    private var altitudeFilter = ReplayAltitudeFilter()
    var current: TripReplay? { archive.trips.first { $0.id == archive.activeID } }
    var hasActiveTrip: Bool { archive.activeID != nil }

    init(archive: TripReplayArchive = .init()) {
        self.archive = archive
        lastMoving = archive.trips.first { $0.id == archive.activeID }?.end
    }

    mutating func pause() {
        needsBreak = true
        preRoll = []
        candidateSince = nil
        altitudeFilter = ReplayAltitudeFilter()
    }

    mutating func append(_ input: TripReplayPoint, automotive: Bool, pedestrian: Bool) {
        guard input.isValid else { needsBreak = true; return }
        if archive.activeID == nil, let previous = preRoll.last, input.time <= previous.time { return }
        if let last = current?.points.last {
            guard input.time > last.time else { return }
            if input.time.timeIntervalSince(last.time) > 1800 { finish(at: last.time) }
            else if input.time.timeIntervalSince(last.time) < 1 { return }
            else if !needsBreak, input.time.timeIntervalSince(last.time) <= 12,
                    last.distance(to: input) > max(80, input.time.timeIntervalSince(last.time) * 100 + last.accuracy + input.accuracy) {
                needsBreak = true
                altitudeFilter = ReplayAltitudeFilter()
                return
            }
        }
        var point = input
        point.driving = !pedestrian && (automotive || (point.speedKmh ?? 0) >= 15)
        if let last = current?.points.last, !last.connects(to: point) { needsBreak = true }
        point.breakBefore = needsBreak
        point.altitude = altitudeFilter.update(input.altitude, at: input.time, reset: needsBreak)
        needsBreak = false
        if archive.activeID == nil {
            preRoll.append(point)
            preRoll.removeAll { point.time.timeIntervalSince($0.time) > 10 }
            let driving = !pedestrian && (point.speedKmh ?? 0) >= (automotive ? 5 : 20)
            guard driving else { candidateSince = nil; return }
            if candidateSince == nil { candidateSince = point.time }
            guard point.time.timeIntervalSince(candidateSince!) >= 2 else { return }
            var points = preRoll
            points[0].breakBefore = true
            let trip = TripReplay(id: UUID(), points: points)
            archive.activeID = trip.id
            archive.trips.insert(trip, at: 0)
            preRoll = []
            lastMoving = point.time
            return
        }
        guard let index = archive.trips.firstIndex(where: { $0.id == archive.activeID }) else { return }
        let last = archive.trips[index].points.last!
        archive.trips[index].points.append(point)
        let moving = (point.speedKmh ?? 0) >= 3
            || (point.speedKmh == nil && last.connects(to: point) && last.distance(to: point) > 15)
        if moving { lastMoving = point.time }
        // Arrival callbacks may be delayed. A long stationary tail ends at the
        // last movement, not five minutes later; traffic stops remain in the trace.
        if let lastMoving, point.time.timeIntervalSince(lastMoving) >= 300 {
            finish(at: lastMoving)
        } else if archive.trips[index].points.count >= 14400 {
            finish(at: point.time)
        }
    }

    mutating func finish(at date: Date? = nil) {
        if let index = archive.trips.firstIndex(where: { $0.id == archive.activeID }) {
            if let date {
                archive.trips[index].points.removeAll { $0.time > date }
                archive.trips[index].events.removeAll { $0.end > date }
            }
            archive.trips[index].finished = true
            if archive.trips[index].points.count < 2 { archive.trips.remove(at: index) }
        }
        archive.activeID = nil
        lastMoving = nil
        pause()
    }

    mutating func add(_ event: TripReplayEvent) {
        guard let index = archive.trips.firstIndex(where: { $0.id == archive.activeID }),
              event.start >= archive.trips[index].start, event.end <= archive.trips[index].end.addingTimeInterval(2),
              archive.trips[index].events.count < 2000 else { return }
        // The GPS fix can lag the motion stream; wait for a later fix rather than
        // writing events beyond the persisted route's end.
        guard event.end <= archive.trips[index].end else { return }
        archive.trips[index].events.append(event)
    }

    mutating func link(visits: [TripReplayVisit]) {
        for index in archive.trips.indices {
            guard let first = archive.trips[index].points.first, let last = archive.trips[index].points.last else { continue }
            let origin = visits.filter {
                guard let departure = $0.departure else { return false }
                return departure <= first.time.addingTimeInterval(30)
                    && first.time.timeIntervalSince(departure) <= 1800 && $0.distance(to: first) <= 300
            }.max { ($0.departure ?? .distantPast) < ($1.departure ?? .distantPast) }
            let destination = visits.filter {
                $0.arrival > first.time && abs($0.arrival.timeIntervalSince(last.time)) <= 1800
                    && $0.distance(to: last) <= 300
                    && (archive.trips[index].id != archive.activeID || ($0.departure ?? .distantFuture) >= last.time)
            }.min { abs($0.arrival.timeIntervalSince(last.time)) < abs($1.arrival.timeIntervalSince(last.time)) }
            archive.trips[index].originVisitID = origin?.id
            archive.trips[index].originName = origin?.name ?? archive.trips[index].originName
            archive.trips[index].destinationVisitID = destination?.id
            archive.trips[index].destinationName = destination?.name ?? (archive.trips[index].finished ? archive.trips[index].destinationName : nil)
            if archive.trips[index].id == archive.activeID, let destination,
               destination.arrival <= last.time, destination.arrival > first.time.addingTimeInterval(10) {
                finish(at: destination.arrival)
                break
            }
        }
    }

    mutating func delete(_ id: UUID) {
        if archive.activeID == id { finish() }
        archive.trips.removeAll { $0.id == id }
    }

    mutating func resolveNames(places: [TripReplayPlace]) {
        for index in archive.trips.indices {
            if let first = archive.trips[index].points.first,
               let name = TripReplayPlace.name(near: first, places: places) {
                archive.trips[index].originName = name
            }
            if let last = archive.trips[index].points.last,
               let name = TripReplayPlace.name(near: last, places: places) {
                archive.trips[index].destinationName = name
            } else if !archive.trips[index].finished, archive.trips[index].destinationVisitID == nil {
                archive.trips[index].destinationName = nil
            }
        }
    }

    mutating func attachPrediction(_ value: TripReplayPrediction) {
        guard value.isValid, let id = archive.activeID,
              let index = archive.trips.firstIndex(where: { $0.id == id }),
              archive.trips[index].prediction == nil,
              abs(value.createdAt.timeIntervalSince(archive.trips[index].start)) <= 600 else { return }
        archive.trips[index].prediction = value
    }

    mutating func prune(now: Date, days: Int) {
        let cutoff = now.addingTimeInterval(-Double(days) * 86400)
        archive.trips.removeAll { $0.id != archive.activeID && $0.end < cutoff }
        while archive.trips.count > 100 || archive.trips.reduce(0, { $0 + $1.points.count }) > 60000 {
            guard let index = archive.trips.lastIndex(where: { $0.id != archive.activeID }) else { break }
            archive.trips.remove(at: index)
        }
    }
}
