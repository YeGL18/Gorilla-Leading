import SwiftUI
import CoreLocation
import ImageIO
import Contacts

struct FindCarCardSnapshot: Identifiable {
    let id = UUID()
    var place: String
    var floor: String?
    var spot: String?
    var area: String?
    var entry: Date
    var coordinate: CLLocationCoordinate2D?
    var photos: [UIImage]
    var locationText: String = ""

    var initialLocationText: String {
        locationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? place : locationText
    }

    static func readableLocation(address: String, poi: String) -> String {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let poi = poi.trimmingCharacters(in: .whitespacesAndNewlines)
        if address.isEmpty { return poi }
        if poi.isEmpty || address.localizedCaseInsensitiveContains(poi) { return address }
        return address + "\n" + poi
    }

    func sharedMapsURL(includeExactLocation: Bool) -> URL? {
        includeExactLocation ? mapsURL : nil
    }

    nonisolated static func thumbnails(_ urls: [URL]) -> [UIImage] {
        urls.compactMap { url in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1200
                  ] as CFDictionary) else { return nil }
            return UIImage(cgImage: image)
        }
    }

    var mapsURL: URL? {
        guard let coordinate, CLLocationCoordinate2DIsValid(coordinate) else { return nil }
        var url = URLComponents(string: "https://maps.apple.com/")!
        url.queryItems = [URLQueryItem(name: "ll", value: "\(coordinate.latitude),\(coordinate.longitude)"),
                         URLQueryItem(name: "q", value: place)]
        return url.url
    }
}

struct FindCarCard: View {
    let snapshot: FindCarCardSnapshot
    var includePhotos: Bool
    var includeLocation: Bool
    var includeExactLocation: Bool = false
    var locationText: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "car.fill").foregroundStyle(.teal)
                Text("Find My Car").font(.headline)
                Spacer()
                Image(uiImage: GorillaBrand.tabIcon).resizable().scaledToFit().frame(width: 28, height: 28)
            }
            Text(snapshot.place).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
            if includeLocation {
                Text(locationText ?? snapshot.initialLocationText)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 20) {
                if let floor = snapshot.floor, !floor.isEmpty { detail("Floor", floor) }
                if let area = snapshot.area, !area.isEmpty { detail("Area", area) }
                if let spot = snapshot.spot, !spot.isEmpty { detail("Spot", spot) }
                }
            }
            Text(snapshot.entry.formatted(date: .abbreviated, time: .shortened)).font(.subheadline).foregroundStyle(.secondary)
            if includePhotos {
                ForEach(Array(snapshot.photos.enumerated()), id: \.offset) { _, photo in
                    Image(uiImage: photo).resizable().scaledToFill()
                        .frame(width: 312, height: 312 / ParkingPhotoLayout.previewAspectRatio)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            if includeExactLocation, let coordinate = snapshot.coordinate, CLLocationCoordinate2DIsValid(coordinate) {
                Label(String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude), systemImage: "mappin")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Divider()
            Text("Gorilla Leading").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 360, alignment: .leading)
        .foregroundStyle(.black)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .environment(\.colorScheme, .light)
        .dynamicTypeSize(.medium)
    }

    private func detail(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FindCarShareItems: Identifiable {
    let id = UUID()
    var items: [Any]
}

private struct NativeCarShare: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = controller.view
            popover.sourceRect = CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct FindCarShareView: View {
    let snapshot: FindCarCardSnapshot
    @Environment(\.dismiss) private var dismiss
    @State private var includePhotos = true
    @State private var includeLocation = true
    @State private var includeExactLocation = false
    @State private var locationDraft: FindCarLocationDraft
    @State private var shareItems: FindCarShareItems?
    @State private var renderFailed = false

    init(snapshot: FindCarCardSnapshot) {
        self.snapshot = snapshot
        _locationDraft = State(initialValue: FindCarLocationDraft(text: snapshot.initialLocationText))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack {
                        if !snapshot.photos.isEmpty { Toggle("Include Photos", isOn: $includePhotos) }
                        Toggle("Include Location", isOn: $includeLocation)
                        if includeLocation {
                            TextField("Address and POI", text: Binding(
                                get: { locationDraft.text },
                                set: { locationDraft.edit($0) }), axis: .vertical)
                                .lineLimit(2...5)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel(Text("Address and POI"))
                        }
                        if snapshot.mapsURL != nil { Toggle("Include Exact Location", isOn: $includeExactLocation) }
                    }
                    .padding(.horizontal)
                    ViewThatFits(in: .horizontal) {
                        card
                        card.scaleEffect(0.8, anchor: .top).frame(width: 288)
                    }
                }
                .padding(.vertical)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Share Car Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { share() } label: {
                        Image(systemName: "square.and.arrow.up")
                            .offset(y: -1)
                    }
                        .accessibilityLabel(Text("Share Car Card"))
                }
            }
            .sheet(item: $shareItems) { NativeCarShare(items: $0.items).presentationDetents([.medium, .large]) }
            .alert("Could Not Create Card", isPresented: $renderFailed) { Button("確定", role: .cancel) {} }
            .task { await resolveParkedLocation() }
        }
    }

    private var card: some View {
        FindCarCard(snapshot: snapshot, includePhotos: includePhotos, includeLocation: includeLocation,
                    includeExactLocation: includeExactLocation, locationText: locationDraft.text)
    }

    @MainActor private func resolveParkedLocation() async {
        guard let coordinate = snapshot.coordinate, CLLocationCoordinate2DIsValid(coordinate) else { return }
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(
                CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                preferredLocale: LanguageManager.locale)
            guard !Task.isCancelled, let placemark = placemarks.first else { return }
            let address = placemark.postalAddress.map {
                CNPostalAddressFormatter.string(from: $0, style: .mailingAddress)
            } ?? [placemark.country, placemark.administrativeArea, placemark.locality,
                  placemark.subLocality, placemark.thoroughfare, placemark.subThoroughfare]
                .compactMap { $0 }.joined(separator: " ")
            let poi = placemark.areasOfInterest?.first ?? snapshot.place
            locationDraft.resolve(FindCarCardSnapshot.readableLocation(address: address, poi: poi))
        } catch {
            // Keep the saved parking location when offline or geocoding is unavailable.
        }
    }

    @MainActor private func share() {
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        guard let image = renderer.uiImage else { renderFailed = true; return }
        // Rendering produces new pixels, without the original photos' EXIF/GPS metadata.
        var items: [Any] = [image]
        if let url = snapshot.sharedMapsURL(includeExactLocation: includeExactLocation) { items.append(url) }
        shareItems = FindCarShareItems(items: items)
    }
}

struct FindCarLocationDraft {
    var text: String
    private(set) var edited = false

    mutating func edit(_ value: String) {
        text = value
        edited = true
    }

    mutating func resolve(_ value: String) {
        guard !edited, !value.isEmpty else { return }
        text = value
    }
}
