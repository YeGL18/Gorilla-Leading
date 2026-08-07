import Foundation
import SwiftUI

struct ParkingPhoto: Identifiable, Codable {
    let id: UUID
    let fileName: String
    let createdAt: Date
    let rotation: Double
    let offsetX: Double
    let offsetY: Double

    // In-memory image cache — avoids disk reads on every SwiftUI body pass
    private static var imageCache: [String: UIImage] = [:]

    var image: UIImage? {
        if let cached = Self.imageCache[fileName] {
            return cached
        }
        guard let loaded = UIImage(contentsOfFile: PhotoStorage.fileURL(for: fileName).path) else {
            return nil
        }
        Self.imageCache[fileName] = loaded
        return loaded
    }

    static func evictCache(for fileName: String) {
        imageCache.removeValue(forKey: fileName)
    }

    static func evictAllCache() {
        imageCache.removeAll()
    }

    init(fileName: String, rotation: Double, offsetX: Double, offsetY: Double) {
        self.id = UUID()
        self.fileName = fileName
        self.createdAt = Date()
        self.rotation = rotation
        self.offsetX = offsetX
        self.offsetY = offsetY
    }
}

class PhotoStorage: ObservableObject {
    static let maxPhotos = 3
    private static let folderName = "parking_photos"
    private static let photosKey = "parking_photos_list"

    @Published var photos: [ParkingPhoto] = []
    private var hasLoaded = false

    static var directoryURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(folderName)
    }

    static func fileURL(for fileName: String) -> URL {
        directoryURL.appendingPathComponent(fileName)
    }

    init() {}

    func prepare() {
        guard !hasLoaded else { return }
        hasLoaded = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            Self.ensureDirectoryExists()
            load()
        }
    }

    static func ensureDirectoryExists() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directoryURL.path) {
            try? fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    func savePhoto(_ image: UIImage) -> ParkingPhoto? {
        guard photos.count < Self.maxPhotos else { return nil }
        Self.ensureDirectoryExists()

        let fileName = "\(UUID().uuidString).jpg"
        let fileURL = Self.fileURL(for: fileName)
        if let data = image.jpegData(compressionQuality: 0.85) {
            try? data.write(to: fileURL)
        }

        let rotation = Double.random(in: -10...10)
        let offsetX = Double.random(in: -6...6)
        let offsetY = Double.random(in: -4...4)
        let photo = ParkingPhoto(fileName: fileName, rotation: rotation, offsetX: offsetX, offsetY: offsetY)
        photos.append(photo)
        saveToDefaults()
        return photo
    }

    func deleteAll() {
        let fm = FileManager.default
        for photo in photos {
            let url = Self.fileURL(for: photo.fileName)
            try? fm.removeItem(at: url)
            ParkingPhoto.evictCache(for: photo.fileName)
        }
        photos = []
        saveToDefaults()
    }

    func deletePhoto(_ photo: ParkingPhoto) {
        let fm = FileManager.default
        let url = Self.fileURL(for: photo.fileName)
        try? fm.removeItem(at: url)
        ParkingPhoto.evictCache(for: photo.fileName)
        photos.removeAll { $0.id == photo.id }
        saveToDefaults()
    }

    private func saveToDefaults() {
        if let data = try? JSONEncoder().encode(photos) {
            UserDefaults.standard.set(data, forKey: Self.photosKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.photosKey),
              let decoded = try? JSONDecoder().decode([ParkingPhoto].self, from: data) else { return }
        photos = decoded
    }
}
