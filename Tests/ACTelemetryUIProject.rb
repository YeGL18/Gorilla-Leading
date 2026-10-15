require 'xcodeproj'
require 'fileutils'
repo = File.expand_path('..', __dir__)
root = '/private/tmp/GorillaACUI'
FileUtils.mkdir_p(root)
policy = File.read("#{repo}/GorillaTranslate/Models/TimePhase.swift")
policy = policy[policy.index('enum GorillaColorGroup:')...policy.index('// MARK: - Time Phase Model')]
dots = File.read("#{repo}/GorillaTranslate/Views/DotMatrixView.swift")
dots = dots[dots.index('struct DotMatrixWebView:')..]
fixture = <<~SWIFT
  import SwiftUI
  import Network
  import MapKit
  import WebKit
  import Combine
  #{policy}
  #{dots}
  final class TimePhaseManager { func stop() {} }
  struct TimeBasedOrbView: View {
    let phaseManager: TimePhaseManager
    let clock: AnimationClock
    let orbEnabled: Bool
    let orbSizeMultiplier: CGFloat
    var body: some View { Color.clear }
  }
  struct ReadOnlyMapView: View {
    let camera: MKMapCamera?
    let mapStyleIndex: Int
    var body: some View { Color.clear }
  }
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
    @AppStorage("acAutoConnectEnabled") var enabled = false
    var body: some View {
      SpeedView(acTelemetry: telemetry, showMap: false, animationClock: clock,
                mapCamera: $camera, isDuoDevice: false, isDuoInnerDisplay: false,
                isDuoPartiallyOpen: false)
        .environmentObject(location)
        .preferredColorScheme(.dark)
        .overlay(alignment: .bottomTrailing) {
          Button(mock.enabled ? "Stop Mock" : "Start Mock") { mock.toggle() }.padding()
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
      UserDefaults.standard.set(false, forKey: "speedParallaxEnabled")
      UserDefaults.standard.set(false, forKey: "orbMasterEnabled")
    }
    var body: some Scene { WindowGroup { Fixture() } }
  }
SWIFT
File.write("#{root}/Fixture.swift", fixture)
project = Xcodeproj::Project.new("#{root}/ACChecks.xcodeproj")
app = project.new_target(:application, 'ACChecks', :ios, '26.0')
tests = project.new_target(:ui_test_bundle, 'ACUITests', :ios, '26.0')
app.source_build_phase.add_file_reference(project.main_group.new_file("#{root}/Fixture.swift"))
%w[Models/ACTelemetry.swift Views/ACDashboardView.swift Views/SpeedView.swift Models/NumberRoller.swift Models/AnimationClock.swift Views/AnimatedBackground.swift Extensions/ColorExtension.swift Shaders/MetaballEffect.metal].each do |file|
  app.source_build_phase.add_file_reference(project.main_group.new_file("#{repo}/GorillaTranslate/#{file}"))
end
tests.source_build_phase.add_file_reference(project.main_group.new_file("#{repo}/Tests/ACTelemetryUITests.swift"))
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
