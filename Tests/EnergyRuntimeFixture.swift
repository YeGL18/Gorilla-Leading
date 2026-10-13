import SwiftUI
import MapKit

// Dependencies outside the scope of these tests never load user data or use the network.
struct PlaceInfo {
    var displayName: String
    var coordinate: CLLocationCoordinate2D
}
struct PendingTripPrediction { var predicted: PlaceInfo }
extension Notification.Name {
    static let timePhasePreviewChanged = Notification.Name("energy-phase-preview")
}
extension CLLocationCoordinate2D {
    var wgs84ToGCJ02: CLLocationCoordinate2D { self }
}

@main
struct EnergyRuntimeFixture: App {
    var body: some Scene { WindowGroup { EdgeFixture() } }
}

private struct EdgeFixture: View {
    @State private var softened = true
    var body: some View {
        VStack {
            Text("Single Map Edge Check").font(.headline)
            EdgeMap(softened: softened).padding(20)
            Button(softened ? "Original Edges" : "Softened Edges") { softened.toggle() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("edgeToggle")
        }
        .background(.black)
        .preferredColorScheme(.dark)
    }
}

private struct EdgeMap: UIViewRepresentable {
    let softened: Bool
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> MapPresentationContainer {
        let container = MapPresentationContainer()
        let map = MKMapView()
        map.delegate = context.coordinator
        map.accessibilityIdentifier = "energy-map"
        map.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        map.overrideUserInterfaceStyle = .dark
        map.setRegion(MKCoordinateRegion(center: .init(latitude: 22.3193, longitude: 114.1694),
                                        latitudinalMeters: 2500, longitudinalMeters: 2500), animated: false)
        let annotation = MKPointAnnotation()
        annotation.coordinate = .init(latitude: 22.3193, longitude: 114.1694)
        annotation.title = "Hong Kong"
        map.addAnnotation(annotation)
        container.addSubview(map)
        return container
    }
    func updateUIView(_ view: MapPresentationContainer, context: Context) {
        view.subviews.compactMap { $0 as? MKMapView }.first?.frame = view.bounds
        view.softenEdges(cornerRadius: softened ? 100 : nil)
        view.layer.cornerRadius = 100
        view.clipsToBounds = true
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let region = mapView.region
            mapView.accessibilityValue = "\(region.center.latitude),\(region.center.longitude),\(region.span.latitudeDelta)"
        }
    }
}
