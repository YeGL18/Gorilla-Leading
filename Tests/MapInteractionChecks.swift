import UIKit
import MapKit

// Standalone simulator app harness; compile with the production MapInteraction.swift.
@main
final class MapInteractionChecks: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Checks", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = MapInteractionCheckScene.self
        return configuration
    }
}

final class MapInteractionCheckScene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        self.window = window
        if ProcessInfo.processInfo.arguments.contains("--marker-motion") ||
            ProcessInfo.processInfo.arguments.contains("--marker-native-pan") {
            window.rootViewController = MapMarkerMotionCheckController()
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--fades") {
            window.rootViewController = MapAnnotationFadeCheckController()
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--fits") {
            window.rootViewController = MapCameraFitCheckController()
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--gestures") {
            window.rootViewController = MapGestureCheckController()
            return
        }
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message)
            checks += 1
        }
        let marker = ScaledMarkerAnnotationView(annotation: MKPointAnnotation(), reuseIdentifier: "scale-check")
        marker.sizeScale = 1.3
        for _ in 0..<100 {
            // Simulate MapKit's read/modify/write of the native transform.
            marker.transform = marker.transform.rotated(by: 0.01)
            check(abs(marker.layer.sublayerTransform.m11 - 1.3) < 0.00001,
                  "Native transforms cannot compound the latest-marker enlargement")
            check(abs(hypot(marker.transform.a, marker.transform.b) - 1) < 0.00001,
                  "MapKit's transform getter must report the actual unscaled view transform")
        }
        marker.locksDragAppearance = true
        marker.setSelected(true, animated: true)
        check(!marker.isSelected, "Dragging must suppress native selected-marker inflation")
        marker.locksDragAppearance = false
        marker.setSelected(true, animated: false)
        check(marker.isSelected, "Ordinary selection must still work after dragging")
        marker.prepareForReuse()
        check(marker.sizeScale == 1 && marker.layer.sublayerTransform.m11 == 1,
              "Reusing an older marker must reset the content scale")
        marker.bounds = CGRect(x: 0, y: 0, width: 40, height: 40)
        let title = UILabel(frame: CGRect(x: -60, y: 48, width: 160, height: 22))
        title.text = "Parking point 1/F"
        marker.addSubview(title)
        check(marker.containsVisibleContent(CGPoint(x: 20, y: 59)),
              "Tapping a visible title below the marker must count as a marker tap")
        check(!marker.containsVisibleContent(CGPoint(x: 20, y: 80)),
              "Blank map below the label must not open the parking popup")
        title.isHidden = true
        check(!marker.containsVisibleContent(CGPoint(x: 20, y: 59)),
              "Hidden labels must not consume blank-map taps")
        title.removeFromSuperview()
        let holder = UIView()
        holder.addSubview(marker)
        let firstCycle = marker.appearanceCycle
        check(marker.alpha == 1 && marker.layer.opacity == 0,
              "The extra fade must not become MapKit's logical opacity")
        for _ in 0..<100 { marker.alpha = marker.alpha - 0.001 }
        check(abs(marker.alpha - 0.9) < 0.00001,
              "Native opacity read/modify/write cannot compound the appearance fade")
        marker.animateAppearance()
        check(marker.appearanceCycle == firstCycle,
              "Repeated attachment callbacks cannot restart an already visible marker")
        for _ in 0..<100 {
            marker.layer.isHidden = true
            marker.layer.isHidden = false
        }
        check(marker.appearanceCycle == firstCycle,
              "Transient native visibility flips cannot keep restarting the fade")
        marker.prepareForReuse()
        marker.removeFromSuperview()
        let map = NonAdjustingMapView(frame: window.bounds)
        window.rootViewController!.view.addSubview(map)
        let origin = CLLocationCoordinate2D(latitude: 22.3193, longitude: 114.1694)
        let camera = MKMapCamera(lookingAtCenter: origin, fromDistance: 1400, pitch: 42, heading: 0)
        map.allowCameraChange = true
        map.setCamera(camera, animated: false)
        map.allowCameraChange = false
        let before = map.camera.centerCoordinate
        let moved = MKMapCamera(lookingAtCenter: .init(latitude: 22.35, longitude: 114.2), fromDistance: 700, pitch: 42, heading: 0)
        map.setCamera(moved, animated: false)
        check(abs(map.camera.centerCoordinate.latitude - before.latitude) < 0.00001, "Automatic writes remain gated")
        map.allowsUserCameraChanges = true
        map.setCamera(moved, animated: false)
        check(abs(map.camera.centerCoordinate.latitude - 22.35) < 0.00001, "Manual pan is allowed")
        check(abs(map.camera.centerCoordinateDistance - 700) < 1, "Manual zoom is allowed")
        let region = MKCoordinateRegion(center: origin, latitudinalMeters: 2500, longitudinalMeters: 2500)
        map.setRegion(region, animated: false)
        check(abs(map.region.center.latitude - origin.latitude) < 0.00001, "Native region changes are allowed")
        map.layoutIfNeeded()
        check(abs(map.region.center.latitude - origin.latitude) < 0.00001, "Layout does not undo manual browsing")
        print("PASS: \(checks) marker scale and manual camera checks")
        fflush(stdout)
        if ProcessInfo.processInfo.arguments.contains("--scale") {
            let status = UILabel(frame: window.bounds.insetBy(dx: 20, dy: 160))
            status.text = "PASS: stable marker scale, reuse and drag selection"
            status.numberOfLines = 0
            status.accessibilityIdentifier = "markerCheckStatus"
            window.rootViewController!.view.addSubview(status)
        } else {
            DispatchQueue.main.async { exit(0) }
        }
    }
}

