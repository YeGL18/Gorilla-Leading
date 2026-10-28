import Foundation
import CryptoKit
import CoreFoundation

enum BackupFailure: Error {
    case invalid, unsupportedVersion, tooLarge, missingPhoto, persistence
}

/// A binary property list keeps original photo bytes without base64 expansion.
struct GorillaBackup: Codable, Sendable {
    static let maximumBytes = 80 * 1024 * 1024
    var format = "GorillaLeadingBackup"
    var version = 1
    var createdAt: Date
    var appVersion: String
    var standard: Data
    var shared: Data
    var photos: [String: Data]

    struct Envelope: Codable {
        var payload: Data
        var digest: Data
    }

    static let standardKeys: Set<String> = [
        "saved_destinations", "selected_destination_id", "visit_records", "motion_segments",
        "visitMinimumNewMinutes", "visitMinimumActiveMinutes", "visitActivateMinutes",
        "visitMatchRadiusMeters", "visitMergeConsecutive", "visitMergeMinutes", "visitDeactivateDays",
        "car_exit_events_v1", "seen_car_bluetooth_devices_v1", "my_car_bluetooth_device_v1",
        "trip_predict_place_catalog_v1", "trip_predict_patterns_v1", "trip_predict_recent_history_v1",
        "parking_photos_list", "HKLocationOverrides", "lastKnownLatitude", "lastKnownLongitude",
        "colorSchemeIndex", "appearanceMode", "capsuleAnimationStyle", "capsuleDarkGlassEnabled",
        "highFrequencyTracking", "mapTrackingAnimation", "speedBlurEnabled", "speedParallaxEnabled",
        "speedNumberHidden", "speedUnit", "orbMasterEnabled", "orbCapsule", "orbExpanded", "orbParkingMemory",
        "orbBackgroundHome", "orbBackgroundSpeed", "orbColorPreset", "orbOverlapGlowEnabled", "orbCanvasDitherEnabled",
        "darkKnightMode", "colorGroupMode", "useTimeBasedOrb", "mapStyleIndex", "vlmRecognitionEnabled",
        "floorConvention", "kalmanSmoothingEnabled", "launchAnimationEnabled", "parkingTimerColorHex",
        "bestRouteColorHex", "launchSoundVersion", "movementSoundVersion", "sfxAccelerationEnabled", "interactionHapticsEnabled",
        "parallaxMode", "outputAnimationStyle", "floorCurveCarIcon", "llm_shortcut_name",
        "trip_replays_v1", "tripReplayEnabled", "tripReplayRetentionDays",
        "meterDetectionEnabled", "meterVehicle", "meterMapRadius", "meterDestinationRadius",
        "meterNearbyRadius", "meterStatusRefreshInterval", "testItemOrder", "testItemFavorites",
        "trafficCameraEnabled", "trafficCameraSound", "trafficCameraSpeechFormat",
        "trafficCameraSlowDown", "trafficCameraRedLightSpeech"
    ]
    static let sharedKeys: Set<String> = [
        "parking_floor_store_v1", "deleted_parking_points_v1", "deleted_places_v1",
        "parkingFloorMode", "parking_altitude_results_v1", "parkingStartTime", "parkingEntryTime",
        "hasDeparted", "manualDeparted", "parkingDepartureTime", "timerRunning",
        "lastKnownArrivalDate", "isNonAutomotiveArrival", "parkingEntryLocation",
        "parkingPhotoContributions", "parkingTimerColorHex", "bestRouteColorHex"
    ]

    static func preferences(_ defaults: UserDefaults, keys: Set<String>, domain: String) throws -> Data {
        let values = (defaults.persistentDomain(forName: domain) ?? [:]).filter { keys.contains($0.key) }
        return try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
    }

