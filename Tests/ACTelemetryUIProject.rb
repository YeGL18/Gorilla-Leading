require 'xcodeproj'
require 'fileutils'
repo = File.expand_path('..', __dir__)
root = '/private/tmp/GorillaACUI'
FileUtils.mkdir_p(root)
policy = File.read("#{repo}/GorillaTranslate/Models/TimePhase.swift")
policy = policy[policy.index('enum GorillaColorGroup:')...policy.index('// MARK: - Time Phase Model')]
dots = File.read("#{repo}/GorillaTranslate/Views/DotMatrixView.swift")
dots = dots[dots.index('struct DotMatrixWebView:')..]
map_source = File.read("#{repo}/GorillaTranslate/Views/MapView.swift")
read_only_map = map_source[map_source.index('struct ReadOnlyMapView:')..]
home_source = File.read("#{repo}/GorillaTranslate/ContentView.swift")
glass_policy = home_source[home_source.index('enum GorillaGlassStyle')...home_source.index('private struct GorillaCapsuleGlass')]
control_appearance = home_source[home_source.index('struct GorillaMapControlAppearance')...home_source.index('private struct GorillaTabBarStyle')]
prediction_start = home_source.index("    @ViewBuilder\n    private func tripConfirmCard") or abort 'Missing prediction card'
prediction_card = home_source[prediction_start...home_source.index('    // MARK: - Floor Confirmation Card')]
fixture = <<~SWIFT
  import SwiftUI
  import Network
  import MapKit
  import WebKit
  import Combine
  #{policy}
  #{glass_policy}
  #{control_appearance}
  #{dots}
  struct PredictedPlace { let key: String; let displayName: String }
  struct PendingTripPrediction {
    let predicted = PredictedPlace(key: "sea", displayName: "Sierra Sea")
    let twoStepAhead: PredictedPlace? = nil
    let confidence = 0.85
    let totalSamples = 5
  }
  final class TripPredictor {
    static let shared = TripPredictor()
    func applyUserFeedback(prediction: PendingTripPrediction, actualNextPlaceKey: String?, confirmed: Bool) {}
    func postponeDeparturePrediction() {}
  }
  final class DestinationManager {
    static let shared = DestinationManager()
    func applyAutoPrediction(_ prediction: PendingTripPrediction) -> Bool { true }
  }
  struct PredictionFixture: View {
    @State var showingTripConfirm = true
    @State var tripConfirmPrediction: PendingTripPrediction?
    let tripPredictor = TripPredictor.shared
    var body: some View {
      GeometryReader { geo in
        tripConfirmCard(prediction: PendingTripPrediction())
          .frame(maxWidth: min(560, geo.size.width - 44))
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }.background(Color.gray.opacity(0.2))
    }
    #{prediction_card}
  }
  final class TimePhaseManager { func stop() {} }
  struct TimeBasedOrbView: View {
    let phaseManager: TimePhaseManager
    let clock: AnimationClock
    let orbEnabled: Bool
    let orbSizeMultiplier: CGFloat
    var body: some View { Color.clear }
  }
  // Use the production representable; only the unrelated gesture/camera-lock
  // subclass is replaced, exposing its actual MapKit configuration for assertions.
  final class NonAdjustingMapView: MKMapView {
    var allowCameraChange = false
    override var preferredConfiguration: MKMapConfiguration {
      didSet { accessibilityValue = preferredConfiguration is MKHybridMapConfiguration ? "satellite" : "standard" }
    }
    override init(frame: CGRect) {
      super.init(frame: frame)
      isAccessibilityElement = true
      accessibilityIdentifier = "fixtureSpeedMap"
      accessibilityValue = "standard"
    }
    required init?(coder: NSCoder) { fatalError() }
  }
  #{read_only_map}
  final class SFXPlayer: ObservableObject { func playAccelerationBurst() {} }
  final class LocationManager: ObservableObject {
    @Published var speed = 42.0
    @Published var smoothedSpeed = 42.0
    @Published var lastLocation: CLLocation? = CLLocation(latitude: 22.3, longitude: 114.1)
    var isGPSLost = false
    var mapReferenceLocation: CLLocation? { lastLocation }
    func predictedSpeed() -> Double { speed }
  }
  @MainActor final class MockAC {
    var listener: NWListener?
    var connections: [NWConnection] = []
    var timer: Timer?
    var enabled = false
    var startedAt = 0.0
    func toggle() {
      enabled.toggle()
      if enabled { start() }
      else {
        timer?.invalidate(); timer = nil
        listener?.cancel(); listener = nil
        connections.forEach { $0.cancel() }; connections = []
      }
    }
    func start() {
      startedAt = ProcessInfo.processInfo.systemUptime
      listener = try! NWListener(using: .udp, on: 9996)
      listener?.newConnectionHandler = { [weak self] connection in
        Task { @MainActor in
          self?.connections.append(connection)
          connection.start(queue: .main)
          self?.receive(connection)
        }
      }
      listener?.start(queue: .main)
      timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
        Task { @MainActor in
          guard let self, self.enabled else { return }
          for connection in self.connections {
            connection.send(content: self.carPacket(), completion: .contentProcessed { _ in })
          }
        }
      }
    }
    func receive(_ connection: NWConnection) {
      connection.receiveMessage { [weak self] data, _, _, _ in
        Task { @MainActor in
          guard let self else { return }
          if let data, data.count == 12, ACPacket.integer(data, 8) == 0 {
            connection.send(content: self.namesPacket(), completion: .contentProcessed { _ in })
          }
          self.receive(connection)
        }
      }
    }
    func put(_ value: UInt32, _ offset: Int, _ data: inout Data) {
      for i in 0..<4 { data[offset+i] = UInt8(truncatingIfNeeded: value >> (i*8)) }
    }
    func carPacket() -> Data {
      var data = Data(repeating: 0, count: 328)
      data[0] = 97
      put(328, 4, &data); put(Float(123).bitPattern, 8, &data)
      put(Float(6500).bitPattern, 68, &data); put(4, 76, &data)
      put(Float(0.65).bitPattern, 56, &data); put(Float(0.2).bitPattern, 60, &data)
      var force = SpeedGForce(lateral: -0.29, longitudinal: 0.4)
      if ProcessInfo.processInfo.arguments.contains("--recent-peak-trace") {
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        if elapsed < 2 { force = SpeedGForce(lateral: 0.3, longitudinal: 0.4) }
        else if elapsed < 4 { force = SpeedGForce(lateral: -0.2, longitudinal: 0) }
        else { force = SpeedGForce(lateral: 0.01, longitudinal: 0) }
      }
      if ProcessInfo.processInfo.arguments.contains("--trail-trace") {
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        force = SpeedGForce(lateral: 0.7 * cos(elapsed * 2), longitudinal: 0.7 * sin(elapsed * 2))
      }
      if ProcessInfo.processInfo.arguments.contains("--action-trace") {
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        if elapsed < 5 { force = SpeedGForce(lateral: 0, longitudinal: 0.22) }
        else if elapsed >= 10 && elapsed < 15 { force = SpeedGForce(lateral: 0, longitudinal: -0.3) }
        else if elapsed >= 20 && elapsed < 25 { force = SpeedGForce(lateral: -0.26, longitudinal: -0.05) }
        else { force = SpeedGForce(lateral: 0, longitudinal: 0) }
      }
      put(Float(force.lateral).bitPattern, 32, &data); put(Float(force.longitudinal).bitPattern, 36, &data)
      put(83456, 40, &data); put(84000, 44, &data); put(82000, 48, &data); put(2, 52, &data)
      return data
    }
    func namesPacket() -> Data {
      var data = Data(repeating: 0, count: 408)
      put(4242, 200, &data); put(1, 204, &data)
      for (text, offset) in [("BMW M3 E30", 0), ("Monza", 208), ("GP", 308)] {
        let bytes = text.data(using: .utf16LittleEndian)!
        data.replaceSubrange(offset..<(offset+bytes.count), with: bytes)
      }
      return data
    }
  }
  struct Fixture: View {
    @StateObject var telemetry = ACTelemetry()
    @State var mock = MockAC()
    @StateObject var location = LocationManager()
    @State var clock = AnimationClock()
    @State var camera: MKMapCamera?
    @State var mapMode = 0
    @State var referenceVisible = ProcessInfo.processInfo.arguments.contains("--reference")
    @State var showUnits = false
    @AppStorage("acAutoConnectEnabled") var enabled = false
    var body: some View {
      SpeedView(acTelemetry: telemetry, showMap: mapMode != 0, showSatellite: mapMode == 2,
                cycleMapPresentation: { mapMode = (mapMode + 1) % 3 }, animationClock: clock,
                mapCamera: $camera, isDuoDevice: ProcessInfo.processInfo.arguments.contains("--duo"),
                isDuoInnerDisplay: ProcessInfo.processInfo.arguments.contains("--duo"),
                isDuoPartiallyOpen: ProcessInfo.processInfo.arguments.contains("--half"))
        .environmentObject(location)
        .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--light") ? .light : .dark)
        .overlay(alignment: .bottomTrailing) {
          Button(mock.enabled ? "Stop Mock" : "Start Mock") { mock.toggle() }.padding()
        }
        .overlay(alignment: .topLeading) {
          if ProcessInfo.processInfo.arguments.contains("--units") {
            Button("Units") { showUnits = true }.padding()
          }
        }
        .sheet(isPresented: $showUnits) {
          NavigationStack {
            Form { SpeedUnitPicker() }
              .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                  Button("Done") { showUnits = false }.accessibilityIdentifier("closeUnitSettings")
                }
              }
          }
        }
        .overlay(alignment: .topTrailing) {
          if referenceVisible {
            Button { referenceVisible = false } label: {
              Image(systemName: "map").font(.system(size: 20, weight: .medium)).frame(width: 44, height: 44)
            }
            .buttonStyle(.glass).modifier(GorillaMapControlAppearance())
            .accessibilityIdentifier("homeControlReference").padding()
          }
        }
        .onChange(of: enabled) { _, value in
          if value { telemetry.connect(host: "127.0.0.1") }
          else { telemetry.disconnect() }
        }
    }
  }
  @main struct CheckApp: App {
    init() {
      UserDefaults.standard.set(false, forKey: "acAutoConnectEnabled")
      UserDefaults.standard.set("127.0.0.1", forKey: "acComputerHost")
      UserDefaults.standard.set(false, forKey: "kalmanSmoothingEnabled")
      UserDefaults.standard.set(ProcessInfo.processInfo.arguments.contains("--gforce"), forKey: "speedParallaxEnabled")
      UserDefaults.standard.set("gforce", forKey: "parallaxMode")
      UserDefaults.standard.set(false, forKey: "orbMasterEnabled")
      UserDefaults.standard.set(!ProcessInfo.processInfo.arguments.contains("--transparent"), forKey: "capsuleDarkGlassEnabled")
      if !ProcessInfo.processInfo.arguments.contains("--preserve-units") {
        UserDefaults.standard.set("kmh", forKey: SpeedUnit.preferenceKey)
      }
      UserDefaults.standard.set(ProcessInfo.processInfo.arguments.contains("--rolling"), forKey: "kalmanSmoothingEnabled")
    }
    var body: some Scene {
      WindowGroup {
        if ProcessInfo.processInfo.arguments.contains("--prediction") { PredictionFixture() }
        else { Fixture() }
      }
    }
  }