final class MapMarkerMotionCheckController: UIViewController, MKMapViewDelegate {
    private let map = NonAdjustingMapView()
    private let point = MKPointAnnotation()
    private let meter = MKPointAnnotation()
    private let nativePan = ProcessInfo.processInfo.arguments.contains("--marker-native-pan")
    private let status = UILabel()
    private var timer: Timer?
    private var samples = 0
    private var baselinePixels = 0
    private var minimumRatio = 1.0
    private var baselineMeterPixels = 0
    private var minimumMeterRatio = 1.0
    private var minimumDetails = ""
    private var start: CFTimeInterval = 0
    private let origin = CLLocationCoordinate2D(latitude: 22.3193, longitude: 114.1694)

    override func viewDidLoad() {
        super.viewDidLoad()
        map.frame = view.bounds
        map.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        map.delegate = self
        map.allowCameraChange = true
        map.pointOfInterestFilter = .excludingAll
        map.setCamera(MKMapCamera(lookingAtCenter: origin, fromDistance: 1400, pitch: 0, heading: 0), animated: false)
        view.addSubview(map)
        point.coordinate = origin
        point.title = "Parking record"
        point.subtitle = "15 records"
        map.addAnnotation(point)
        if nativePan {
            meter.coordinate = .init(latitude: origin.latitude + 0.0005, longitude: origin.longitude)
            meter.title = "Meter"
            map.addAnnotation(meter)
        }
        status.frame = CGRect(x: 20, y: 90, width: 650, height: 100)
        status.numberOfLines = 0
        status.accessibilityIdentifier = "markerMotionStatus"
        view.addSubview(status)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.begin() }
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if annotation === meter {
            let marker = FadingMarkerAnnotationView(annotation: annotation, reuseIdentifier: "meter-motion")
            marker.markerTintColor = .systemGreen
            marker.glyphText = "P"
            marker.displayPriority = .required
            return marker
        }
        let marker = ScaledMarkerAnnotationView(annotation: annotation, reuseIdentifier: "motion")
        marker.markerTintColor = .systemOrange
        marker.glyphText = "15"
        marker.sizeScale = 1.3
        marker.displayPriority = .required
        return marker
    }

    func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
        map.annotationsDidAppear(views)
    }

    private func begin() {
        guard let marker = map.view(for: point) else { return }
        baselinePixels = orangePixels(in: marker)
        if nativePan, let meterView = map.view(for: meter) {
            baselineMeterPixels = orangePixels(in: meterView, green: true)
        }
        (marker as? ScaledMarkerAnnotationView)?.locksDragAppearance = true
        map.beginAnnotationDrag()
        map.deselectAnnotation(point, animated: false)
        start = CACurrentMediaTime()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.advance() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func advance() {
        let elapsed = CACurrentMediaTime() - start
        guard let marker = map.view(for: point) else { return }
        if nativePan {
            // Leave the camera under MapKit's real gesture control.
        } else if elapsed < 5 {
            point.coordinate = .init(latitude: origin.latitude + sin(elapsed * 2) * 0.0002,
                                     longitude: origin.longitude + cos(elapsed * 2) * 0.0003)
        } else if elapsed < 10 {
            let camera = map.camera.copy() as! MKMapCamera
            camera.centerCoordinate = .init(latitude: origin.latitude + sin(elapsed * 2) * 0.0001,
                                            longitude: origin.longitude + cos(elapsed * 2) * 0.0002)
            map.setCamera(camera, animated: false)
        } else {
            timer?.invalidate()
            timer = nil
        }
        samples += 1
        if samples % 15 == 0 {
            // MapKit may deliver another didAdd/visibility refresh for the same view.
            map.annotationsDidAppear([marker])
            let count = orangePixels(in: marker)
            if baselinePixels > 0 {
                let ratio = Double(count) / Double(baselinePixels)
                if ratio < minimumRatio {
                    minimumRatio = ratio
                    minimumDetails = "at=\(String(format: "%.2f", elapsed)) alpha=\(marker.alpha) layerOpacity=\(marker.layer.opacity) viewScale=\(hypot(marker.transform.a, marker.transform.b)) contentScale=\(marker.layer.sublayerTransform.m11)"
                }
            }
            if nativePan, let meterView = map.view(for: meter), baselineMeterPixels > 0 {
                minimumMeterRatio = min(minimumMeterRatio,
                    Double(orangePixels(in: meterView, green: true)) / Double(baselineMeterPixels))
            }
            status.text = "done=\(elapsed >= 10 ? 1 : 0) pixels=\(count) base=\(baselinePixels) ratio=\(Int(minimumRatio * 100)) meterBase=\(baselineMeterPixels) meterRatio=\(Int(minimumMeterRatio * 100)) alpha=\(marker.alpha) scale=\(marker.transform.a)"
            print(status.text!)
        }
        if elapsed >= 10 {
            timer?.invalidate()
            timer = nil
            status.text = "done=1 base=\(baselinePixels) ratio=\(Int(minimumRatio * 100)) meterBase=\(baselineMeterPixels) meterRatio=\(Int(minimumMeterRatio * 100)) samples=\(samples) \(minimumDetails)"
        }
    }

    private func orangePixels(in marker: MKAnnotationView, green: Bool = false) -> Int {
        let rect = marker.bounds.insetBy(dx: -8, dy: -8)
        let screenRect = marker.convert(rect, to: map)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: screenRect.size, format: format).image { context in
            // Render the map-space crop so ancestor/native view scales are measured too.
            context.cgContext.translateBy(x: -screenRect.minX, y: -screenRect.minY)
            map.drawHierarchy(in: map.bounds, afterScreenUpdates: false)
        }
        guard let cg = image.cgImage else { return 0 }
        let width = cg.width, height = cg.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        return bytes.withUnsafeMutableBytes { data in
            guard let context = CGContext(data: data.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            let pixels = data.bindMemory(to: UInt8.self)
            return stride(from: 0, to: pixels.count, by: 4).reduce(0) { count, i in
                let matches = green
                    ? Int(pixels[i+1]) > 130 && Int(pixels[i]) < 100 && Int(pixels[i+2]) < 130
                    : Int(pixels[i]) > 150 && Int(pixels[i+1]) > 45 && Int(pixels[i+1]) < 210 && Int(pixels[i+2]) < 80
                return count + (matches ? 1 : 0)
            }
        }
    }

}

