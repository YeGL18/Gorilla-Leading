import SwiftUI
import MapKit

// Test the production ownership/handoff code with a real UIKit/MapKit container.
final class MapPresentationContainer: UIView {
    let map = MKMapView()
    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(map)
        map.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }
    required init?(coder: NSCoder) { fatalError() }
}

struct MapView {
    var centerOffsetX: CGFloat = 0
    var centerOffsetY: CGFloat = 0
    var onMapBlankTap: (() -> Void)?
    final class Coordinator {
        var parent = MapView()
        var layouts = 0
        var dismantles = 0
        func updateMapFrame(in container: UIView, centerOffset: CGPoint) { layouts += 1 }
        func detachHomeHost() { parent.onMapBlankTap = nil }
    }
    static func dismantleMapContainer(_ container: UIView, coordinator: Coordinator) {
        coordinator.dismantles += 1
    }
}

@main
struct HomeMapSessionFixture: App {
    var body: some Scene { WindowGroup { Text("Home map session checks") } }
}
