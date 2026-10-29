require 'xcodeproj'
require 'fileutils'
repo = File.expand_path('..', __dir__)
root = '/private/tmp/GorillaParkingPresentationUI'
FileUtils.mkdir_p(root)
def section(text, first, last)
  start = text.index(first) or abort "Missing #{first}"
  finish = text.index(last, start) or abort "Missing #{last}"
  text[start...finish]
end
map = File.read(ENV.fetch('MAP_SOURCE', "#{repo}/GorillaTranslate/Views/MapView.swift"))
content = File.read("#{repo}/GorillaTranslate/ContentView.swift")
toolbarOffset = section(content, '    private var mapToolbarVerticalOffset:', '    private var boundaryToolbarHeight:')
location = File.read("#{repo}/GorillaTranslate/Models/LocationManager.swift")
models = File.read('/private/tmp/gorilla-parking-level-tests/Models.swift')
coordinates = section(location, 'extension CLLocationCoordinate2D {', 'enum ParkingFloorMode:')
drawing = section(map, '        func beginBoundaryDraw(on ', '        @objc func handleParkingTap(')
driving = section(map, "        @MainActor\n        private final class TrackingDisplayLinkTarget:", '        func updateMeterDetailPresentation(').gsub(/\bCoordinator\b/, 'EntryTrackingCoordinator')
layout = section(map, '        /// 首次顯示先套用完整 frame', '        func beginManualCameraControl(')
highAltitude = section(map, '        private func showHighAltitudeView(', '        func scheduleAutoZoom(')
trackingEntry = section(map, '        func startTracking(', '        private func showHighAltitudeView(')
tracking = section(map, '        private func flyToLocation(', '        func flyToCoordinate(')
popup = section(map, '        private var lastParkingPopupCameraID:', '        /// 彈窗開咗對位停車點：')
fixture = <<~SWIFT
  import SwiftUI
  import MapKit
  #{models}
  #{coordinates}
  struct DrawingParent {
    var boundaryDrawVertices: [ParkingBoundaryVertex]? = []
    var boundaryDrawBridge: BoundaryDrawMapBridge? = BoundaryDrawMapBridge()
  }
  final class DrawingCoordinator {
    var parent = DrawingParent()
    weak var mapView: NonAdjustingMapView?
    weak var container: UIView?
    var boundaryCanvas: BoundaryDrawCanvas?
    var boundaryDrawSessionID: UUID?
    var boundaryFlightTimer: Timer?
    var boundaryMapInteractionWasEnabled: Bool?
    var boundaryMapGestures: (scroll: Bool, zoom: Bool, pitch: Bool, rotate: Bool, userCamera: Bool)?
    var isBoundaryFlightInProgress: Bool { boundaryMapGestures != nil && boundaryCanvas == nil }
    var isUserInteracting = false
    var cameraAnimationGeneration = 0
    var isFlying = false
    var routeReturnTimer: Timer?
    var isBoundaryDrawing: Bool { parent.boundaryDrawVertices != nil }
    func endMeterOverview() {}
    func freezeAutomaticCamera() {
      cameraAnimationGeneration += 1
      routeReturnTimer?.invalidate()
      routeReturnTimer = nil
      isFlying = false
    }
    func scheduleAutoZoom() {}
    func focusParkingPopupPoint(pointID: UUID, mapView: NonAdjustingMapView, container: UIView) {}
    #{popup}
    #{drawing}
    func dismissSourcePopup() { updateParkingPopupCameraFreeze(nil) }
    func seedPopup() { lastParkingPopupCameraID = UUID() }
  }
  struct BoundaryCameraFixture: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
      let root = UIView()
      let map = NonAdjustingMapView()
      root.addSubview(map)
      map.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([map.topAnchor.constraint(equalTo: root.topAnchor), map.bottomAnchor.constraint(equalTo: root.bottomAnchor), map.leadingAnchor.constraint(equalTo: root.leadingAnchor), map.trailingAnchor.constraint(equalTo: root.trailingAnchor)])
      let result = UILabel()
      result.accessibilityIdentifier = "boundaryCameraResult"
      root.addSubview(result)
      result.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([result.centerXAnchor.constraint(equalTo: root.centerXAnchor), result.topAnchor.constraint(equalTo: root.topAnchor, constant: 20)])
      let coordinator = DrawingCoordinator()
      coordinator.mapView = map
      coordinator.container = root
      context.coordinator.drawing = coordinator
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        map.allowCameraChange = true
        let initial = MKMapCamera(lookingAtCenter: CLLocationCoordinate2D(latitude: 22.3, longitude: 114.17), fromDistance: 2400, pitch: 40, heading: 130)
        map.setCamera(initial, animated: false)
        map.allowCameraChange = false
        let startDistance = map.camera.centerCoordinateDistance
        coordinator.seedPopup()
        coordinator.parent.boundaryDrawBridge?.initialFocus = (CLLocationCoordinate2D(latitude: 22.303, longitude: 114.174), 1200)
        coordinator.beginBoundaryDraw(on: map)
        let generation = coordinator.cameraAnimationGeneration
        coordinator.dismissSourcePopup()
        let bridge = coordinator.parent.boundaryDrawBridge!
        var valid = generation == coordinator.cameraAnimationGeneration && abs(map.camera.centerCoordinateDistance - startDistance) < 2
        valid = valid && coordinator.boundaryCanvas == nil && !bridge.isReady && bridge.centerCoordinateProvider == nil
        valid = valid && !map.isUserInteractionEnabled && !map.isScrollEnabled && !map.isZoomEnabled
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
          valid = valid && map.camera.centerCoordinateDistance > 1200 && map.camera.centerCoordinateDistance < startDistance
          valid = valid && coordinator.boundaryCanvas == nil && !bridge.isReady && bridge.centerCoordinateProvider == nil
          coordinator.beginBoundaryDraw(on: map)
          valid = valid && coordinator.cameraAnimationGeneration == generation
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
          let opacity = coordinator.boundaryCanvas?.layer.presentation()?.opacity ?? 0
          valid = valid && opacity > 0 && opacity < 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
          valid = valid && abs(map.camera.centerCoordinateDistance - 1200) < 2 && map.camera.pitch < 0.1 && !coordinator.isFlying
          valid = valid && abs(map.centerCoordinate.latitude - 22.303) < 0.00001 && abs(map.centerCoordinate.longitude - 114.174) < 0.00001
          valid = valid && bridge.isReady && bridge.centerCoordinateProvider?() != nil && coordinator.boundaryCanvas != nil
          valid = valid && map.isUserInteractionEnabled && map.isScrollEnabled && map.isZoomEnabled && !map.isRotateEnabled && !map.isPitchEnabled
          bridge.reset()
          coordinator.parent.boundaryDrawVertices = nil
          coordinator.endBoundaryDraw(on: map)
          valid = valid && coordinator.boundaryCanvas == nil && map.isRotateEnabled && map.isPitchEnabled
          // Cancel a fresh flight before arrival. Its old timer must not reveal a canvas later.
          coordinator.parent.boundaryDrawVertices = []
          bridge.initialFocus = (CLLocationCoordinate2D(latitude: 22.4, longitude: 114.2), 1800)
          coordinator.beginBoundaryDraw(on: map)
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            bridge.reset()
            coordinator.parent.boundaryDrawVertices = nil
            coordinator.endBoundaryDraw(on: map)
            let cancelledCenter = map.centerCoordinate
            let cancelledDistance = map.camera.centerCoordinateDistance
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
              valid = valid && coordinator.boundaryCanvas == nil && !bridge.isReady && bridge.centerCoordinateProvider == nil
              valid = valid && map.isUserInteractionEnabled && map.isScrollEnabled && map.isZoomEnabled && map.isRotateEnabled && map.isPitchEnabled
              valid = valid && abs(map.camera.centerCoordinateDistance - cancelledDistance) < 2
              valid = valid && abs(map.centerCoordinate.latitude - cancelledCenter.latitude) < 0.00001 && coordinator.boundaryFlightTimer == nil
              result.text = valid ? "PASS" : "FAIL"
            }
          }
        }
      }
      return root
    }
    func updateUIView(_ view: UIView, context: Context) {}
    func makeCoordinator() -> Holder { Holder() }
    final class Holder { var drawing: DrawingCoordinator? }
  }
  struct TrackingLocationManager { var mapReferenceLocation: CLLocation? }
  struct TrackingParent { var followHeading = false; var locationManager = TrackingLocationManager(); var savedRegion: MKCoordinateRegion? }
  let hongKongMapFallback = CLLocation(latitude: 22.3, longitude: 114.17)
  @MainActor final class EntryTrackingCoordinator {
    var parent = TrackingParent()
    weak var mapView: NonAdjustingMapView?
    var automaticCameraPaused = false
    var autoZoomTimer: Timer?
    var flyTimer: Timer?
    var cameraAnimationGeneration = 0
    var isFlying = false
    var isDriving = false
    var northOverrideArmed = false
    var hasShownHighAltitude = true
    var pendingAutoZoom = false
    var validTrackingLocation: CLLocation?
    func fallbackTrackingDistance(for location: CLLocation) -> CLLocationDistance { 8000 }
    var hasInitialized = false
    var centerOffsetX: CGFloat = 0
    var centerOffsetY: CGFloat = 0
    var hasAppliedMapLayout = false
    var lastMapContainerSize: CGSize = .zero
    var drivingDisplayLink: CADisplayLink?
    var drivingMotion = MapCameraMotion()
    var lastTrackingFrame: CFTimeInterval = 0
    var lastTrackingDistanceUpdate: CFTimeInterval = 0
    var cachedDrivingDistance: CLLocationDistance = 1800
    var cachedSoftTracking = true
    let drivingPitch: CGFloat = 42
    let idlePitch: CGFloat = 0
    let correctedHeading: CLLocationDirection = 0
    func freezeAutomaticCamera() {
      cameraAnimationGeneration += 1
      stopDrivingTracking()
      flyTimer?.invalidate()
      flyTimer = nil
      isFlying = false
    }
    func trackingDistance(for location: CLLocation) -> CLLocationDistance { isDriving ? 1800 : 800 }
    func stopContinuousHeading() {}
    var smoothPanTimer: Timer?
    func trackingFlightTarget(fallback: CLLocationCoordinate2D, at date: Date) -> CLLocationCoordinate2D { fallback }
    func startRealTimeUpdates() { startDrivingTracking() }
    func receiveDrivingFix(_ location: CLLocation) { validTrackingLocation = location; startDrivingTracking() }
    #{layout}
    #{driving}
    #{highAltitude}
    #{trackingEntry}
    #{tracking}
    func enterMap(at location: CLLocation) {
      guard let mapView else { return }
      validTrackingLocation = location
      startTracking(useHongKongFallback: true)
    }
  }
  struct EntryCameraFixture: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
      let root = UIView()
      let map = NonAdjustingMapView()
      root.addSubview(map)
      map.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([map.topAnchor.constraint(equalTo: root.topAnchor), map.bottomAnchor.constraint(equalTo: root.bottomAnchor), map.leadingAnchor.constraint(equalTo: root.leadingAnchor), map.trailingAnchor.constraint(equalTo: root.trailingAnchor)])
      let result = UILabel()
      result.accessibilityIdentifier = "entryCameraResult"
      root.addSubview(result)
      result.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([result.centerXAnchor.constraint(equalTo: root.centerXAnchor), result.topAnchor.constraint(equalTo: root.topAnchor, constant: 20)])
      let coordinator = EntryTrackingCoordinator()
      coordinator.mapView = map
      context.coordinator.tracking = coordinator
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        map.allowCameraChange = true
        map.setCamera(MKMapCamera(lookingAtCenter: CLLocationCoordinate2D(latitude: 22.3, longitude: 114.17), fromDistance: 50000, pitch: 0, heading: 30), animated: false)
        map.allowCameraChange = false
        coordinator.enterMap(at: CLLocation(latitude: 22.301, longitude: 114.172))
        var beforeResize: CLLocationDistance = 0
        let generation = coordinator.cameraAnimationGeneration
        var valid = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
          beforeResize = map.camera.centerCoordinateDistance
          coordinator.startTracking(useHongKongFallback: true)
          valid = valid && coordinator.cameraAnimationGeneration == generation
          // Production updateUIView clears this permission when orientation changes.
          map.allowCameraChange = false
          map.frame.size = CGSize(width: map.bounds.width - 10, height: map.bounds.height)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
          valid = valid && map.camera.centerCoordinateDistance < beforeResize - 1000
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.8) {
          valid = valid && abs(map.camera.centerCoordinateDistance - 800) < 2 && !coordinator.isFlying
          valid = valid && abs(map.centerCoordinate.latitude - 22.301) < 0.00001 && abs(map.centerCoordinate.longitude - 114.172) < 0.00001
          result.text = valid ? "PASS" : "FAIL"
        }
      }
      return root
    }
    func updateUIView(_ view: UIView, context: Context) {}
    func makeCoordinator() -> Holder { Holder() }
    final class Holder { var tracking: EntryTrackingCoordinator? }
  }
  struct InitialDrivingCameraFixture: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
      let root = UIView()
      let map = NonAdjustingMapView()
      root.addSubview(map)
      let result = UILabel()
      result.accessibilityIdentifier = "initialDrivingCameraResult"
      root.addSubview(result)
      result.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([result.centerXAnchor.constraint(equalTo: root.centerXAnchor), result.topAnchor.constraint(equalTo: root.topAnchor, constant: 20)])
      let coordinator = EntryTrackingCoordinator()
      coordinator.mapView = map
      coordinator.isDriving = true
      coordinator.hasShownHighAltitude = false
      context.coordinator.tracking = coordinator
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        let coordinate = CLLocationCoordinate2D(latitude: 22.3, longitude: 114.17)
        map.allowCameraChange = true
        map.setCamera(MKMapCamera(lookingAtCenter: coordinate, fromDistance: 50000, pitch: 0, heading: 0), animated: false)
        map.allowCameraChange = false
        coordinator.updateMapFrame(in: root, centerOffset: CGPoint(x: 0, y: -120))
        var valid = map.layer.animationKeys()?.isEmpty != false
        let initialDistance = map.camera.centerCoordinateDistance
        let location = CLLocation(coordinate: coordinate, altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, course: 0, speed: 14, timestamp: Date())
        coordinator.receiveDrivingFix(location)
        valid = valid && coordinator.drivingDisplayLink == nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
          valid = valid && abs(map.camera.centerCoordinateDistance - initialDistance) < 2 && map.camera.pitch < 0.1
          coordinator.enterMap(at: location)
          valid = valid && abs(map.camera.centerCoordinateDistance - initialDistance) < 2
          let generation = coordinator.cameraAnimationGeneration
          var previousDistance = map.camera.centerCoordinateDistance
          var upwardJumps = 0
          let sampler = Timer(timeInterval: 1.0 / 60.0, repeats: true) { _ in
            let distance = map.camera.centerCoordinateDistance
            if distance > previousDistance + 2 { upwardJumps += 1 }
            previousDistance = distance
          }
          RunLoop.main.add(sampler, forMode: .common)
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            coordinator.startTracking(useHongKongFallback: true)
            coordinator.updateMapFrame(in: root, centerOffset: CGPoint(x: 0, y: -120))
            valid = valid && coordinator.cameraAnimationGeneration == generation && coordinator.drivingDisplayLink == nil
          }
          DispatchQueue.main.asyncAfter(deadline: .now() + 4.3) {
            coordinator.receiveDrivingFix(CLLocation(coordinate: coordinate, altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, course: 0, speed: 14, timestamp: Date()))
          }
          DispatchQueue.main.asyncAfter(deadline: .now() + 4.8) {
            sampler.invalidate()
            valid = valid && upwardJumps == 0 && !coordinator.isFlying && coordinator.drivingDisplayLink != nil
            valid = valid && abs(map.camera.centerCoordinateDistance - 1800) < 2
            coordinator.stopDrivingTracking()
            result.text = valid ? "PASS" : "FAIL"
            result.accessibilityValue = "upwardJumps=\\(upwardJumps) distance=\\(map.camera.centerCoordinateDistance)"
          }
        }
      }
      return root
    }
    func updateUIView(_ view: UIView, context: Context) {
      if let tracking = context.coordinator.tracking {
        tracking.updateMapFrame(in: view, centerOffset: CGPoint(x: 0, y: -120))
      }
    }
    func makeCoordinator() -> Holder { Holder() }
    final class Holder { var tracking: EntryTrackingCoordinator? }
  }
  struct PresentationFixture: View {
    @StateObject private var store = ParkingFloorStore()
    @State private var merge = false
    @State private var draw = false
    @State private var editingEnabled = false
    var body: some View {
      NavigationStack {
        VStack {
          BoundaryCameraFixture().frame(height: 180)
          EntryCameraFixture().frame(height: 160)
          InitialDrivingCameraFixture().frame(height: 160)
          Text("\\(store.lots.count)").accessibilityIdentifier("presentationLotCount")
          Button("Merge Areas") { merge = true }
          Button("Draw Boundary") { withAnimation(.spring(response: 0.6, dampingFraction: 0.78)) { draw.toggle(); editingEnabled = false } }
          if draw { Button("Finish Camera Flight") { editingEnabled = true } }
          if draw { Button("Simulate Vertex Drag") { editingEnabled = false } }
          ZStack {
            if draw {
              BoundaryDrawToolbar(vertexCount: 3, canConfirm: true, editingEnabled: editingEnabled, onCancel: { draw = false }, onUndo: {}, onAdd: {}, onConfirm: { draw = false })
            } else { Text("Address").font(.body.bold()) }
          }
          .frame(width: draw ? 370 : 270, height: draw ? 56 : 44)
          .glassEffect(.regular, in: .rect(cornerRadius: 34))
          Spacer()
        }.padding(.top)
        .sheet(isPresented: $merge) {
          if let source = store.lots.first { ParkingLotMergeView(store: store, sourceID: source.id) }
        }
        .onAppear {
          if store.lots.isEmpty {
            let lots = [22.3, 22.4].enumerated().map { index, lat in
              ParkingLotRecord(id: UUID(), name: index == 0 ? "Source Parking" : "Target Parking", centerLatitude: lat,
                centerLongitude: 114.17, radiusMeters: 180, createdAt: TestClock.now, updatedAt: TestClock.now, points: [])
            }
            TestDefaults.standard.set(try! JSONEncoder().encode(lots), forKey: "parking_floor_store_v1")
            store.prepare()
          }
        }
      }
    }
  }
  struct DragSelectionFixture: UIViewRepresentable {
    func makeCoordinator() -> Delegate { Delegate() }
    func makeUIView(context: Context) -> UIView {
      let root = UIView()
      let map = NonAdjustingMapView(frame: CGRect(x: 0, y: 60, width: 390, height: 500))
      root.addSubview(map)
      let result = UILabel(frame: CGRect(x: 10, y: 5, width: 380, height: 50))
      result.accessibilityIdentifier = "dragSelectionResult"
      result.text = "Waiting"
      root.addSubview(result)
      context.coordinator.result = result
      map.delegate = context.coordinator
      let meter = context.coordinator.meter
      meter.coordinate = CLLocationCoordinate2D(latitude: 22.3193, longitude: 114.1694)
      map.allowCameraChange = true
      map.setCamera(MKMapCamera(lookingAtCenter: meter.coordinate, fromDistance: 1200, pitch: 0, heading: 0), animated: false)
      map.allowCameraChange = false
      map.addAnnotation(meter)
      return root
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
    final class Delegate: NSObject, MKMapViewDelegate {
      let meter = MKPointAnnotation()
      weak var result: UILabel?
      var popupCount = 0
      var started = false
      func mapView(_ map: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "meter")
      }
      func mapView(_ map: MKMapView, didSelect view: MKAnnotationView) {
        if (map as? NonAdjustingMapView)?.rejectSelectionDuringAnnotationDrag(view) == true { return }
        popupCount += 1
      }
      func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
        guard !started, let map = mapView as? NonAdjustingMapView,
              let marker = views.first(where: { $0.annotation === meter }) else { return }
        started = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
          var valid = true
          map.beginAnnotationDrag()
          // A crossing hit and the delegate path that bypasses selectAnnotation.
          map.selectAnnotation(self.meter, animated: false)
          self.mapView(map, didSelect: marker)
          valid = valid && map.selectedAnnotations.isEmpty && self.popupCount == 0
          // A second finger during deceleration must not unlock selection.
          map.beginAnnotationTouch()
          map.selectAnnotation(self.meter, animated: false)
          valid = valid && map.isAnnotationSelectionSuppressed && self.popupCount == 0
          map.endAnnotationDrag()
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            // The release callback can arrive after the drag timer has finished.
            map.selectAnnotation(self.meter, animated: false)
            self.mapView(map, didSelect: marker)
            valid = valid && map.selectedAnnotations.isEmpty && self.popupCount == 0
            map.beginAnnotationTouch()
            map.selectAnnotation(self.meter, animated: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
              valid = valid && !map.isAnnotationSelectionSuppressed && self.popupCount == 1
                && map.selectedAnnotations.contains(where: { $0 === self.meter })
              self.result?.text = valid ? "PASS" : "FAIL: popups=\\(self.popupCount)"
            }
          }
        }
      }
    }
  }
  struct ToolbarClearanceFixture: View {
    @State private var draw = false
    @State private var invalidBoundary = false
    @State private var isLandscape = false
    var boundaryDrawLot: Bool? { draw ? true : nil }
    var boundaryToolbarHeight: CGFloat { invalidBoundary ? 82 : 56 }
    let isParkingMemoryExpanded = false
    let isFloorCurveInCapsule = false
    let isCapsuleExpanded = false
    #{toolbarOffset}
    var body: some View {
      GeometryReader { geometry in
        VStack {
          Button("Draw Boundary") { withAnimation(.spring(response: 0.6, dampingFraction: 0.78)) { draw = true } }
          Button("Show Invalid Boundary") { invalidBoundary = true }.disabled(!draw)
          Spacer()
          ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
              if draw {
                BoundaryDrawToolbar(vertexCount: 3, canConfirm: !invalidBoundary,
                    onCancel: { withAnimation(.spring(response: 0.6, dampingFraction: 0.78)) { draw = false; invalidBoundary = false } },
                    onUndo: {}, onAdd: {}, onConfirm: {})
                if invalidBoundary { Text("Invalid boundary").font(.caption).frame(height: 26) }
              } else { Text("Address") }
            }
            .frame(width: draw ? min(370, geometry.size.width - 32) : 270, height: draw ? boundaryToolbarHeight : 44)
            .animation(.spring(response: 0.6, dampingFraction: 0.78), value: draw)
            .animation(.smooth(duration: 0.25), value: boundaryToolbarHeight)
            .glassEffect(.regular, in: .rect(cornerRadius: 34))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("previewCapsule")
            .padding(.bottom, 28)
            VStack(spacing: 10) {
              Button("Heading") {}.accessibilityIdentifier("previewHeading")
              Button("Search") {}.accessibilityIdentifier("previewSearch")
              Button("Map") {}.accessibilityIdentifier("previewMapMode")
            }
            .frame(width: 44)
            .buttonStyle(.glass)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 16)
            .padding(.bottom, 72)
            .offset(y: mapToolbarVerticalOffset)
            .animation(.timingCurve(0.4, 0.0, 0.2, 1.0, duration: 0.5), value: mapToolbarVerticalOffset)
            .animation(.spring(response: 0.6, dampingFraction: 0.78), value: draw)
            .animation(.smooth(duration: 0.25), value: boundaryToolbarHeight)
          }
          .frame(height: 260)
          Spacer()
        }
        .onAppear { isLandscape = geometry.size.width > geometry.size.height }
      }
    }
  }
  struct VertexDragFixture: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIView {
      let root = UIView()
      let map = MKMapView()
      map.frame = root.bounds
      map.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      root.addSubview(map)
      let canvas = BoundaryDrawCanvas(frame: root.bounds)
      canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      canvas.mapView = map
      canvas.isAccessibilityElement = true
      canvas.accessibilityIdentifier = "vertexDragSurface"
      canvas.accessibilityLabel = "Editable boundary"
      map.addSubview(canvas)
      let label = UILabel()
      label.accessibilityIdentifier = "vertexDragResult"
      label.numberOfLines = 3
      label.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
      label.backgroundColor = .systemBackground
      label.translatesAutoresizingMaskIntoConstraints = false
      root.addSubview(label)
      NSLayoutConstraint.activate([label.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
        label.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
        label.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8)])
      let coordinator = context.coordinator
      coordinator.map = map
      coordinator.label = label
      map.delegate = coordinator
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        map.setCamera(MKMapCamera(lookingAtCenter: .init(latitude: 22.303, longitude: 114.174), fromDistance: 1200, pitch: 0, heading: 0), animated: false)
        canvas.frame = map.bounds
        let points = [CGPoint(x: map.bounds.width * 0.25, y: map.bounds.height * 0.3),
          CGPoint(x: map.bounds.width * 0.75, y: map.bounds.height * 0.3),
          CGPoint(x: map.bounds.width * 0.75, y: map.bounds.height * 0.7),
          CGPoint(x: map.bounds.width * 0.25, y: map.bounds.height * 0.7)]
        canvas.vertices = points.map { map.convert($0, toCoordinateFrom: canvas) }
        let original = canvas.vertices
        let center = map.centerCoordinate
        canvas.onVertexMove = { index, coordinate in
          coordinator.moves += 1
          let moved = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            .distance(from: CLLocation(latitude: original[index].latitude, longitude: original[index].longitude)) > 5
          let others = original.indices.filter { $0 != index }.allSatisfy {
            abs(canvas.vertices[$0].latitude - original[$0].latitude) < 1e-9 &&
            abs(canvas.vertices[$0].longitude - original[$0].longitude) < 1e-9
          }
          let stable = abs(map.centerCoordinate.latitude - center.latitude) < 1e-6 && abs(map.centerCoordinate.longitude - center.longitude) < 1e-6
          coordinator.result = "moves=\\(coordinator.moves) moved=\\(moved) others=\\(others) camera=\\(stable)"
          label.text = coordinator.result
        }
        canvas.onVertexInsert = { index, coordinate in
          let previous = original[(index + original.count - 1) % original.count]
          let next = original[index % original.count]
          let midpoint = CLLocation(latitude: (previous.latitude + next.latitude) / 2,
                                    longitude: (previous.longitude + next.longitude) / 2)
          let moved = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude).distance(from: midpoint) > 5
          let others = original.indices.allSatisfy {
            let updated = canvas.vertices[$0 >= index ? $0 + 1 : $0]
            return abs(updated.latitude - original[$0].latitude) < 1e-9 && abs(updated.longitude - original[$0].longitude) < 1e-9
          }
          let stable = abs(map.centerCoordinate.latitude - center.latitude) < 1e-6 && abs(map.centerCoordinate.longitude - center.longitude) < 1e-6
          coordinator.result = "insert=\\(index) count=\\(canvas.vertices.count) moved=\\(moved) others=\\(others) camera=\\(stable)"
          label.text = coordinator.result
        }
        canvas.onVertexDragChanged = { dragging in
          if dragging {
            coordinator.dragBegan = canvas.isDraggingVertex && !map.isScrollEnabled
            if ProcessInfo.processInfo.arguments.contains("--edge-cancel") {
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { canvas.cancelVertexDrag() }
            }
          } else {
            if ProcessInfo.processInfo.arguments.contains("--edge-cancel") {
              coordinator.result = "cancelled count=\\(canvas.vertices.count) uncommitted=\\(coordinator.result.isEmpty)"
            }
            coordinator.result += " restored=\\(map.isScrollEnabled && map.isZoomEnabled && !canvas.isDraggingVertex) dragBegan=\\(coordinator.dragBegan)"
            label.text = coordinator.result
          }
        }
        coordinator.initialCenter = center
        label.text = "READY"
        canvas.reveal()
      }
      return root
    }
    func updateUIView(_ view: UIView, context: Context) {}
    final class Coordinator: NSObject, MKMapViewDelegate {
      weak var map: MKMapView?
      weak var label: UILabel?
      var moves = 0
      var dragBegan = false
      var result = ""
      var initialCenter: CLLocationCoordinate2D?
      func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        guard moves > 0, let initialCenter,
          abs(mapView.centerCoordinate.latitude - initialCenter.latitude) > 1e-5 else { return }
        label?.text = result + " mapPan=true"
      }
    }
  }
  struct ToolbarFeedbackFixture: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIView {
      let root = UIView()
      root.backgroundColor = .white
      let coordinator = context.coordinator
      let toolbar = BoundaryDrawToolbar(vertexCount: 4, canConfirm: true,
        onCancel: {}, onUndo: {}, onAdd: {}, onConfirm: { [weak coordinator] in coordinator?.activated() })
        .frame(width: 370, height: 56)
        .glassEffect(.regular, in: .rect(cornerRadius: 34))
        .highPriorityGesture(DragGesture(minimumDistance: 10), including: .subviews)
      let host = UIHostingController(rootView: toolbar)
      coordinator.host = host
      host.view.backgroundColor = .clear
      host.view.translatesAutoresizingMaskIntoConstraints = false
      root.addSubview(host.view)
      let label = UILabel()
      label.accessibilityIdentifier = "toolbarFeedbackResult"
      label.translatesAutoresizingMaskIntoConstraints = false
      root.addSubview(label)
      coordinator.label = label
      NSLayoutConstraint.activate([host.view.centerXAnchor.constraint(equalTo: root.centerXAnchor),
        host.view.centerYAnchor.constraint(equalTo: root.centerYAnchor),
        host.view.widthAnchor.constraint(equalToConstant: 370), host.view.heightAnchor.constraint(equalToConstant: 56),
        label.centerXAnchor.constraint(equalTo: root.centerXAnchor), label.topAnchor.constraint(equalTo: root.topAnchor, constant: 20)])
      coordinator.timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak coordinator] timer in
        guard let coordinator else { timer.invalidate(); return }
        coordinator.sample()
      }
      return root
    }
    func updateUIView(_ view: UIView, context: Context) {}
    final class Coordinator {
      var host: UIViewController?
      weak var label: UILabel?
      var timer: Timer?
      var baseline = 0, minimum = Int.max, stage = 0, count = 0
      var holdPassed = false
      func sample() {
        guard stage >= 0, let view = host?.view, view.window != nil, view.bounds.width > 0 else { return }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: view.bounds.size, format: format).image { _ in
          view.drawHierarchy(in: view.bounds, afterScreenUpdates: false)
        }
        guard let cg = image.cgImage else { return }
        let width = cg.width, height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let green = pixels.withUnsafeMutableBytes { buffer -> Int in
          guard let ctx = CGContext(data: buffer.baseAddress, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
          ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
          let bytes = buffer.bindMemory(to: UInt8.self)
          return stride(from: 0, to: bytes.count, by: 4).reduce(0) { result, i in
            result + ((bytes[i] < 120 && bytes[i + 1] > 130 && bytes[i + 2] < 170) ? 1 : 0)
          }
        }
        guard green > 20 else { return }
        baseline = max(baseline, green)
        minimum = min(minimum, green)
        if label?.text == nil, baseline > 300 { label?.text = "READY" }
      }
      func activated() {
        count += 1
        let ratio = Double(minimum) / Double(max(1, baseline))
        let passed = ratio > 0.4 && ratio < 0.8
        if count == 1 {
          holdPassed = passed
          stage = -1
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            self.minimum = Int.max
            self.stage = 1
            self.label?.text = "READY2 holdPASS=\\(self.holdPassed)"
          }
        } else {
          stage = -1
          timer?.invalidate()
          label?.text = "count=\\(count) holdPASS=\\(holdPassed) tapPASS=\\(passed)"
        }
      }
    }
  }
  @main struct ParkingPresentationCheckApp: App {
    var body: some Scene { WindowGroup {
      if ProcessInfo.processInfo.arguments.contains("--toolbar-feedback") { ToolbarFeedbackFixture() }
      else if ProcessInfo.processInfo.arguments.contains("--vertex-drag") || ProcessInfo.processInfo.arguments.contains("--edge-insert") || ProcessInfo.processInfo.arguments.contains("--edge-cancel") { VertexDragFixture() }
      else if ProcessInfo.processInfo.arguments.contains("--drag-selection") { DragSelectionFixture() }
      else if ProcessInfo.processInfo.arguments.contains("--toolbar-clearance") { ToolbarClearanceFixture() }
      else { PresentationFixture() }
    } }
  }