final class MapCameraFitCheckController: UIViewController {
    private let status = UILabel()

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        status.accessibilityIdentifier = "fitStatus"
        status.numberOfLines = 0
        status.frame = view.bounds.insetBy(dx: 20, dy: 100)
        view.backgroundColor = .systemBackground
        var failures: [String] = []
        var checks = 0
        func check(_ value: Bool, _ message: String) {
            checks += 1
            if !value { failures.append(message) }
        }
        let user = CLLocationCoordinate2D(latitude: 22.3193, longitude: 114.1694)
        let meter = CLLocationCoordinate2D(latitude: 22.326, longitude: 114.175)
        let size = CGSize(width: 390, height: 844)
        let shifted = NonAdjustingMapView.displayFrame(in: size, centerOffset: .init(x: 0, y: -2 * MapCameraMotion.trackingPointDownshift))
        check(shifted.contains(CGRect(origin: .zero, size: size)), "Tracking offset cannot expose a map gap")
        check(shifted.midY == size.height / 2 + MapCameraMotion.trackingPointDownshift, "Tracking center matches the configured downward offset")
        let seated = NonAdjustingMapView.displayFrame(in: size, centerOffset: .init(x: 0, y: size.height / 2))
        check(seated.contains(CGRect(origin: .zero, size: size)), "Hinge map still covers the viewport")
        check(seated.midY == size.height / 4, "Hinge retains its existing upper-screen center")
        for size in [CGSize(width: 390, height: 844), CGSize(width: 900, height: 600), CGSize(width: 430, height: 600)] {
            for pitch in [0.0, 42.0] {
                let map = NonAdjustingMapView(frame: CGRect(origin: .zero, size: size))
                view.addSubview(map)
                map.allowCameraChange = true
                map.setCamera(MKMapCamera(lookingAtCenter: user, fromDistance: 1400, pitch: pitch, heading: 30), animated: false)
                map.allowCameraChange = false
                map.layoutIfNeeded()
                let start = map.camera.copy() as! MKMapCamera
                let padding = UIEdgeInsets(top: 80, left: 30, bottom: 160, right: 120)
                let fitted = map.cameraFitting(MapCameraMotion.overviewRect(user: user, meter: meter), edgePadding: padding)
                check(abs(map.camera.centerCoordinate.latitude - start.centerCoordinate.latitude) < 1e-8 &&
                      abs(map.camera.centerCoordinate.longitude - start.centerCoordinate.longitude) < 1e-8,
                      "Fitting must not move the starting center")
                check(abs(map.camera.centerCoordinateDistance - start.centerCoordinateDistance) < 0.01 &&
                      abs(map.camera.pitch - start.pitch) < 0.01 && abs(map.camera.heading - start.heading) < 0.01,
                      "Fitting must preserve starting height, pitch and heading")
                check(!map.allowCameraChange, "Fitting restores camera ownership")
                map.allowCameraChange = true
                map.setCamera(fitted, animated: false)
                let visible = map.bounds.inset(by: padding)
                check(visible.contains(map.convert(user, toPointTo: map)), "Driver is inside the unobscured viewport")
                check(visible.contains(map.convert(meter, toPointTo: map)), "Meter is inside the unobscured viewport")
                map.removeFromSuperview()
            }
        }
        view.addSubview(status)
        status.text = failures.isEmpty ? "PASS: \(checks) padded camera checks" : failures.joined(separator: "\n")
        print(status.text!)
    }
}

