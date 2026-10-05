require 'xcodeproj'
require 'fileutils'

repo = File.expand_path('..', __dir__)
root = '/private/tmp/GorillaFloorCaptureUI'
FileUtils.mkdir_p(root)
source = File.read("#{repo}/GorillaTranslate/ContentView.swift")
first = source.index('private struct ParkingStopConfirmationView:') or abort 'Missing stop confirmation'
last = source.index('struct ContentView:', first) or abort 'Missing picker boundary'
picker = source[first...last]
model = File.read("#{repo}/GorillaTranslate/Models/LocationManager.swift")
policy_start = model.index('struct ParkingStopConfirmation {') or abort 'Missing stop policy'
policy_end = model.index('struct ParkingAltitudeResult:', policy_start) or abort 'Missing policy boundary'
policy = model[policy_start...policy_end]
fixture = <<~SWIFT
  import SwiftUI
  enum ParkingFloorStore {
    static func formatFloor(_ floor: Int) -> String {
      floor == 0 ? "G" : floor < 0 ? "B\\(abs(floor))" : "\\(floor)"
    }
  }
  #{picker}
  #{policy}
  @main struct FloorCaptureCheckApp: App {
    var body: some Scene {
      WindowGroup {
        if ProcessInfo.processInfo.arguments.contains("--parking-stop") { ParkingStopFixture() }
        else { FloorFixture() }
      }
    }
  }
  struct FloorFixture: View {
    @State private var saved = -3
    @State private var userConfirmed = false
    @State private var confirmed = false
    var body: some View {
      VStack(spacing: 30) {
        Text("\\(saved)|\\(userConfirmed)|\\(confirmed)").accessibilityIdentifier("captureStatus")
        VStack {
          HStack { Text("Floor detection").bold(); Spacer(); Text("B3") }
          Color.blue.opacity(0.1).frame(height: 110)
            .overlay {
              Image(systemName: "waveform.path").font(.system(size: 60)).foregroundStyle(.blue).blur(radius: 4)
              FloorCaptureConfirmationView(initialFloor: -3, confirmed: confirmed,
                onChange: { saved = $0; userConfirmed = true },
                onConfirm: { userConfirmed = userConfirmed || $0; confirmed = true })
            }
        }
        .padding(12).frame(width: 320).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 28))
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(.systemGroupedBackground))
    }
  }
  struct ParkingStopFixture: View {
    @State private var policy = ParkingStopConfirmation()
    @State private var sampling = true
    @State private var sampleCount = 0
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
      VStack(spacing: 30) {
        Text(verbatim: "\\(sampling)|\\(sampleCount)").accessibilityIdentifier("samplingStatus")
        Color.blue.opacity(0.1).frame(width: 320, height: 110)
          .overlay {
            Image(systemName: "waveform.path").font(.system(size: 60))
              .blur(radius: policy.promptID != nil ? 4 : 0)
            if let id = policy.promptID {
              ParkingStopConfirmationView(
                onContinue: { policy.deferPrompt(at: Date()) },
                onConfirm: { sampling = false; policy.reset() })
                .id(id)
            }
          }
      }
      .onAppear { policy.update(stableStop: true, at: Date()) }
      .onReceive(tick) { date in
        guard sampling else { return }
        sampleCount += 1
        policy.update(stableStop: true, at: date)
      }
    }
  }
SWIFT
File.write("#{root}/FloorFixture.swift", fixture)
project = Xcodeproj::Project.new("#{root}/FloorChecks.xcodeproj")
app = project.new_target(:application, 'FloorCaptureChecks', :ios, '27.1')
tests = project.new_target(:ui_test_bundle, 'FloorCaptureUITests', :ios, '27.1')
sources = project.main_group.new_group('Sources')
app.source_build_phase.add_file_reference(sources.new_file("#{root}/FloorFixture.swift"))
tests.source_build_phase.add_file_reference(sources.new_file("#{repo}/Tests/FloorCaptureUITests.swift"))
tests.add_dependency(app)
[app, tests].each do |target|
  target.build_configurations.each do |config|
    config.build_settings['SWIFT_VERSION'] = '5.0'
    config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
    config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
  end
end
app.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.gorilla.floor-capture-checks'
  config.build_settings['INFOPLIST_KEY_UIApplicationSceneManifest_Generation'] = 'YES'
  config.build_settings['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
end
tests.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.gorilla.floor-capture-uitests'
  config.build_settings['TEST_TARGET_NAME'] = 'FloorCaptureChecks'
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_build_target(tests)
scheme.add_test_target(tests)
scheme.set_launch_target(app)
scheme.save_as(project.path, 'FloorChecks', true)
