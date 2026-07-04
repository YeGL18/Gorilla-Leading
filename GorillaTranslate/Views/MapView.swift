import SwiftUI
import MapKit

class NonAdjustingMapView: MKMapView {
    var allowCameraChange = false
    private var lockedDistance: CLLocationDistance?
    private var lockedCenter: CLLocationCoordinate2D?
    private var lockedPitch: CGFloat?
    private var lockedHeading: CLLocationDirection?
    private var isLocked = false

    func lockCamera() {
        lockedDistance = camera.centerCoordinateDistance
        lockedCenter = centerCoordinate
        lockedPitch = camera.pitch
        lockedHeading = camera.heading
        isLocked = true
    }

    func unlockCamera() {
        isLocked = false
    }

    func restoreCamera() {
        guard isLocked, 
              let dist = lockedDistance, 
              let center = lockedCenter,
              let pitch = lockedPitch,
              let heading = lockedHeading else { return }
        let cam = camera
        cam.centerCoordinateDistance = dist
        cam.centerCoordinate = center
        cam.pitch = pitch
        cam.heading = heading
        super.setCamera(cam, animated: false)
    }

    override func setCamera(_ newCamera: MKMapCamera, animated: Bool) {
        guard allowCameraChange else { 
            restoreCamera()
            return 
        }
        super.setCamera(newCamera, animated: animated)
    }

    override func setRegion(_ newRegion: MKCoordinateRegion, animated: Bool) {
        guard allowCameraChange else { 
            restoreCamera()
            return 
        }
        super.setRegion(newRegion, animated: animated)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        restoreCamera()
    }
    
    override func setCenter(_ coordinate: CLLocationCoordinate2D, animated: Bool) {
        guard allowCameraChange else {
            restoreCamera()
            return
        }
        super.setCenter(coordinate, animated: animated)
    }
    
    override func setVisibleMapRect(_ mapRect: MKMapRect, animated: Bool) {
        guard allowCameraChange else {
            restoreCamera()
            return
        }
        super.setVisibleMapRect(mapRect, animated: animated)
    }
    
    override func setVisibleMapRect(_ mapRect: MKMapRect, edgePadding insets: UIEdgeInsets, animated: Bool) {
        guard allowCameraChange else {
            restoreCamera()
            return
        }
        super.setVisibleMapRect(mapRect, edgePadding: insets, animated: animated)
    }
    
    override func showAnnotations(_ annotations: [MKAnnotation], animated: Bool) {
        guard allowCameraChange else {
            restoreCamera()
            return
        }
        super.showAnnotations(annotations, animated: animated)
    }
}