final class MapAnnotationFadeCheckController: UIViewController, MKMapViewDelegate {
    let map = NonAdjustingMapView()
    let status = UILabel()
    let points = [MKPointAnnotation(), MKPointAnnotation()]
    var singleFades = 0, clusterFades = 0, reused = 0, snapshots = 0
    var sampledCycles: [ObjectIdentifier: Int] = [:]
    var nonemptySnapshots = 0
    var checkedSnapshots = Set<ObjectIdentifier>()
    var invalidSnapshot = false
    var link: CADisplayLink?
    private struct MotionAnchor {
        let coordinate: CLLocationCoordinate2D
        let offset: CGPoint
        let initialOrigin: CGPoint
    }
    private var motionAnchors: [ObjectIdentifier: MotionAnchor] = [:]
    private var motionStart: CFTimeInterval?
    private var motionCamera: MKMapCamera?
    private var motionSamples = 0
    private var motionTravel: CGFloat = 0
    private var motionError: CGFloat = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        map.frame = view.bounds
        map.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(map)
        map.delegate = self
        points[0].coordinate = .init(latitude: 22.3193, longitude: 114.1694)
        points[1].coordinate = .init(latitude: 22.3193, longitude: 114.1719)
        for point in points { point.title = "Test point" }
        setDistance(1400)
        let actions = UIStackView()
        actions.axis = .horizontal
        actions.distribution = .fillEqually
        actions.translatesAutoresizingMaskIntoConstraints = false
        for title in ["Add", "Cluster", "Separate", "Hide", "Show", "Remove", "Move Fade"] {
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.addAction(UIAction { [weak self] _ in self?.perform(title) }, for: .touchUpInside)
            actions.addArrangedSubview(button)
        }
        status.accessibilityIdentifier = "fadeStatus"
        status.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        status.numberOfLines = 0
        status.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(actions)
        view.addSubview(status)
        NSLayoutConstraint.activate([
            actions.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            actions.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 10),
            actions.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -10),
            actions.heightAnchor.constraint(equalToConstant: 44),
            status.topAnchor.constraint(equalTo: actions.bottomAnchor, constant: 10),
            status.leadingAnchor.constraint(equalTo: actions.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: actions.trailingAnchor),
            status.heightAnchor.constraint(equalToConstant: 50)
        ])
        let link = CADisplayLink(target: self, selector: #selector(frame))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func setDistance(_ distance: Double) {
        map.allowCameraChange = true
        map.setCamera(MKMapCamera(lookingAtCenter: .init(latitude: 22.3193, longitude: 114.17065),
                                 fromDistance: distance, pitch: 0, heading: 0), animated: false)
        map.allowCameraChange = false
    }

    private func perform(_ action: String) {
        switch action {
        case "Add": map.addAnnotations(points)
        case "Cluster": setDistance(50000)
        case "Separate": setDistance(1400)
        case "Hide": for point in points { map.view(for: point)?.isHidden = true }
        case "Show": for point in points { map.view(for: point)?.isHidden = false }
        case "Remove": map.removeAnnotations(points)
        case "Move Fade":
            motionCamera = map.camera.copy() as? MKMapCamera
            motionStart = CACurrentMediaTime()
            motionAnchors.removeAll()
            motionSamples = 0
            motionTravel = 0
            motionError = 0
            map.removeAnnotations(points)
            recordMotionAnchors()
        default: break
        }
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        let isCluster = annotation is MKClusterAnnotation
        let id = isCluster ? "cluster" : "single"
        let old = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? ScaledMarkerAnnotationView
        if old != nil { reused += 1 }
        let marker = old ?? ScaledMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
        marker.sizeScale = isCluster ? 1 : 1.3
        marker.annotation = annotation
        marker.glyphText = isCluster ? "2" : "P"
        marker.markerTintColor = .systemOrange
        marker.clusteringIdentifier = isCluster ? nil : "fade-checks"
        return marker
    }

    func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
        map.annotationsDidAppear(views)
    }

    @objc private func frame() {
        if let start = motionStart, let original = motionCamera {
            recordMotionAnchors()
            let t = min(1, (CACurrentMediaTime() - start) / 0.18)
            let camera = original.copy() as! MKMapCamera
            camera.centerCoordinate.latitude += 0.0006 * t
            camera.centerCoordinate.longitude += 0.0012 * t
            camera.centerCoordinateDistance *= 1 - 0.18 * t
            camera.heading += 65 * t
            camera.pitch = 35 * t
            map.allowCameraChange = true
            map.setCamera(camera, animated: false)
            map.allowCameraChange = false
            if t >= 1 { motionStart = nil }
            // Sample after all display-link writers have updated this frame.
            DispatchQueue.main.async { [weak self] in self?.sampleMotion() }
        }
        let fading = map.subviews.filter { $0.layer.name == FadingMarkerAnnotationView.disappearanceSnapshotName }
        snapshots = max(snapshots, fading.count)
        invalidSnapshot = invalidSnapshot || fading.contains { $0.isUserInteractionEnabled || !$0.accessibilityElementsHidden }
        for case let ghost as UIImageView in fading where checkedSnapshots.insert(ObjectIdentifier(ghost)).inserted {
            if let image = ghost.image?.cgImage, hasVisiblePixels(image) { nonemptySnapshots += 1 }
            else { invalidSnapshot = true }
        }
        let visible = map.annotations.compactMap { map.view(for: $0) as? FadingMarkerAnnotationView }
        for marker in visible where marker.appearanceOpacity > 0 && marker.appearanceOpacity < 1 && !marker.isHidden {
            let id = ObjectIdentifier(marker)
            guard sampledCycles[id] != marker.appearanceCycle else { continue }
            sampledCycles[id] = marker.appearanceCycle
            if marker.annotation is MKClusterAnnotation { clusterFades += 1 }
            else { singleFades += 1 }
        }
        let opaque = visible.filter { !$0.isHidden && $0.alpha == 1 && $0.appearanceOpacity == 1 }.count
        status.text = "single=\(singleFades) cluster=\(clusterFades) reused=\(reused) snapshots=\(snapshots) images=\(nonemptySnapshots) active=\(fading.count) opaque=\(opaque) invalid=\(invalidSnapshot ? 1 : 0) motion=\(motionSamples) travel=\(Int(motionTravel)) error=\(Int(ceil(motionError)))"
    }

    private func recordMotionAnchors() {
        for ghost in map.subviews where ghost.layer.name == FadingMarkerAnnotationView.disappearanceSnapshotName {
            let id = ObjectIdentifier(ghost)
            guard motionAnchors[id] == nil else { continue }
            // The test's two separate points are horizontally spaced apart.
            // Match the outgoing image independently of the production driver.
            let coordinate = points.min {
                abs(map.convert($0.coordinate, toPointTo: map).x - ghost.frame.midX) <
                    abs(map.convert($1.coordinate, toPointTo: map).x - ghost.frame.midX)
            }!.coordinate
            let anchor = map.convert(coordinate, toPointTo: map)
            motionAnchors[id] = MotionAnchor(coordinate: coordinate,
                offset: CGPoint(x: ghost.frame.minX - anchor.x, y: ghost.frame.minY - anchor.y),
                initialOrigin: ghost.frame.origin)
        }
    }

    private func sampleMotion() {
        for ghost in map.subviews where ghost.layer.name == FadingMarkerAnnotationView.disappearanceSnapshotName {
            guard let original = motionAnchors[ObjectIdentifier(ghost)] else { continue }
            let anchor = map.convert(original.coordinate, toPointTo: map)
            let expected = CGPoint(x: anchor.x + original.offset.x, y: anchor.y + original.offset.y)
            motionSamples += 1
            motionError = max(motionError, hypot(ghost.frame.minX - expected.x, ghost.frame.minY - expected.y))
            motionTravel = max(motionTravel, hypot(ghost.frame.minX - original.initialOrigin.x, ghost.frame.minY - original.initialOrigin.y))
        }
    }

    private func hasVisiblePixels(_ image: CGImage) -> Bool {
        var bytes = [UInt8](repeating: 0, count: 16 * 16 * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: 16, height: 16, bitsPerComponent: 8,
                                    bytesPerRow: 64, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: 16, height: 16))
        }
        return stride(from: 3, to: bytes.count, by: 4).contains { bytes[$0] > 0 }
    }
}

