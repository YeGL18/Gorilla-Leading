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
    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("--activity-preview") { ActivityFixture() }
            else if ProcessInfo.processInfo.arguments.contains("--time-entrance") { TimeEntranceFixture() }
            else { EdgeFixture() }
        }
    }
}

private struct ActivityFixture: View {
    private let states: [GorillaActivityState] = [.parking, .nonAutomotiveParking, .driving, .stationary, .walking, .cycling]
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(states, id: \.self) { state in
                    GorillaLockScreenView(state: .init(state: state, startDate: Date().addingTimeInterval(-1480),
                        location: "銀湖・天峰停車場", area: "A", floor: "B2", spot: "128",
                        destinationName: [.driving, .cycling].contains(state) ? "香港國際機場" : nil,
                        languageCode: "zh-Hant"))
                        .background(.black.opacity(0.8), in: .rect(cornerRadius: 26))
                        .frame(maxWidth: 400)
                }
            }.padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--light") ? .light : .dark)
    }
}

private struct TimeEntranceFixture: View {
    @StateObject private var manager = TimePhaseManager(weatherService: WeatherService())
    @StateObject private var clock = AnimationClock()

    private var targetHour: Double {
        let start = manager.schedule.startHours[TimePhase.morning.rawValue]
        let end = manager.schedule.startHours[TimePhase.afternoon.rawValue]
        return start + (end - start) * 0.88
    }

    var body: some View {
        TimeBasedOrbView(phaseManager: manager, clock: clock)
            .overlay(alignment: .bottom) {
                VStack {
                    Text(String(format: "%.3f", manager.phaseTransitionProgress))
                        .accessibilityIdentifier("phaseProgress")
                    HStack {
                        Button("Start") { showFrame(0) }
                        Button("Middle") { showFrame(0.5) }
                        Button("End") { showFrame(1) }
                        Button("Replay") {
                            manager.setPreviewHour(targetHour)
                            manager.startWithEntranceAnimation(duration: 2)
                        }
                    }
                }.padding(24).foregroundStyle(.black)
            }
            .onAppear { showFrame(0) }
    }

    private func showFrame(_ progress: Double) {
        let entrance = TimePhaseEntrance(targetHour: targetHour, schedule: manager.schedule)
        manager.setPreviewHour(entrance.frame(progress: progress, targetHour: targetHour).hour)
    }
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
