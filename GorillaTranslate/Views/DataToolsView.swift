import SwiftUI
import UniformTypeIdentifiers
import WidgetKit
import ImageIO

extension UTType {
    static let gorillaBackup = UTType(exportedAs: "com.gorilla.leading.backup", conformingTo: .data)
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.gorillaBackup] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              data.count <= GorillaBackup.maximumBytes else { throw BackupFailure.tooLarge }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

@MainActor
final class BackupController: ObservableObject {
    static let shared = BackupController()
    @Published var busy = false
    @Published var restoring = false
    @Published var generation = UUID()
    @Published var restoreMessage: String?
    @Published var recoveryRequired = false
    private(set) var lastRestoreHadSafetyCopy = false
    static let group = "group.com.gorilla.translate"
    nonisolated static var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    nonisolated static var support: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0] }
    nonisolated static var safetyURL: URL { support.appendingPathComponent("before-restore.gorillabackup") }
    static var transaction: BackupTransaction {
        BackupTransaction(standard: .standard, shared: UserDefaults(suiteName: group)!,
            documents: documents, recoveryURL: support.appendingPathComponent("restore-recovery.gorillabackup"),
            replayURL: TripReplayStore.defaultStorageURL)
    }

    private func capture() throws -> GorillaBackup {
        guard UIApplication.shared.isProtectedDataAvailable else { throw BackupFailure.persistence }
        guard TripReplayStore.shared.flush() else { throw BackupFailure.persistence }
        var snapshot = GorillaBackup(createdAt: Date(), appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            standard: try GorillaBackup.preferences(.standard, keys: GorillaBackup.standardKeys,
                domain: Bundle.main.bundleIdentifier!),
            shared: try GorillaBackup.preferences(UserDefaults(suiteName: Self.group)!, keys: GorillaBackup.sharedKeys, domain: Self.group),
            photos: [:])
        if let replay = try TripReplayStore.shared.backupData() {
            var values = try snapshot.values(shared: false)
            values[TripReplayStore.storageKey] = replay
            snapshot.standard = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        }
        return snapshot
    }

    nonisolated private static func attachPhotos(_ snapshot: GorillaBackup) throws -> GorillaBackup {
        var snapshot = snapshot
        let values = try snapshot.values(shared: false)
        if let data = values["parking_photos_list"] as? Data {
            let photos = try JSONDecoder().decode([ParkingPhoto].self, from: data)
            for photo in photos {
                guard GorillaBackup.safePhotoName(photo.fileName) else { throw BackupFailure.invalid }
                let url = documents.appendingPathComponent("parking_photos").appendingPathComponent(photo.fileName)
                guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                      size < GorillaBackup.maximumBytes else { throw BackupFailure.tooLarge }
                snapshot.photos[photo.fileName] = try Data(contentsOf: url)
            }
        }
        return try snapshot.validated()
    }

    func export() async throws -> Data {
        busy = true
        defer { busy = false }
        let snapshot = try capture()
        return try await Task.detached(priority: .userInitiated) {
            let complete = try Self.attachPhotos(snapshot)
            try Self.validateModels(complete)
            return try complete.encoded()
        }.value
    }

    func read(_ url: URL) async throws -> GorillaBackup {
        busy = true
        defer { busy = false }
        return try await Task.detached(priority: .userInitiated) {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            // Coordinate reads from Files/iCloud rather than assuming a local URL.
            var coordinationError: NSError?
            var result: Result<GorillaBackup, Error> = .failure(BackupFailure.invalid)
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { localURL in
                result = Result {
                    let size = try localURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
                    guard size <= GorillaBackup.maximumBytes else { throw BackupFailure.tooLarge }
                    let snapshot = try GorillaBackup.decode(Data(contentsOf: localURL))
                    try Self.validateModels(snapshot)
                    return snapshot
                }
            }
            if let coordinationError { throw coordinationError }
            return try result.get()
        }.value
    }

    /// Check domain schemas before any settings or photos are replaced.
    nonisolated static func validateModels(_ snapshot: GorillaBackup) throws {
        let standard = try snapshot.values(shared: false)
        let shared = try snapshot.values(shared: true)
        func check<T: Decodable>(_ key: String, _ type: T.Type, in values: [String: Any]) throws {
            guard let value = values[key] else { return }
            guard let data = value as? Data else { throw BackupFailure.invalid }
            _ = try JSONDecoder().decode(type, from: data)
        }
        try check("saved_destinations", [Destination].self, in: standard)
        try check("selected_destination_id", UUID.self, in: standard)
        try check("visit_records", [LocationManager.VisitRecord].self, in: standard)
        try check("motion_segments", [MotionSegment].self, in: standard)
        if let data = standard[TripReplayStore.storageKey] as? Data {
            _ = try JSONDecoder().decode(TripReplayArchive.self, from: data).validated()
        }
        try check("car_exit_events_v1", [CarExitEvent].self, in: standard)
        try check("seen_car_bluetooth_devices_v1", [CarBluetoothDevice].self, in: standard)
        try check("my_car_bluetooth_device_v1", CarBluetoothDevice.self, in: standard)
        try check("trip_predict_place_catalog_v1", [String: PlaceInfo].self, in: standard)
        try check("trip_predict_patterns_v1", [String: TripPatternRecord].self, in: standard)
        try check("trip_predict_recent_history_v1", [PlaceInfo].self, in: standard)
        try check("parking_photos_list", [ParkingPhoto].self, in: standard)
        try check("parking_floor_store_v1", [ParkingLotRecord].self, in: shared)
        try check("deleted_parking_points_v1", [DeletedPointEntry].self, in: shared)
        try check("deleted_places_v1", [DeletedPlaceEntry].self, in: shared)
        try check("parking_altitude_results_v1", [ParkingAltitudeResult].self, in: shared)
        try check("parkingPhotoContributions", [UUID: [String: String]].self, in: shared)
        if let data = shared["parking_floor_store_v1"] as? Data {
            let lots = try JSONDecoder().decode([ParkingLotRecord].self, from: data)
            guard lots.allSatisfy({ lot in
                CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: lot.centerLatitude, longitude: lot.centerLongitude)) && lot.radiusMeters.isFinite
                    && lot.radiusMeters >= 0 && lot.radiusMeters <= 10000
                    && lot.points.allSatisfy { CLLocationCoordinate2DIsValid($0.coordinate) }
            }) else { throw BackupFailure.invalid }
        }
        for data in snapshot.photos.values {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 12000, height <= 12000,
                  width * height <= 64_000_000,
                  CGImageSourceGetType(source) as String? == UTType.jpeg.identifier else { throw BackupFailure.invalid }
        }
    }

    func restore(_ target: GorillaBackup) async throws {
        lastRestoreHadSafetyCopy = false
        busy = true
        restoring = true
        defer { busy = false; restoring = false }
        try await Task.detached(priority: .userInitiated) {
            _ = try target.validated()
            try Self.validateModels(target)
        }.value
        // Detach the old ContentView first; its timers cannot later overwrite restored state.
        try await Task.sleep(for: .milliseconds(150))
        let before = try capture()
        let safety = try await Task.detached(priority: .userInitiated) {
            try Self.attachPhotos(before)
        }.value
        let safetyData = try await Task.detached(priority: .userInitiated) { try safety.encoded() }.value
        try FileManager.default.createDirectory(at: Self.support, withIntermediateDirectories: true)
        try safetyData.write(to: Self.safetyURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        lastRestoreHadSafetyCopy = true
        ParkingFloorStore.shared.barometer.cancelCapture()
        TripReplayStore.shared.prepareForRestore()
        await GorillaActivityManager.shared.resetForRestore()
        do {
            try Self.transaction.restore(target, safety: safety)
        } catch {
            if FileManager.default.fileExists(atPath: Self.transaction.recoveryURL.path) {
                recoveryRequired = true
            } else { reloadStores() }
            throw error
        }
        reloadStores()
        restoreMessage = String(localized: "Backup Restored")
    }

    func retryRecovery() {
        do {
            try Self.transaction.recoverIfNeeded()
            reloadStores()
            recoveryRequired = false
        } catch { restoreMessage = String(localized: "Restore failed. The safety copy has been retained.") }
    }

    private func reloadStores() {
        ParkingPhoto.evictAllCache()
        ParkingFloorStore.shared.reloadAfterRestore()
        TripPredictor.shared.reloadAfterRestore()
        DestinationManager.shared.reloadAfterRestore()
        LocationManager.shared.reloadAfterRestore()
        TripReplayStore.shared.reload()
        LanguageManager.migrateLegacyOverride()
        WidgetCenter.shared.reloadAllTimelines()
        generation = UUID()
    }
}

