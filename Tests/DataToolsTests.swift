import XCTest
import SwiftUI
import ImageIO
@testable import GorillaTranslate

@MainActor final class DataToolsTests: XCTestCase {
    func testEditableLocationAndExactLocationAreIndependent() {
        let snapshot = FindCarCardSnapshot(place: "銀湖天峰", floor: "1/F", spot: "1208", area: "A",
            entry: Date(), coordinate: .init(latitude: 22.425, longitude: 114.235), photos: [],
            locationText: "西沙路 599 號")
        XCTAssertEqual(snapshot.initialLocationText, "西沙路 599 號")
        XCTAssertNil(snapshot.sharedMapsURL(includeExactLocation: false))
        XCTAssertNotNil(snapshot.sharedMapsURL(includeExactLocation: true))
        XCTAssertEqual(FindCarCardSnapshot.readableLocation(address: "西沙路 599 號", poi: "銀湖天峰"),
                       "西沙路 599 號\n銀湖天峰")
        XCTAssertEqual(FindCarCardSnapshot.readableLocation(address: "西沙路 銀湖天峰", poi: "銀湖天峰"),
                       "西沙路 銀湖天峰")
        var draft = FindCarLocationDraft(text: snapshot.initialLocationText)
        draft.resolve("香港 西沙路 599 號")
        XCTAssertEqual(draft.text, "香港 西沙路 599 號")
        draft.edit("自訂地址")
        draft.resolve("遲到的地理編碼結果")
        XCTAssertEqual(draft.text, "自訂地址")
        draft.edit("")
        draft.resolve("不要覆蓋清空的地址")
        XCTAssertEqual(draft.text, "")
    }

    func testLocationDetailsSwitchChangesCardWithoutRequiringCoordinates() throws {
        let snapshot = FindCarCardSnapshot(place: "Car Park", floor: "B2/F", spot: "1208", area: "East",
            entry: Date(), photos: [], locationText: "599 Sai Sha Road\nLake Silver")
        let included = ImageRenderer(content: FindCarCard(snapshot: snapshot, includePhotos: false, includeLocation: true))
        let hidden = ImageRenderer(content: FindCarCard(snapshot: snapshot, includePhotos: false, includeLocation: false))
        XCTAssertGreaterThan(try XCTUnwrap(included.uiImage).size.height, try XCTUnwrap(hidden.uiImage).size.height)
        XCTAssertNil(snapshot.sharedMapsURL(includeExactLocation: true))
    }
    private func plist(_ values: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
    }