SWIFT
File.write("#{root}/Fixture.swift", fixture)
project = Xcodeproj::Project.new("#{root}/PresentationChecks.xcodeproj")
app = project.new_target(:application, 'PresentationChecks', :ios, '26.0')
tests = project.new_target(:ui_test_bundle, 'ParkingPresentationUITests', :ios, '26.0')
app.source_build_phase.add_file_reference(project.main_group.new_file("#{root}/Fixture.swift"))
%w[GorillaTranslate/Views/ParkingAreaViews.swift GorillaTranslate/Views/MapInteraction.swift GorillaTranslate/Models/MapCameraMotion.swift GorillaTranslate/Models/AnimationClock.swift GorillaTranslate/Extensions/AppHaptics.swift].each do |file|
  app.source_build_phase.add_file_reference(project.main_group.new_file("#{repo}/#{file}"))
end
tests.source_build_phase.add_file_reference(project.main_group.new_file("#{repo}/Tests/ParkingPresentationUITests.swift"))
tests.add_dependency(app)
resources = project.main_group.new_variant_group('Localizable.strings')
%w[en zh-Hant zh-Hans ja].each do |locale|
  file = resources.new_file("#{repo}/GorillaTranslate/Resources/Localization/#{locale}.lproj/Localizable.strings")
  file.name = locale
end
app.resources_build_phase.add_file_reference(resources)
[app, tests].each do |target|
  target.build_configurations.each do |config|
    config.build_settings['SWIFT_VERSION'] = '5.0'
    config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
    config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
  end
end
app.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.gorilla.parking-presentation-checks'
  config.build_settings['INFOPLIST_KEY_UIApplicationSceneManifest_Generation'] = 'YES'
  config.build_settings['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
end
tests.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.gorilla.parking-presentation-uitests'
  config.build_settings['TEST_TARGET_NAME'] = 'PresentationChecks'
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app); scheme.add_build_target(tests); scheme.add_test_target(tests); scheme.set_launch_target(app)
scheme.save_as(project.path, 'PresentationChecks', true)