struct BackupToolsView: View {
    @ObservedObject private var controller = BackupController.shared
    @State private var document: BackupDocument?
    @State private var exporting = false
    @State private var importing = false
    @State private var candidate: GorillaBackup?
    @State private var confirming = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                Button { export() } label: { Label("Export Backup", systemImage: "square.and.arrow.up") }
                Button { importing = true } label: { Label("Restore Backup", systemImage: "square.and.arrow.down") }
                if FileManager.default.fileExists(atPath: BackupController.safetyURL.path) {
                    Button { exportSafety() } label: { Label("Save Safety Copy", systemImage: "clock.arrow.circlepath") }
                }
            } footer: {
                Text("Backups contain your places, visits, parking records, settings and saved photos. They are not encrypted. Keep them somewhere private. App language and device permissions are not replaced.")
            }
            if let candidate {
                Section("Backup Preview") {
                    LabeledContent("Created", value: candidate.createdAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("App Version", value: candidate.appVersion)
                    LabeledContent("Destinations", value: String(candidate.count("saved_destinations")))
                    LabeledContent("Visits", value: String(candidate.count("visit_records")))
                    LabeledContent("Trip Replay", value: String(candidate.count("trip_replays_v1")))
                    LabeledContent("Parking Lots", value: String(candidate.count("parking_floor_store_v1", shared: true)))
                    LabeledContent("Photos", value: String(candidate.photos.count))
                    Button("Replace Current Data", role: .destructive) { confirming = true }
                    Button("取消", role: .cancel) { self.candidate = nil }
                }
            }
            if controller.busy { ProgressView() }
        }
        .disabled(controller.busy)
        .navigationTitle("Backup & Restore")
        .fileExporter(isPresented: $exporting, document: document, contentType: .gorillaBackup,
            defaultFilename: "Gorilla-\(Date().formatted(.iso8601.year().month().day()))") { result in
                if case .failure(let error) = result { message = error.localizedDescription }
                document = nil
            }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.gorillaBackup, .data]) { result in
            Task {
                do { candidate = try await controller.read(result.get()) }
                catch { message = String(localized: "The backup could not be read. No data was changed.") }
            }
        }
        .confirmationDialog("Replace Current Data?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Restore Backup", role: .destructive) {
                guard let candidate else { return }
                Task {
                    do { try await controller.restore(candidate) }
                    catch {
                        controller.restoreMessage = controller.lastRestoreHadSafetyCopy
                            ? String(localized: "Restore failed. The safety copy has been retained.")
                            : String(localized: "Restore could not start. No data was changed.")
                    }
                }
            }
        } message: { Text("A safety copy of your current data will be saved before restoring. This replaces records and photos, not merges them.") }
        .alert("Backup & Restore", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("確定", role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
    }

    private func export() {
        Task {
            do { document = BackupDocument(data: try await controller.export()); exporting = true }
            catch { message = String(localized: "Backup failed. Check that saved photos are available and try again.") }
        }
    }
    private func exportSafety() {
        Task {
            do {
                let data = try await Task.detached { try Data(contentsOf: BackupController.safetyURL) }.value
                document = BackupDocument(data: data)
                exporting = true
            } catch { message = error.localizedDescription }
        }
    }
}
