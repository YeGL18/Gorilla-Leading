require 'xcodeproj'
require 'fileutils'
repo = File.expand_path('..', __dir__)
root = '/private/tmp/GorillaCameraUI'
FileUtils.mkdir_p(root)
meter_source = File.read("#{repo}/GorillaTranslate/Views/ParkingMeterViews.swift")
meter_layers = meter_source[meter_source.index('extension MeterDisplayState')...meter_source.index('struct MeterSettingsSection:')]
content_source = File.read("#{repo}/GorillaTranslate/ContentView.swift")
edit_control = content_source[content_source.index('struct ParkingPointEditControl:')...content_source.index('struct AddressCapsuleDragGeometry {')]
gps_badge = content_source[content_source.index('    private var gpsStatusBadge:')...content_source.index('    private func enterMarkerOverview(')]
File.write("#{root}/Fixture.swift", <<~SWIFT)
  import SwiftUI
  import MapKit
  enum LanguageManager { static let languageCode = "en" }
  extension CLLocationCoordinate2D { var wgs84ToGCJ02: Self { self } }
  @main struct CheckApp: App {
    init() { UserDefaults.standard.set(true, forKey: "trafficCameraEnabled") }
    var body: some Scene { WindowGroup {
      Group {
        if ProcessInfo.processInfo.arguments.contains("--gps-carousel") { GPSCarouselFixture() }
        else if ProcessInfo.processInfo.arguments.contains("--edit-point") { PointEditFixture() }
        else if ProcessInfo.processInfo.arguments.contains("--meters") { MeterOverviewFixture() }
        else { Fixture() }
      }.preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--dark") ? .dark : nil)
    } }
  }
  #{edit_control}
  struct GorillaCapsuleGlass: ViewModifier {
    let cornerRadius: CGFloat
    func body(content: Content) -> some View { content.background(.regularMaterial, in: Capsule()) }
  }
  final class GPSFixtureLocation: ObservableObject { @Published var gpsQuality = 0 }
  struct GPSCarouselFixture: View {
    @StateObject var locationManager = GPSFixtureLocation()
    @ObservedObject var markerOverview = MapMarkerOverviewState.shared
    @State var gpsGlowPhase: CGFloat = 0
    @State var gpsShowsMapDetails = false
    @State var showingMarkerOverviewChoices = false
    var hkDetailMode: Bool { markerOverview.mode != .nearby }
    var gpsColor: Color { .green }
    var gpsLabel: String { "GPS" }
    var body: some View {
      ZStack(alignment: .topTrailing) {
        Color(uiColor: .secondarySystemBackground).ignoresSafeArea()
        gpsStatusBadge.padding(24)
      }
    }
    func enterMarkerOverview(_ mode: MapMarkerOverviewMode) { markerOverview.mode = mode }
    #{gps_badge}
  }
  struct PointEditFixture: View {
    @State var restores = 0
    var body: some View {
      ZStack {
        Color(uiColor: .secondarySystemBackground).ignoresSafeArea()
        VStack(spacing: 20) {
          HStack {
            Text("Parking / stay point").font(.headline)
            ParkingPointEditControl(canRenameFloor: true, canReset: true,
              onRename: {}, onRenameFloor: {}, onBoundary: {}, onMerge: {}, onReset: { restores += 1 })
          }
          Text(verbatim: "Restores \\(restores)").accessibilityIdentifier("restoreCount")
        }
        .padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
      }
    }
  }
  struct Fixture: View {
    @AppStorage("trafficCameraEnabled") var enabled = true
    @State var count = 0
    @State var mode: MapMarkerOverviewMode = .cameras
    @State var showingMenu = false
    var body: some View {
      TabView {
        CameraMap(enabled: enabled, mode: mode, count: $count)
          .overlay(alignment: .top) {
            VStack {
              Text("Markers \\(count)").accessibilityIdentifier("cameraCount")
              Text("GPS").padding(12).background(.regularMaterial, in: Capsule())
                .onTapGesture(count: 2) { showingMenu = true }
                .popover(isPresented: $showingMenu, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                  MapMarkerOverviewMenu { selection in
                    mode = selection
                    showingMenu = false
                  }
                }
              HStack {
                Button("Nearby cameras") { mode = .nearby }
                Button("All cameras") { mode = .cameras }
                Button("Meter overview") { mode = .meters }
              }
            }
          }
          .tabItem { Label("Map", systemImage: "map") }
        NavigationStack { TrafficCameraSettingsView() }
          .tabItem { Label("Settings", systemImage: "gearshape") }
      }.overlay { TrafficCameraDetailOverlay() }
       .task {
         if ProcessInfo.processInfo.arguments.contains("--matched") {
           TrafficCameraStore.shared.selected = TrafficCameraStore.shared.cameras.first { $0.roadSpeedLimitKmh != nil }
         } else if ProcessInfo.processInfo.arguments.contains("--unknown") {
           TrafficCameraStore.shared.selected = TrafficCameraStore.shared.cameras.first { $0.roadSpeedLimitKmh == nil }
         } else if ProcessInfo.processInfo.arguments.contains("--red-light") {
           TrafficCameraStore.shared.selected = TrafficCameraStore.shared.cameras.first { $0.kind == "rlc" }
         }
       }
    }
  }
  class FadingMarkerAnnotationView: MKMarkerAnnotationView {
    func refreshAppearanceSnapshot() {}
  }
  @MainActor final class ParkingMeterManager {
    static let shared = ParkingMeterManager()
    var revision = 1
    var selectedMeter: ParkingMeter?
    func state(_ meter: ParkingMeter) -> MeterDisplayState { .vacant }
  }
  #{meter_layers}
  struct MeterOverviewFixture: View {
    @State var count = 0
    @State var total = 0
    @State var zoomed = false
    @State var ping = 0
    var body: some View {
      MeterOverviewMap(count: $count, total: $total, zoomed: zoomed)
        .overlay(alignment: .top) {
          VStack {
            Text(verbatim: "Annotations \\(count)").accessibilityIdentifier("meterAnnotations")
            Text(verbatim: "Bays \\(total)").accessibilityIdentifier("meterBays")
            Button("Zoom meters") { zoomed.toggle() }
            Button("Ping \\(ping)") { ping += 1 }
          }.padding().background(.regularMaterial)
        }
    }
  }
  struct MeterOverviewMap: UIViewRepresentable {
    @Binding var count: Int
    @Binding var total: Int
    let zoomed: Bool
    static let meters = (0..<24000).map { i in
      ParkingMeter(id: "overview-\\(i)", poleId: "1000", district: "", street: "", streetKey: "",
        latitude: 22.15 + Double(i / 200) * 0.003, longitude: 113.85 + Double(i % 200) * 0.003,
        bayType: .general, lpp: nil, operatingPeriod: "", paymentUnit: nil, timeUnit: nil)
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> MKMapView {
      let map = MKMapView()
      map.delegate = context.coordinator
      return map
    }
    func updateUIView(_ map: MKMapView, context: Context) {
      context.coordinator.refresh = { map in
        let annotations = map.annotations.filter { !MeterMapLayer.members($0).isEmpty }
        let bays = annotations.reduce(0) { $0 + MeterMapLayer.members($1).count }
        DispatchQueue.main.async { count = annotations.count; total = bays }
      }
      if context.coordinator.zoomed != zoomed {
        context.coordinator.zoomed = zoomed
        map.setRegion(.init(center: .init(latitude: 22.34, longitude: 114.16),
          span: .init(latitudeDelta: zoomed ? 0.01 : 0.8, longitudeDelta: zoomed ? 0.01 : 0.9)), animated: false)
      }
      context.coordinator.layer.syncOverview(map: map, meters: Self.meters, manager: .shared)
      context.coordinator.refresh?(map)
    }
    final class Coordinator: NSObject, MKMapViewDelegate {
      let layer = MeterMapLayer()
      var zoomed: Bool?
      var refresh: ((MKMapView) -> Void)?
      func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        layer.syncOverview(map: mapView, meters: MeterOverviewMap.meters, manager: .shared)
        refresh?(mapView)
      }
      func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        MeterMapLayer.view(map: mapView, annotation: annotation, manager: .shared)
      }
    }
  }
  struct CameraMap: UIViewRepresentable {
    let enabled: Bool
    let mode: MapMarkerOverviewMode
    @Binding var count: Int
    func makeCoordinator() -> TrafficCameraMapLayer { TrafficCameraMapLayer() }
    func makeUIView(context: Context) -> MKMapView {
      let map = MKMapView()
      map.delegate = Delegate.shared
      map.setRegion(.init(center: .init(latitude: 22.248, longitude: 114.152),
                          latitudinalMeters: 1800, longitudinalMeters: 1800), animated: false)
      return map
    }
    func updateUIView(_ map: MKMapView, context: Context) {
      context.coordinator.sync(map, enabled: enabled,
        location: CLLocation(latitude: 22.248, longitude: 114.152),
        mode: enabled ? mode : .meters)
      let total = map.annotations.filter { $0 is TrafficCameraAnnotation }.count
      DispatchQueue.main.async { count = total }
    }
    final class Delegate: NSObject, MKMapViewDelegate {
      static let shared = Delegate()
      func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        TrafficCameraMapLayer.view(mapView, annotation: annotation)
      }
      func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        if let annotation = view.annotation as? TrafficCameraAnnotation {
          TrafficCameraStore.shared.selected = annotation.camera
          mapView.deselectAnnotation(annotation, animated: false)
        }
      }
    }
  }