    func testPhotoAndSchemaValidation() throws {
        let name = "\(UUID()).jpg"
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 60))
        let image = renderer.image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 60))
        }
        let photo = ParkingPhoto(fileName: name, rotation: 0, offsetX: 0, offsetY: 0)
        var backup = GorillaBackup(createdAt: Date(), appVersion: "test",
            standard: try plist(["parking_photos_list": JSONEncoder().encode([photo])]),
            shared: try plist([:]), photos: [name: image.jpegData(compressionQuality: 0.8)!])
        _ = try backup.validated()
        XCTAssertNoThrow(try BackupController.validateModels(backup))
        backup.photos[name] = Data([1, 2, 3])
        XCTAssertThrowsError(try BackupController.validateModels(backup))
        backup.photos = [:]
        backup.standard = try plist(["visit_records": Data("[{}]".utf8)])
        XCTAssertThrowsError(try BackupController.validateModels(backup))
    }

    func testRenderedCardAndPrivacy() throws {
        let snapshot = FindCarCardSnapshot(place: "銀湖天峰 住戶停車場 / Residential Car Park",
            floor: "B2/F", spot: "B2-1208", area: "East", entry: Date(timeIntervalSince1970: 1_791_000_000),
            coordinate: .init(latitude: 22.425, longitude: 114.235), photos: [])
        let card = FindCarCard(snapshot: snapshot, includePhotos: false, includeLocation: false)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertEqual(image.size.width, 360)
        XCTAssertGreaterThan(image.size.height, 150)
        let data = try XCTUnwrap(image.pngData())
        XCTAssertGreaterThan(data.count, 10000)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        let query = try XCTUnwrap(URLComponents(url: snapshot.mapsURL!, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.first { $0.name == "q" }?.value, snapshot.place)
        XCTAssertEqual(query.first { $0.name == "ll" }?.value, "22.425,114.235")
        try data.write(to: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("gorilla-find-car-card.png"))
    }

    func testRestoreTransactionOnIOS() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("restore-check-\(UUID())")
        let standardName = "restore-check-standard-\(UUID())"
        let sharedName = "restore-check-shared-\(UUID())"
        let standard = try XCTUnwrap(UserDefaults(suiteName: standardName))
        let shared = try XCTUnwrap(UserDefaults(suiteName: sharedName))
        defer {
            standard.removePersistentDomain(forName: standardName)
            shared.removePersistentDomain(forName: sharedName)
            try? FileManager.default.removeItem(at: root)
        }
        let entry = Date(timeIntervalSince1970: 1_791_000_000)
        let before = GorillaBackup(createdAt: Date(), appVersion: "test",
            standard: try plist(["appearanceMode": 2, "visit_records": Data("[]".utf8)]),
            shared: try plist(["parkingEntryTime": entry]), photos: [:])
        let after = GorillaBackup(createdAt: Date(), appVersion: "test",
            standard: try plist(["appearanceMode": 1]), shared: try plist([:]), photos: [:])
        let transaction = BackupTransaction(standard: standard, shared: shared, documents: root,
            recoveryURL: root.appendingPathComponent("recovery.gorillabackup"))
        try transaction.apply(before)
        standard.set(["ja"], forKey: "AppleLanguages")
        try transaction.restore(after, safety: before)
        XCTAssertEqual(standard.integer(forKey: "appearanceMode"), 1)
        XCTAssertNil(standard.object(forKey: "visit_records"))
        XCTAssertEqual(standard.stringArray(forKey: "AppleLanguages"), ["ja"])
        try transaction.apply(before)
        enum Injected: Error { case failure }
        XCTAssertThrowsError(try transaction.restore(after, safety: before) { throw Injected.failure })
        XCTAssertEqual(standard.integer(forKey: "appearanceMode"), 2)
        XCTAssertEqual(shared.object(forKey: "parkingEntryTime") as? Date, entry)
        try before.encoded().write(to: transaction.recoveryURL)
        try transaction.apply(after)
        try transaction.recoverIfNeeded()
        XCTAssertEqual(standard.integer(forKey: "appearanceMode"), 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: transaction.recoveryURL.path))
    }

    func testCardUsesParkingPreviewCrop() throws {
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 480)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 240, height: 480))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 336, width: 240, height: 144))
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 144, width: 240, height: 192))
        }
        let snapshot = FindCarCardSnapshot(place: "銀湖天峰", entry: Date(), photos: [photo])
        let withPhotos = ImageRenderer(content: FindCarCard(snapshot: snapshot, includePhotos: true, includeLocation: false))
        let withoutPhotos = ImageRenderer(content: FindCarCard(snapshot: snapshot, includePhotos: false, includeLocation: false))
        withPhotos.scale = 1
        withoutPhotos.scale = 1
        let image = try XCTUnwrap(withPhotos.uiImage)
        let plain = try XCTUnwrap(withoutPhotos.uiImage)
        XCTAssertEqual(image.size.height - plain.size.height,
            312 / ParkingPhotoLayout.previewAspectRatio + 18, accuracy: 1)

        let cgImage = try XCTUnwrap(image.cgImage)
        var pixels = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: cgImage.width, height: cgImage.height,
                bitsPerComponent: 8, bytesPerRow: cgImage.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        }
        var green = 0
        var redOrBlue = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            if pixels[i] < 20 && pixels[i + 1] > 240 && pixels[i + 2] < 20 { green += 1 }
            if (pixels[i] > 240 && pixels[i + 1] < 20 && pixels[i + 2] < 20)
                || (pixels[i] < 20 && pixels[i + 1] < 20 && pixels[i + 2] > 240) { redOrBlue += 1 }
        }
        XCTAssertGreaterThan(green, 30_000)
        XCTAssertEqual(redOrBlue, 0, "The original photo's top and bottom should be cropped out")
        let corners = [0, cgImage.width - 1, (cgImage.height - 1) * cgImage.width,
            cgImage.height * cgImage.width - 1]
        for corner in corners {
            XCTAssertEqual(pixels[corner * 4 + 3], 0, "The shared card should retain transparent rounded corners")
        }
        XCTAssertEqual(pixels[(cgImage.width / 2) * 4 + 3], 255)
        try XCTUnwrap(image.pngData()).write(to: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("gorilla-find-car-crop.png"))
    }

    func testOptInDiagnosticsReusesCallbacks() {
        let recorder = PerformanceRecorder.shared
        XCTAssertNil(AnimationDiagnostics.callback)
        recorder.start()
        XCTAssertNotNil(AnimationDiagnostics.callback)
        AnimationDiagnostics.callback?("map_tracking", 1, 1.0 / 60)
        AnimationDiagnostics.callback?("map_tracking", 1.1, 1.0 / 60)
        recorder.stop()
        XCTAssertNil(AnimationDiagnostics.callback)
        XCTAssertFalse(recorder.running)
        XCTAssertTrue(recorder.csv.contains("map_tracking,1,1,100.00"))
        XCTAssertFalse(recorder.csv.contains("latitude"))
        let rows = recorder.csv.split(separator: "\n").map { $0.split(separator: ",") }
        XCTAssertTrue(rows.allSatisfy { $0.count == 17 })
        for row in rows.dropFirst() {
            for column in [0, 2, 6, 7, 8, 16] {
                XCTAssertNotNil(Double(row[column]))
            }
        }
    }
}