    func values(shared: Bool) throws -> [String: Any] {
        let bytes = shared ? self.shared : standard
        guard let values = try PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any],
              Set(values.keys).isSubset(of: shared ? Self.sharedKeys : Self.standardKeys) else {
            throw BackupFailure.invalid
        }
        return values
    }

    func validated() throws -> Self {
        guard format == "GorillaLeadingBackup" else { throw BackupFailure.invalid }
        guard version == 1 else { throw BackupFailure.unsupportedVersion }
        guard standard.count + shared.count + photos.values.reduce(0, { $0 + $1.count }) < Self.maximumBytes,
              photos.count <= 3 else { throw BackupFailure.tooLarge }
        let standard = try values(shared: false)
        let shared = try values(shared: true)
        let blobs: Set<String> = ["saved_destinations", "selected_destination_id", "visit_records", "motion_segments", "trip_replays_v1",
            "car_exit_events_v1", "seen_car_bluetooth_devices_v1", "my_car_bluetooth_device_v1",
            "trip_predict_place_catalog_v1", "trip_predict_patterns_v1", "trip_predict_recent_history_v1",
            "parking_photos_list", "testItemOrder", "testItemFavorites", "parking_floor_store_v1",
            "deleted_parking_points_v1", "deleted_places_v1", "parking_altitude_results_v1", "parkingPhotoContributions"]
        let strings: Set<String> = ["parkingTimerColorHex", "bestRouteColorHex", "floorCurveCarIcon",
            "llm_shortcut_name", "meterVehicle", "parkingEntryLocation", "parallaxMode", "speedUnit"]
        let dates: Set<String> = ["parkingStartTime", "parkingEntryTime", "parkingDepartureTime", "lastKnownArrivalDate"]
        for values in [standard, shared] {
            for (key, value) in values {
                if blobs.contains(key) {
                    guard value is Data else { throw BackupFailure.invalid }
                } else if strings.contains(key) {
                    guard let string = value as? String, string.count <= 4096 else { throw BackupFailure.invalid }
                } else if dates.contains(key) {
                    guard value is Date else { throw BackupFailure.invalid }
                } else if key == "HKLocationOverrides" {
                    guard let overrides = value as? [String: [String: Double]], overrides.values.allSatisfy({
                        guard let lat = $0["lat"], let lon = $0["lon"] else { return false }
                        return lat.isFinite && lon.isFinite && (-90...90).contains(lat) && (-180...180).contains(lon)
                    }) else { throw BackupFailure.invalid }
                } else {
                    guard let number = value as? NSNumber, number.doubleValue.isFinite else { throw BackupFailure.invalid }
                }
            }
        }
        for (name, data) in photos {
            guard Self.safePhotoName(name), !data.isEmpty else { throw BackupFailure.invalid }
        }
        if let data = standard["parking_photos_list"] as? Data {
            guard let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  list.count <= 3 else { throw BackupFailure.invalid }
            let names = try list.map { item -> String in
                guard let name = item["fileName"] as? String, Self.safePhotoName(name) else {
                    throw BackupFailure.invalid
                }
                return name
            }
            guard Set(names) == Set(photos.keys), Set(names).count == names.count else { throw BackupFailure.missingPhoto }
        } else if !photos.isEmpty { throw BackupFailure.invalid }
        return self
    }

    static func safePhotoName(_ name: String) -> Bool {
        guard name.hasSuffix(".jpg"), name.count == 40 else { return false }
        return UUID(uuidString: String(name.dropLast(4))) != nil
    }

    func encoded() throws -> Data {
        _ = try validated()
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let payload = try encoder.encode(self)
        let data = try encoder.encode(Envelope(payload: payload, digest: Data(SHA256.hash(data: payload))))
        guard data.count <= Self.maximumBytes else { throw BackupFailure.tooLarge }
        return data
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumBytes else { throw BackupFailure.tooLarge }
        let envelope = try PropertyListDecoder().decode(Envelope.self, from: data)
        guard Data(SHA256.hash(data: envelope.payload)) == envelope.digest else { throw BackupFailure.invalid }
        return try PropertyListDecoder().decode(Self.self, from: envelope.payload).validated()
    }

    func count(_ key: String, shared: Bool = false) -> Int {
        guard let bytes = try? values(shared: shared)[key] as? Data,
              let object = try? JSONSerialization.jsonObject(with: bytes) else { return 0 }
        if key == "trip_replays_v1" { return ((object as? [String: Any])?["trips"] as? [Any])?.count ?? 0 }
        return (object as? [Any])?.count ?? 0
    }
}

/// Runs without suspension on the main thread in the app, so model callbacks
/// cannot save stale state halfway through the defaults/file transaction.
struct BackupTransaction {
    let standard: UserDefaults
    let shared: UserDefaults
    let documents: URL
    let recoveryURL: URL
    var replayURL: URL? = nil

    func apply(_ backup: GorillaBackup, afterFiles: () throws -> Void = {}) throws {
        _ = try backup.validated()
        let fm = FileManager.default
        let folder = documents.appendingPathComponent("parking_photos", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        // Only our own photo filenames are replaced. Unrelated documents are untouched.
        for url in try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        where GorillaBackup.safePhotoName(url.lastPathComponent) {
            try fm.removeItem(at: url)
        }
        for (name, data) in backup.photos {
            try data.write(to: folder.appendingPathComponent(name), options: .atomic)
        }
        let groupValues = try backup.values(shared: true)
        let lots = groupValues["parking_floor_store_v1"] as? Data ?? Data("[]".utf8)
        try lots.write(to: documents.appendingPathComponent("parking_lots_backup.json"), options: .atomic)
        let standardValues = try backup.values(shared: false)
        if let replayURL {
            try fm.createDirectory(at: replayURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let replay = standardValues["trip_replays_v1"] as? Data {
                try replay.write(to: replayURL, options: .atomic)
            } else if fm.fileExists(atPath: replayURL.path) { try fm.removeItem(at: replayURL) }
        }
        try afterFiles()
        for (defaults, keys, values) in [
            (standard, GorillaBackup.standardKeys, standardValues),
            (shared, GorillaBackup.sharedKeys, groupValues)
        ] {
            for key in keys { defaults.removeObject(forKey: key) }
            for (key, value) in values where replayURL == nil || key != "trip_replays_v1" { defaults.set(value, forKey: key) }
            guard defaults.synchronize() else { throw BackupFailure.persistence }
        }
    }

    func restore(_ target: GorillaBackup, safety: GorillaBackup, afterFiles: () throws -> Void = {}) throws {
        try FileManager.default.createDirectory(at: recoveryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try safety.encoded().write(to: recoveryURL, options: .atomic)
        do {
            try apply(target, afterFiles: afterFiles)
            try FileManager.default.removeItem(at: recoveryURL)
        } catch {
            // Keep the journal if rollback fails; next launch retries before stores hydrate.
            try apply(safety)
            try FileManager.default.removeItem(at: recoveryURL)
            throw error
        }
    }

    func recoverIfNeeded() throws {
        guard FileManager.default.fileExists(atPath: recoveryURL.path) else { return }
        try apply(GorillaBackup.decode(Data(contentsOf: recoveryURL)))
        try FileManager.default.removeItem(at: recoveryURL)
    }
}