SWIFT
project = Xcodeproj::Project.new("#{root}/CameraChecks.xcodeproj")
app = project.new_target(:application, 'CameraChecks', :ios, '26.0')
tests = project.new_target(:ui_test_bundle, 'TrafficCameraUITests', :ios, '26.0')
group = project.main_group
["#{root}/Fixture.swift", "#{repo}/GorillaTranslate/Models/TrafficCamera.swift",
 "#{repo}/GorillaTranslate/Models/MeterData.swift"].each do |file|
  app.source_build_phase.add_file_reference(group.new_file(file))
end
%w[traffic_cameras.json camera_alert.wav].each do |file|
  app.resources_build_phase.add_file_reference(group.new_file("#{repo}/GorillaTranslate/Resources/#{file}"))
end
loc = group.new_variant_group('Localizable.strings')
%w[en zh-Hant zh-Hans ja].each { |lang| loc.new_file("#{repo}/GorillaTranslate/Resources/Localization/#{lang}.lproj/Localizable.strings").name = lang }
app.resources_build_phase.add_file_reference(loc)
tests.source_build_phase.add_file_reference(group.new_file("#{repo}/Tests/TrafficCameraUITests.swift"))
tests.add_dependency(app)
[app, tests].each do |target|
  target.build_configurations.each do |config|
    config.build_settings.merge!('SWIFT_VERSION' => '5.0', 'GENERATE_INFOPLIST_FILE' => 'YES',
      'CODE_SIGNING_ALLOWED' => 'NO', 'TARGETED_DEVICE_FAMILY' => '1,2',
      'PRODUCT_BUNDLE_IDENTIFIER' => "com.gorilla.#{target.name.downcase}")
  end
end
app.build_configurations.each do |config|
  config.build_settings.merge!('INFOPLIST_KEY_UIApplicationSceneManifest_Generation' => 'YES',
    'INFOPLIST_KEY_UILaunchScreen_Generation' => 'YES',
    'INFOPLIST_KEY_UISupportedInterfaceOrientations' => 'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight')
end
tests.build_configurations.each { |config| config.build_settings['TEST_TARGET_NAME'] = app.name }
project.save
scheme = Xcodeproj::XCScheme.new
[app, tests].each { |target| scheme.add_build_target(target) }
scheme.add_test_target(tests)
scheme.set_launch_target(app)
scheme.save_as(project.path, 'CameraChecks', true)