final class MapGestureCheckController: UIViewController {
    let map = NonAdjustingMapView()
    let status = UILabel()
    var cameraLink: CADisplayLink?
    var manual = false
    var begins = 0
    var ends = 0
    var touchStarted = Date()
    var heldMilliseconds = 0
    let origin = CLLocationCoordinate2D(latitude: 22.3193, longitude: 114.1694)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        map.translatesAutoresizingMaskIntoConstraints = false
        status.translatesAutoresizingMaskIntoConstraints = false
        status.accessibilityIdentifier = "cameraStatus"
        status.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        status.numberOfLines = 0
        view.addSubview(map)
        view.addSubview(status)
        NSLayoutConstraint.activate([
            status.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            status.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            status.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            status.heightAnchor.constraint(equalToConstant: 80),
            map.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 12),
            map.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            map.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            map.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        map.onTouchBegan = { [weak self] in
            guard let self else { return }
            manual = true
            begins += 1
            touchStarted = Date()
            map.allowsUserCameraChanges = true
            map.allowCameraChange = true
            map.setCamera(map.camera.copy() as! MKMapCamera, animated: false)
            map.allowCameraChange = false
        }
        map.onTouchEnded = { [weak self] in
            guard let self else { return }
            ends += 1
            heldMilliseconds = Int(Date().timeIntervalSince(touchStarted) * 1000)
        }
        map.allowCameraChange = true
        map.setCamera(MKMapCamera(lookingAtCenter: origin, fromDistance: 1400, pitch: 42, heading: 0), animated: false)
        map.allowCameraChange = false
        let link = CADisplayLink(target: self, selector: #selector(frame))
        link.preferredFramesPerSecond = 60
        link.add(to: .main, forMode: .common)
        cameraLink = link
    }

    @objc func frame() {
        if !manual {
            map.allowCameraChange = true
            map.setCamera(MKMapCamera(lookingAtCenter: origin, fromDistance: 1400, pitch: 42, heading: 0), animated: false)
            map.allowCameraChange = false
        }
        let displacement = CLLocation(latitude: map.centerCoordinate.latitude, longitude: map.centerCoordinate.longitude)
            .distance(from: CLLocation(latitude: origin.latitude, longitude: origin.longitude))
        status.text = "distance=\(Int(displacement)) zoom=\(Int(map.camera.centerCoordinateDistance)) heading=\(Int(map.camera.heading)) begins=\(begins) ends=\(ends) heldMs=\(heldMilliseconds)"
    }
}
