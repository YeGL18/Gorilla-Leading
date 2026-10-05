require 'xcodeproj'
require 'fileutils'

repo = File.expand_path('..', __dir__)
root = '/private/tmp/GorillaParkingAreaUI'
FileUtils.mkdir_p(root)
models = File.read('/private/tmp/gorilla-parking-level-tests/Models.swift')
location = File.read("#{repo}/GorillaTranslate/Models/LocationManager.swift")
map = File.read("#{repo}/GorillaTranslate/Views/MapView.swift")
def section(text, first, last)
  start = text.index(first) or abort "Missing #{first}"
  finish = text.index(last, start) or abort "Missing #{last}"
  text[start...finish]
end
coordinates = section(location, 'extension CLLocationCoordinate2D {', 'enum ParkingFloorMode:')
annotation = section(map, 'final class ParkingPointAnnotation:', 'final class ParkingRangeRenderer:')
tap_and_hit = section(map, '        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive', '        /// 點擊地圖空白處收縮膠囊')
drag = section(map, '        @objc func handleParkingDrag(', '        private var validTrackingLocation:')
select = section(map, '        func mapView(_ mapView: MKMapView, didSelect view:', '        func mapView(_ mapView: MKMapView, didDeselect')
setup = section(map, '        let parkingDrag = UILongPressGestureRecognizer', '        let compassButton = MKCompassButton')
setup.gsub!('context.coordinator', 'coordinator')
fixture = <<~SWIFT
  import SwiftUI
  import MapKit
  #{models}
  #{coordinates}
  #{annotation}
  #{File.read("#{repo}/GorillaTranslate/Views/ParkingAreaViews.swift")}
  final class ParkingMeterManager {
    static let shared = ParkingMeterManager()
    var selectedMeter: Int?
    func representative(_ members: [Int]) -> Int? { nil }
    func select(_ meter: Int) {}
  }
  enum MeterMapLayer { static func members(_ annotation: MKAnnotation?) -> [Int] { [] } }
  final class GestureMap: MKMapView { var allowCameraChange = false }
  struct GestureFixture: UIViewRepresentable {
    var onSelectParkingPoint: (UUID?) -> Void
    var onMoveParkingPoint: (UUID, CLLocationCoordinate2D) -> Void
    var onSelectHKLocation: ((String, CLLocationCoordinate2D)?) -> Void = { _ in }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> GestureMap {
      let mapView = GestureMap()
      let coordinator = context.coordinator
      coordinator.mapView = mapView
      mapView.delegate = coordinator
      let coordinate = CLLocationCoordinate2D(latitude: 22.316, longitude: 114.18)
      mapView.setRegion(MKCoordinateRegion(center: coordinate,
        latitudinalMeters: 800, longitudinalMeters: 800), animated: false)
      #{setup}
      let annotation = ParkingPointAnnotation(pointID: UUID(), coordinate: coordinate,
        title: "Parking", subtitle: nil, isAutomotive: true)
      mapView.addAnnotation(annotation)
      return mapView
    }
    func updateUIView(_ map: GestureMap, context: Context) { context.coordinator.parent = self }
    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
      var parent: GestureFixture
      weak var mapView: GestureMap?
      var isParkingPointDragging = false, isApplyingParkingSelection = false
      var isUserInteracting = false, isFlying = false, pendingAutoZoom = false, hasInitialized = false
      var isHKDragging = false
      var flyTimer: Timer?, autoZoomTimer: Timer?, realTimeUpdateTimer: Timer?, smoothPanTimer: Timer?
      var parkingDragTimer: Timer?, hkDragTimer: Timer?
      var hkAnnotations: [MKPointAnnotation] = []
      var draggingParkingPointID: UUID?
      weak var draggingParkingAnnotation: ParkingPointAnnotation?
      var draggingHKAnnotation: MKPointAnnotation?, hkDragTitle: String?
      var dragTargetCoordinate: CLLocationCoordinate2D?
      var parkingDragGrabOffset = CGPoint.zero
      init(_ parent: GestureFixture) { self.parent = parent }
      func scheduleAutoZoom() {}
      static func saveHKOverride(name: String, coordinate: CLLocationCoordinate2D) {}
      func updateMeterDetailSelection(_ meter: Int, forceOverview: Bool) {}
      func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
      #{tap_and_hit}
      #{drag}
      #{select}
      func mapView(_ map: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "parking")
        view.glyphText = "P"
        view.markerTintColor = .systemOrange
        view.centerOffset = CGPoint(x: 0, y: -10)
        view.isDraggable = false
        view.canShowCallout = false
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = "parkingMarker"
        return view
      }
    }
  }
  struct AreaFixture: View {
    @ObservedObject var store: ParkingFloorStore
    @State private var showBoundary = false
    @State private var showMerge = false
    @State private var opened = 0
    @State private var moved = 0
    var body: some View {
      VStack {
        HStack {
          Button("Boundary") { showBoundary = true }
          Button("Merge Areas") { showMerge = true }
        }.buttonStyle(.bordered)
        Text("\\(store.lots.first?.boundaryVertices?.count ?? 0)").accessibilityIdentifier("savedVertexCount")
        Text("\\(store.lots.count)").accessibilityIdentifier("lotCount")
        Text("\\(opened)").accessibilityIdentifier("openCount")
        Text("\\(moved)").accessibilityIdentifier("moveCount")
        GestureFixture(onSelectParkingPoint: { if $0 != nil { opened += 1 } }, onMoveParkingPoint: { _, _ in moved += 1 })
      }
      .sheet(isPresented: $showBoundary) { ParkingBoundaryEditor(store: store, lot: store.lots[0]) }
      .sheet(isPresented: $showMerge) { ParkingLotMergeView(store: store, sourceID: store.lots[1].id) }
    }
  }
  @main struct ParkingAreaCheckApp: App {
    @StateObject private var store: ParkingFloorStore
    init() {
      let date = TestClock.now
      let lots = (0..<2).map { i in
        let point = ParkingPointRecord(id: UUID(), address: "Residence", latitude: 22.316, longitude: 114.18,
          createdAt: date, predictedFloorIndex: -1)
        return ParkingLotRecord(id: UUID(), name: i == 0 ? "Residence" : "Residence Annex",
        centerLatitude: 22.316, centerLongitude: 114.18, radiusMeters: 180, createdAt: date,
        updatedAt: date, points: [point]) }
      TestDefaults.standard.set(try! JSONEncoder().encode(lots), forKey: "parking_floor_store_v1")
      let store = ParkingFloorStore()
      store.prepare()
      _store = StateObject(wrappedValue: store)
    }
    var body: some Scene { WindowGroup { AreaFixture(store: store) } }
  }
SWIFT
File.write("#{root}/AreaFixture.swift", fixture)
project = Xcodeproj::Project.new("#{root}/ParkingAreaChecks.xcodeproj")
app = project.new_target(:application, 'ParkingAreaChecks', :ios, '18.0')
tests = project.new_target(:ui_test_bundle, 'ParkingAreaUITests', :ios, '18.0')
app.source_build_phase.add_file_reference(project.main_group.new_file("#{root}/AreaFixture.swift"))
tests.source_build_phase.add_file_reference(project.main_group.new_file("#{repo}/Tests/ParkingAreaUITests.swift"))
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
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.gorilla.parking-area-checks'
  config.build_settings['INFOPLIST_KEY_UIApplicationSceneManifest_Generation'] = 'YES'
  config.build_settings['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
  config.build_settings['INFOPLIST_KEY_UISupportedInterfaceOrientations'] = 'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight'
end
tests.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.gorilla.parking-area-uitests'
  config.build_settings['TEST_TARGET_NAME'] = 'ParkingAreaChecks'
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_build_target(tests)
scheme.add_test_target(tests)
scheme.set_launch_target(app)
scheme.save_as(project.path, 'ParkingAreaChecks', true)
