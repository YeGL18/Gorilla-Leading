import Foundation

@main struct BackupChecks {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("backup-check-\(UUID())")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let standardName = "backup-check-standard-\(UUID())"
        let sharedName = "backup-check-shared-\(UUID())"
        let standard = UserDefaults(suiteName: standardName)!
        let shared = UserDefaults(suiteName: sharedName)!
        defer { standard.removePersistentDomain(forName: standardName); shared.removePersistentDomain(forName: sharedName) }
        func plist(_ values: [String: Any]) throws -> Data {
            try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        }
        let name = "\(UUID()).jpg"
        let photoList = try JSONSerialization.data(withJSONObject: [["fileName": name]])
        let before = GorillaBackup(createdAt: Date(), appVersion: "1", standard: try plist([
            "visit_records": Data("[]".utf8), "parking_photos_list": photoList, "appearanceMode": 2,
            "parallaxMode": "subtle", "speedUnit": "mph", "interactionHapticsEnabled": false,
            "trafficCameraSpeechFormat": "short", "trafficCameraSpeechLanguage": "ja",
            "trip_replays_v1": Data("{\"version\":1,\"trips\":[]}".utf8),
            "tripReplayEnabled": true, "tripReplayRetentionDays": 30
        ]), shared: try plist(["parkingEntryTime": Date(timeIntervalSince1970: 123)]), photos: [name: Data([1, 2, 3])])
        let after = GorillaBackup(createdAt: Date(), appVersion: "2", standard: try plist([
            "saved_destinations": Data("[]".utf8), "appearanceMode": 1
        ]), shared: try plist(["parking_floor_store_v1": Data("[]".utf8)]), photos: [:])
        let transaction = BackupTransaction(standard: standard, shared: shared, documents: root,
            recoveryURL: root.appendingPathComponent("journal"))
        let encoded = try before.encoded()
        let decoded = try GorillaBackup.decode(encoded)
        precondition(decoded.photos == before.photos && decoded.standard == before.standard)
        try transaction.apply(before)
        standard.set(["zh-Hant"], forKey: "AppleLanguages")
        standard.set("secret", forKey: "unrelatedKey")
        try transaction.restore(after, safety: before)
        precondition(standard.integer(forKey: "appearanceMode") == 1)
        precondition(standard.object(forKey: "speedUnit") == nil)
        precondition(standard.object(forKey: "interactionHapticsEnabled") == nil)
        precondition(standard.object(forKey: "trip_replays_v1") == nil)
        precondition(standard.object(forKey: "tripReplayEnabled") == nil)
        precondition(standard.object(forKey: "visit_records") == nil)
        precondition(standard.string(forKey: "unrelatedKey") == "secret")
        precondition(standard.stringArray(forKey: "AppleLanguages") == ["zh-Hant"])
        precondition(!fm.fileExists(atPath: root.appendingPathComponent("parking_photos/\(name)").path))
        precondition(!fm.fileExists(atPath: transaction.recoveryURL.path))
        try transaction.apply(before)
        enum Injected: Error { case failure }
        do {
            try transaction.restore(after, safety: before) { throw Injected.failure }
            preconditionFailure("Expected rollback")
        } catch Injected.failure {}
        precondition(standard.integer(forKey: "appearanceMode") == 2)
        precondition(standard.string(forKey: "parallaxMode") == "subtle")
        precondition(standard.string(forKey: "speedUnit") == "mph")
        precondition(standard.string(forKey: "trafficCameraSpeechLanguage") == "ja")
        precondition(standard.string(forKey: "trafficCameraSpeechFormat") == "short")
        precondition(standard.object(forKey: "interactionHapticsEnabled") as? Bool == false)
        precondition(standard.data(forKey: "trip_replays_v1") == Data("{\"version\":1,\"trips\":[]}".utf8))
        precondition(standard.bool(forKey: "tripReplayEnabled"))
        precondition(standard.integer(forKey: "tripReplayRetentionDays") == 30)
        let restoredPhoto = try Data(contentsOf: root.appendingPathComponent("parking_photos/\(name)"))
        precondition(restoredPhoto == before.photos[name])
        // A terminated process leaves a journal; next launch restores the old snapshot.
        try encoded.write(to: transaction.recoveryURL)
        try transaction.apply(after)
        try transaction.recoverIfNeeded()
        precondition(standard.integer(forKey: "appearanceMode") == 2)
        precondition(shared.object(forKey: "parkingEntryTime") as? Date == Date(timeIntervalSince1970: 123))
        let replayURL = root.appendingPathComponent("replays/history.json")
        let fileTransaction = BackupTransaction(standard: standard, shared: shared, documents: root,
            recoveryURL: root.appendingPathComponent("file-journal"), replayURL: replayURL)
        try fileTransaction.apply(before)
        let restoredReplay = try Data(contentsOf: replayURL)
        precondition(restoredReplay == Data("{\"version\":1,\"trips\":[]}".utf8))
        precondition(standard.object(forKey: "trip_replays_v1") == nil)
        try fileTransaction.restore(after, safety: before)
        precondition(!fm.fileExists(atPath: replayURL.path))
        do {
            try fileTransaction.restore(after, safety: before) { throw Injected.failure }
            preconditionFailure("Expected file rollback")
        } catch Injected.failure {}
        let rolledBackReplay = try Data(contentsOf: replayURL)
        precondition(rolledBackReplay == Data("{\"version\":1,\"trips\":[]}".utf8))
        func rejected(_ snapshot: GorillaBackup) {
            do { _ = try snapshot.encoded(); preconditionFailure("Expected rejection") } catch {}
        }
        var invalid = before
        invalid.version = 2; rejected(invalid)
        invalid = before; invalid.photos = ["../unsafe.jpg": Data([1])]; rejected(invalid)
        invalid = before; invalid.photos = [:]; rejected(invalid)
        invalid = before; invalid.standard = try plist(["AppleLanguages": ["en"]]); rejected(invalid)
        invalid = before; invalid.standard = try plist(["appearanceMode": "dark"]); rejected(invalid)
        invalid = before; invalid.standard = try plist(["HKLocationOverrides": ["invalid": ["lat": 91.0, "lon": 114.0]]]); rejected(invalid)
        var damaged = encoded
        damaged[damaged.count / 2] ^= 1
        do { _ = try GorillaBackup.decode(damaged); preconditionFailure("Expected integrity rejection") } catch {}
        let preferences = try GorillaBackup.preferences(standard, keys: GorillaBackup.standardKeys, domain: standardName)
        let exported = try PropertyListSerialization.propertyList(from: preferences, format: nil) as! [String: Any]
        precondition(exported["AppleLanguages"] == nil && exported["unrelatedKey"] == nil)
        print("Backup checks passed: round trip, replacement, photo restore, rollback, crash recovery, language preservation, validation and integrity.")
    }
}