struct MapView: UIViewRepresentable {
    @Binding var savedRegion: MKCoordinateRegion?
    @Binding var flyTrigger: Int
    var isLandscape: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> NonAdjustingMapView {
        let mapView = NonAdjustingMapView()
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .none
        mapView.pointOfInterestFilter = .excludingAll
        mapView.overrideUserInterfaceStyle = .dark
        mapView.delegate = context.coordinator
        context.coordinator.mapView = mapView

        if let saved = savedRegion {
            mapView.unlockCamera()
            mapView.allowCameraChange = true
            mapView.setRegion(saved, animated: false)
            mapView.lockCamera()
            mapView.allowCameraChange = false
        } else {
            mapView.allowCameraChange = true
            mapView.lockCamera()
            mapView.allowCameraChange = false
        }

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.userTouched))
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.userTouched))
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.userTouched))
        let rotate = UIRotationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.userTouched))
        mapView.addGestureRecognizer(tap)
        mapView.addGestureRecognizer(pan)
        mapView.addGestureRecognizer(pinch)
        mapView.addGestureRecognizer(rotate)

        // 调整指南针位置：下移一个指南针高度 + 12pt
        // 指南针的标准高度大约是 30pt
        let compassHeight: CGFloat = 30
        let additionalOffset: CGFloat = 12
        
        // 查找指南针视图并调整其位置
        DispatchQueue.main.async {
            for subview in mapView.subviews {
                if NSStringFromClass(type(of: subview)).contains("Compass") {
                    var frame = subview.frame
                    frame.origin.y += compassHeight + additionalOffset
                    subview.frame = frame
                    break
                }
            }
        }

        return mapView
    }

    func updateUIView(_ mapView: NonAdjustingMapView, context: Context) {
        let landscapeChanged = context.coordinator.isLandscape != isLandscape
        context.coordinator.isLandscape = isLandscape
        
        if landscapeChanged {
            mapView.lockCamera()
            mapView.allowCameraChange = false
            context.coordinator.autoZoomTimer?.invalidate()
            context.coordinator.autoZoomTimer = nil
        }
        
        if flyTrigger > 0 && flyTrigger != context.coordinator.lastFlyTrigger {
            context.coordinator.lastFlyTrigger = flyTrigger
            if landscapeChanged {
                let coordinator = context.coordinator
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    coordinator.startTracking()
                }
            } else {
                context.coordinator.startTracking()
            }
        }
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapView
        weak var mapView: NonAdjustingMapView?
        var lastFlyTrigger = 0
        var isLandscape = false
        var autoZoomTimer: Timer?
        var flyTimer: Timer?
        var isFlying = false
        var hasShownHighAltitude = false
        var hasInitialized = false

        init(_ parent: MapView) {
            self.parent = parent
        }

        @objc func userTouched() {
            isFlying = false
            flyTimer?.invalidate()
            flyTimer = nil
            autoZoomTimer?.invalidate()
            autoZoomTimer = nil
            hasInitialized = true
            scheduleAutoZoom()
        }

        func startTracking() {
            guard let mapView = mapView else { return }
            
            // 如果是第一次，先显示高空视角
            if !hasShownHighAltitude {
                if let location = mapView.userLocation.location {
                    showHighAltitudeView(mapView: mapView, location: location)
                    return
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.startTracking()
                    }
                    return
                }
            }
            
            // 正常的飞行动画
            flyTimer?.invalidate()
            flyTimer = nil
            isFlying = false
            if let location = mapView.userLocation.location {
                flyToLocation(mapView: mapView, location: location)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.startTracking()
                }
            }
        }

        private func showHighAltitudeView(mapView: NonAdjustingMapView, location: CLLocation) {
            hasShownHighAltitude = true
            
            mapView.unlockCamera()
            mapView.allowCameraChange = true
            
            let camera = mapView.camera
            camera.centerCoordinate = location.coordinate
            camera.centerCoordinateDistance = 50000
            mapView.camera = camera
            
            mapView.lockCamera()
            mapView.allowCameraChange = false
            
            hasInitialized = true
            parent.savedRegion = mapView.region
            
            scheduleAutoZoom()
        }

        func scheduleAutoZoom() {
            guard !isFlying else { return }
            autoZoomTimer?.invalidate()
            autoZoomTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
                guard let self = self, !self.isFlying else { return }
                DispatchQueue.main.async {
                    self.startTracking()
                }
            }
        }

        private func flyToLocation(mapView: NonAdjustingMapView, location: CLLocation) {
            autoZoomTimer?.invalidate()
            autoZoomTimer = nil
            isFlying = true
            let landscape = isLandscape
            let latOffset: CLLocationDegrees = landscape ? 0.00035 : 0
            let targetCenter = CLLocationCoordinate2D(
                latitude: location.coordinate.latitude + latOffset,
                longitude: location.coordinate.longitude
            )
            let targetDistance: CLLocationDistance = landscape ? 320 : 260
            let startCenter = mapView.centerCoordinate
            let startDistance = mapView.camera.centerCoordinateDistance
            mapView.unlockCamera()
            mapView.allowCameraChange = true

            let duration: TimeInterval = 4.5
            let startTime = Date()
            flyTimer?.invalidate()

            flyTimer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak mapView, weak self] timer in
                guard let mapView = mapView, let self = self else { timer.invalidate(); return }
                let elapsed = Date().timeIntervalSince(startTime)
                let t = min(elapsed / duration, 1.0)
                let posEase = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
                let distT = max(0, min(1, (t - 0.3) / 0.7))
                let distEase = distT < 0.5 ? 16 * distT * distT * distT * distT * distT : 1 - pow(-2 * distT + 2, 5) / 2

                let lat = startCenter.latitude + (targetCenter.latitude - startCenter.latitude) * posEase
                let lon = startCenter.longitude + (targetCenter.longitude - startCenter.longitude) * posEase
                let dist = startDistance + (targetDistance - startDistance) * distEase

                let camera = mapView.camera
                camera.centerCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                camera.centerCoordinateDistance = dist
                mapView.camera = camera

                if t >= 1.0 {
                    timer.invalidate()
                    self.flyTimer = nil
                    self.isFlying = false
                    mapView.lockCamera()
                    mapView.allowCameraChange = false
                    DispatchQueue.main.async {
                        self.scheduleAutoZoom()
                    }
                }
            }
            RunLoop.main.add(flyTimer!, forMode: .common)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            if hasInitialized {
                parent.savedRegion = mapView.region
            }
            if let nonAdjusting = mapView as? NonAdjustingMapView {
                nonAdjusting.restoreCamera()
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            nil
        }
    }
}

struct VignetteMapView: View {
    @Binding var savedRegion: MKCoordinateRegion?
    @Binding var firstFlyTrigger: Int
    @State private var flyTrigger = 0
    @State private var isLandscape = false
    @State private var hasTriggeredFirstTime = false

    var body: some View {
        ZStack {
            MapView(savedRegion: $savedRegion, flyTrigger: $flyTrigger, isLandscape: isLandscape)
                .ignoresSafeArea()

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: 0.45),
                        .init(color: .black.opacity(0.45), location: 0.7),
                        .init(color: .black.opacity(0.75), location: 1)
                    ]),
                    center: .center,
                    startRadius: min(w, h) * 0.25,
                    endRadius: max(w, h) * 0.65
                )
                .ignoresSafeArea()
                .onChange(of: geo.size.width) { _, _ in
                    let landscape = w > h
                    if landscape != isLandscape {
                        isLandscape = landscape
                        flyTrigger += 1
                    }
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        .onChange(of: firstFlyTrigger) { _, _ in
            if !hasTriggeredFirstTime {
                hasTriggeredFirstTime = true
                flyTrigger += 1
            }
        }
    }
}