SWIFT
File.write("#{root}/Fixture.swift", fixture)
project = Xcodeproj::Project.new("#{root}/ACChecks.xcodeproj")
app = project.new_target(:application, 'ACChecks', :ios, '26.0')
tests = project.new_target(:ui_test_bundle, 'ACUITests', :ios, '26.0')
app.source_build_phase.add_file_reference(project.main_group.new_file("#{root}/Fixture.swift"))
app.source_build_phase.add_file_reference(project.main_group.new_file("#{repo}/Shared/SpeedUnit.swift"))
%w[Models/ACTelemetry.swift Models/SpeedGForce.swift Views/SpeedInstrumentCards.swift Views/ACDashboardView.swift Views/SpeedView.swift Models/NumberRoller.swift Models/AnimationClock.swift Views/AnimatedBackground.swift Extensions/ColorExtension.swift Shaders/MetaballEffect.metal].each do |file|
  app.source_build_phase.add_file_reference(project.main_group.new_file("#{repo}/GorillaTranslate/#{file}"))
end
tests.source_build_phase.add_file_reference(project.main_group.new_file("#{repo}/Tests/ACTelemetryUITests.swift"))
%w[SpeedUnit.swift GorillaActivityAttributes.swift].each do |file|
  tests.source_build_phase.add_file_reference(project.main_group.new_file("#{repo}/Shared/#{file}"))
end
tests.add_dependency(app)
[app, tests].each do |target|
  target.build_configurations.each do |config|
    config.build_settings['SWIFT_VERSION'] = '5.0'
    config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
    config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = "com.gorilla.#{target.name.downcase}"
  end
end
app.build_configurations.each do |config|
  config.build_settings['INFOPLIST_KEY_UIApplicationSceneManifest_Generation'] = 'YES'
  config.build_settings['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
  config.build_settings['INFOPLIST_KEY_UISupportedInterfaceOrientations'] = 'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight'
  config.build_settings['INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone'] = 'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight'
  config.build_settings['INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad'] = 'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight'
end
tests.build_configurations.each { |config| config.build_settings['TEST_TARGET_NAME'] = app.name }
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_build_target(tests)
scheme.add_test_target(tests)
scheme.set_launch_target(app)
scheme.save_as(project.path, app.name, true)
