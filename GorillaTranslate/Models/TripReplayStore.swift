import Foundation
import Combine
import UIKit
import CoreLocation

@MainActor
final class TripReplayStore: ObservableObject {
    static let shared = TripReplayStore()
    nonisolated static let storageKey = "trip_replays_v1"
    nonisolated static var defaultStorageURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TripReplay", isDirectory: true).appendingPathComponent("history.json")
    }
    @Published private(set) var trips: [TripReplay] = []
    @Published private(set) var activeID: UUID?
    @Published private(set) var enabled: Bool
    @Published private(set) var retentionDays: Int
    @Published private(set) var storageError: String?
    private var recorder = TripReplayRecorder()
    private let defaults: UserDefaults
    private let storageURL: URL
    private let persistence: TripReplayPersistence
    private var foreground = false
    private var game = false
    private var pedestrian = false
    private var lastSaved = Date.distantPast
    private var force: SpeedGForce?
    private var tracker = SpeedActionTracker()
    private var lastEventTime: TimeInterval?
    private var pendingEvents: [TripReplayEvent] = []
    private var subscriptions: Set<AnyCancellable> = []
    private var visits: [TripReplayVisit] = []
    private var places: [TripReplayPlace] = []
    private var pendingPrediction: TripReplayPrediction?
    private var archiveReadable = true

    init(defaults: UserDefaults = .standard, storageURL: URL = TripReplayStore.defaultStorageURL) {
        self.defaults = defaults
        self.storageURL = storageURL
        persistence = TripReplayPersistence(defaults: defaults, url: storageURL)
        enabled = defaults.object(forKey: "tripReplayEnabled") as? Bool ?? true
        let days = defaults.integer(forKey: "tripReplayRetentionDays")
        retentionDays = [7, 30, 90].contains(days) ? days : 30
        reload()
        GForceParallaxMotion.shared.$reading.sink { [weak self] in self?.recordForce($0) }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)
            .sink { [weak self] _ in self?.updateOrientation() }.store(in: &subscriptions)
    }

    var isRecording: Bool { enabled && foreground && !game && activeID != nil }

    func setEnabled(_ value: Bool) {
        guard archiveReadable || !value else { return }
        enabled = value
        defaults.set(value, forKey: "tripReplayEnabled")
        if !value {
            recorder.finish()
            recorder.resolveNames(places: places)
            pendingPrediction = nil
            resetMotion()
        }
        publish()
        _ = flush()
    }

    func setRetention(_ days: Int) {
        guard [7, 30, 90].contains(days) else { return }
        retentionDays = days
        defaults.set(days, forKey: "tripReplayRetentionDays")
        recorder.prune(now: .now, days: days)
        publish()
        _ = flush()
    }

    func setContext(foreground: Bool, game: Bool) {
        guard foreground != self.foreground || game != self.game else { return }
        self.foreground = foreground
        self.game = game
        if !foreground || game {
            pendingPrediction = nil
            recorder.pause()
            resetMotion()
            _ = flush()
        } else {
            // Never connect the last background/previous-process fix to a new one.
            recorder.pause()
            updateOrientation()
        }
        objectWillChange.send()
    }

    func record(_ location: CLLocation, automotive: Bool, pedestrian: Bool, now: Date = .now) {
        guard enabled, foreground, !game else { return }
        self.pedestrian = pedestrian
        guard var point = TripReplayPoint.capture(location, now: now) else {
            recorder.pause()
            resetMotion()
            return
        }
        if !pedestrian, (point.speedKmh ?? 0) >= 5, let force {
            point.lateralG = force.lateral
            point.longitudinalG = force.longitudinal
        }
        let previousActive = recorder.archive.activeID
        recorder.append(point, automotive: automotive, pedestrian: pedestrian)
        if let pendingPrediction { recorder.attachPrediction(pendingPrediction) }
        if recorder.current?.prediction != nil { pendingPrediction = nil }
        for event in pendingEvents where event.end <= (recorder.current?.end ?? .distantPast) { recorder.add(event) }
        pendingEvents.removeAll { $0.end <= (recorder.current?.end ?? .distantFuture) }
        if previousActive != recorder.archive.activeID {
            recorder.link(visits: visits)
            recorder.resolveNames(places: places)
        }
        recorder.prune(now: now, days: retentionDays)
        if now.timeIntervalSince(lastSaved) >= 30 { recorder.resolveNames(places: places) }
        publish()
        if recorder.hasActiveTrip {
            updateOrientation()
            GForceParallaxMotion.shared.start(consumer: "replay")
        } else { resetMotion() }
        if previousActive != recorder.archive.activeID || now.timeIntervalSince(lastSaved) >= 30 || !recorder.hasActiveTrip { save() }
    }

    func link(visits: [TripReplayVisit]) {
        guard visits != self.visits else { return }
        self.visits = visits
        recorder.link(visits: visits)
        recorder.resolveNames(places: places)
        publish()
        if !recorder.hasActiveTrip { resetMotion() }
        save()
    }

    func updatePlaces(_ values: [TripReplayPlace]) {
        guard values != places else { return }
        places = values
        recorder.link(visits: visits)
        recorder.resolveNames(places: places)
        publish()
        if !recorder.hasActiveTrip { resetMotion() }
        save()
    }

    func notePrediction(_ value: TripReplayPrediction) {
        guard enabled, foreground, !game, value.isValid,
              recorder.current?.prediction == nil,
              abs(value.createdAt.timeIntervalSinceNow) <= 600 else { return }
        pendingPrediction = value
        recorder.attachPrediction(value)
    }

    private func recordForce(_ value: SpeedGForce?) {
        force = value
        guard isRecording, !pedestrian, let last = recorder.current?.points.last,
              Date().timeIntervalSince(last.time) <= 5, (last.speedKmh ?? 0) >= 5 else {
            tracker = SpeedActionTracker()
            return
        }
        let uptime = ProcessInfo.processInfo.systemUptime
        tracker.update(value, at: uptime)
        if let result = tracker.lastCompleted, result.endedAt != lastEventTime {
            lastEventTime = result.endedAt
            let end = Date().addingTimeInterval(result.endedAt - uptime)
            pendingEvents.append(TripReplayEvent(id: UUID(), start: end.addingTimeInterval(-result.duration),
                end: end, action: result.action, peakG: result.peak, score: result.score))
        }
    }

    private func updateOrientation() {
        guard foreground, !game else { return }
        let orientation = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?.effectiveGeometry.interfaceOrientation
        let angle: Double = orientation == .landscapeLeft ? .pi / 2 : orientation == .landscapeRight ? -.pi / 2
            : orientation == .portraitUpsideDown ? .pi : 0
        GForceParallaxMotion.shared.setScreenRotation(angle)
    }

    private func resetMotion() {
        GForceParallaxMotion.shared.stop(consumer: "replay")
        force = nil
        tracker = SpeedActionTracker()
        lastEventTime = nil
        pendingEvents = []
    }

    private func publish() {
        trips = recorder.archive.trips
        activeID = recorder.archive.activeID
    }

    func delete(_ id: UUID) {
        recorder.delete(id)
        if !recorder.hasActiveTrip { resetMotion() }
        publish()
        _ = flush()
    }

    func deleteAll() {
        archiveReadable = true
        storageError = nil
        recorder = TripReplayRecorder()
        resetMotion()
        publish()
        _ = flush()
    }

    func finish() {
        recorder.finish()
        recorder.link(visits: visits)
        recorder.resolveNames(places: places)
        resetMotion()
        publish()
        _ = flush()
    }

    private func save() {
        guard archiveReadable else { return }
        lastSaved = .now
        let snapshot = recorder.archive
        persistence.save(snapshot) { [weak self] success in
            if !success {
                Task { @MainActor in self?.storageError = String(localized: "Replay Save Failed") }
            }
        }
    }

    @discardableResult func flush() -> Bool {
        guard archiveReadable else { return false }
        let snapshot = recorder.archive
        do {
            try persistence.flush(snapshot)
            lastSaved = .now
            return true
        } catch {
            storageError = String(localized: "Replay Save Failed")
            return false
        }
    }

    func prepareForRestore() {
        setContext(foreground: false, game: false)
        persistence.drain()
    }

    func backupData() throws -> Data? {
        persistence.drain()
        return try readArchiveFile()
    }

    private func readArchiveFile() throws -> Data? {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return nil }
        let size = try storageURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size <= 32 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        return try Data(contentsOf: storageURL)
    }

    func reload() {
        persistence.drain()
        archiveReadable = true
        storageError = nil
        enabled = defaults.object(forKey: "tripReplayEnabled") as? Bool ?? true
        let days = defaults.integer(forKey: "tripReplayRetentionDays")
        retentionDays = [7, 30, 90].contains(days) ? days : 30
        do {
            let data: Data?
            if FileManager.default.fileExists(atPath: storageURL.path) { data = try readArchiveFile() }
            else { data = defaults.data(forKey: Self.storageKey) }
            if let data {
                let archive = try JSONDecoder().decode(TripReplayArchive.self, from: data).validated()
                recorder = TripReplayRecorder(archive: archive)
                recorder.prune(now: .now, days: retentionDays)
            } else { recorder = TripReplayRecorder() }
        } catch {
            // Keep unreadable bytes intact rather than replacing the history.
            storageError = String(localized: "Replay Read Failed")
            archiveReadable = false
            enabled = false
        }
        publish()
    }
}

// Only the serial queue accesses persistence work. Draining it before restore
// prevents an older queued snapshot from overwriting restored/deleted history.
private final class TripReplayPersistence: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.gorilla.trip-replay-storage", qos: .utility)
    private let defaults: UserDefaults
    private let url: URL
    init(defaults: UserDefaults, url: URL) { self.defaults = defaults; self.url = url }
    func save(_ archive: TripReplayArchive, completion: @escaping @Sendable (Bool) -> Void) {
        queue.async {
            do { try self.write(archive); completion(true) }
            catch { completion(false) }
        }
    }
    func flush(_ archive: TripReplayArchive) throws {
        try queue.sync {
            try write(archive)
            guard defaults.synchronize() else { throw CocoaError(.fileWriteUnknown) }
        }
    }
    func drain() { queue.sync { } }
    private func write(_ archive: TripReplayArchive) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(archive).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        // Preferences hold settings only. Migrate any early/backup blob after a
        // successful file write, never before the original data is safely saved.
        defaults.removeObject(forKey: TripReplayStore.storageKey)
    }
}
