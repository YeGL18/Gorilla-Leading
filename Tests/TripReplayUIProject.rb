require 'xcodeproj'
require 'fileutils'
repo = File.expand_path('..', __dir__)
root = '/private/tmp/GorillaReplayUI'
FileUtils.mkdir_p(root)
fixture = <<~SWIFT
  import SwiftUI
  import Combine
  import CoreLocation
  final class GForceParallaxMotion: ObservableObject {
    static let shared = GForceParallaxMotion()
    @Published var reading: SpeedGForce?
    func start(consumer: String = "speed") {}
    func stop(consumer: String = "speed") {}
    func setScreenRotation(_ angle: Double) {}
  }
  @MainActor enum ReplayFixture {
    static let defaults = UserDefaults(suiteName: "com.gorilla.replay-ui-fixture")!
    static let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("replay-fixture.json")
    static func store() -> TripReplayStore {
      if !ProcessInfo.processInfo.arguments.contains("--preserve") {
        defaults.removePersistentDomain(forName: "com.gorilla.replay-ui-fixture")
        try? FileManager.default.removeItem(at: url)
        UserDefaults.standard.set("kmh", forKey: SpeedUnit.preferenceKey)
        if !ProcessInfo.processInfo.arguments.contains("--empty") {
          let start = Calendar.current.startOfDay(for: .now).addingTimeInterval(60)
          let points: [TripReplayPoint] = (0...600).compactMap { index in
            if (180..<210).contains(index) { return nil }
            let t = Double(index)
            let altitude: Double? = (300..<340).contains(index) ? nil : 20 + 40 * sin(t / 600 * .pi)
            return TripReplayPoint(time: start.addingTimeInterval(t), latitude: 22.425 + 0.002 * sin(t / 140),
              longitude: 114.205 + t * 0.00003, accuracy: 5, speedKmh: (400..<410).contains(index) ? nil : 50 + 30 * sin(t / 100),
              altitude: altitude, verticalAccuracy: altitude == nil ? nil : 5,
              lateralG: 0.1, longitudinalG: 0.05, breakBefore: index == 210, driving: true)
          }
          let events = [(10.0, SpeedDrivingAction.accelerating), (30, .left), (80, .braking), (150, .right)].map { offset, action in
            TripReplayEvent(id: UUID(), start: start.addingTimeInterval(offset), end: start.addingTimeInterval(offset + 5),
              action: action, peakG: 0.24, score: 90)
          }
          let trip = TripReplay(id: UUID(), points: points, events: events, originName: "Home", destinationName: "Sierra Sea", finished: true)
          var trips = [trip]
          if ProcessInfo.processInfo.arguments.contains("--multi-day") {
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: start)!
            for index in 0..<3 {
              let time = yesterday.addingTimeInterval(Double(index) * 3600)
              let samples = [0.0, 10].map { offset in
                TripReplayPoint(time: time.addingTimeInterval(offset), latitude: 22.425,
                  longitude: 114.205 + offset * 0.00003, accuracy: 5, speedKmh: 36)
              }
              trips.append(TripReplay(id: UUID(), points: samples, originName: "Home",
                destinationName: "Yesterday " + String(index + 1), finished: true))
            }
          }
          defaults.set(try! JSONEncoder().encode(TripReplayArchive(trips: trips)), forKey: TripReplayStore.storageKey)
        }
      }
      return TripReplayStore(defaults: defaults, storageURL: url)
    }
  }
  struct ActionGateFixture: View {
    @StateObject var telemetry = ACTelemetry()
    @StateObject var motion = GForceParallaxMotion.shared
    @State var driving = false
    let tick = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    var body: some View {
      VStack {
        Button("Toggle Driving") { driving.toggle() }
        SpeedInstrumentCards(motion: motion, telemetry: telemetry, partiallyOpen: false,
          foreground: .white, accent: .orange, source: "GPS", drivingState: driving) { _ in Text("0") }
      }
      .preferredColorScheme(.dark)
      .onReceive(tick) { _ in motion.reading = SpeedGForce(lateral: 0, longitudinal: 0.4) }
    }
  }
  struct VLMFixture: View {
    @State var show = false
    @State var result = ""
    var body: some View {
      VStack {
        Button("Show VLM") { show = true }
        Text(result)
        Text("Unchanged Pink").foregroundStyle(.pink)
      }
      .modifier(VLMActionPrompt(isPresented: $show, shortcutName: "Gorilla", onReady: {
        result = "Ready called"
      }, onCancel: { result = "Cancel called" }))
      .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--dark") ? .dark : .light)
    }
  }
  struct LibrarySheetFixture: View {
    @ObservedObject var store: TripReplayStore
    @State var show = false
    var body: some View {
      Color.gray.onAppear { show = true }
        .sheet(isPresented: $show) {
          NavigationStack {
            TripReplayLibraryView(store: store, onClose: { show = false })
          }
        }
    }
  }
  @main struct ReplayChecksApp: App {
    @StateObject var store = ReplayFixture.store()
    var body: some Scene {
      WindowGroup {
        Group {
          if ProcessInfo.processInfo.arguments.contains("--action-gate") { ActionGateFixture() }
          else if ProcessInfo.processInfo.arguments.contains("--vlm-prompt") { VLMFixture() }
          else if ProcessInfo.processInfo.arguments.contains("--sheet-library") { LibrarySheetFixture(store: store) }
          else {
            NavigationStack { TripReplayLibraryView(store: store) }
              .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--dark") ? .dark : .light)
          }
        }.background(AppHapticObserver().allowsHitTesting(false))
      }
    }
  }
SWIFT
palette = File.read("#{repo}/GorillaTranslate/Models/TimePhase.swift").split('// MARK: - Time Phase Model').first
fixture = palette + fixture
File.write("#{root}/Fixture.swift", fixture)
project = Xcodeproj::Project.new("#{root}/ReplayChecks.xcodeproj")
app = project.new_target(:application, 'ReplayChecks', :ios, '26.0')
tests = project.new_target(:ui_test_bundle, 'ReplayUITests', :ios, '26.0')
app.source_build_phase.add_file_reference(project.main_group.new_file("#{root}/Fixture.swift"))
%w[Models/SpeedGForce.swift Models/TripReplay.swift Models/TripReplayStore.swift Views/TripReplayView.swift].each do |file|
  app.source_build_phase.add_file_reference(project.main_group.new_file("#{repo}/GorillaTranslate/#{file}"))
end
app.source_build_phase.add_file_reference(project.main_group.new_file("#{repo}/Shared/SpeedUnit.swift"))
app.source_build_phase.add_file_reference(project.main_group.new_file("#{repo}/GorillaTranslate/Extensions/ColorExtension.swift"))
%w[Models/ACTelemetry.swift Views/SpeedInstrumentCards.swift Extensions/AppHaptics.swift Views/VLMActionPrompt.swift].each do |file|
  app.source_build_phase.add_file_reference(project.main_group.new_file("#{repo}/GorillaTranslate/#{file}"))
end
tests.source_build_phase.add_file_reference(project.main_group.new_file("#{repo}/GorillaTranslate/Extensions/ColorExtension.swift"))
tests.source_build_phase.add_file_reference(project.main_group.new_file("#{repo}/GorillaTranslate/Models/ParkingReminderPolicy.swift"))
tests.source_build_phase.add_file_reference(project.main_group.new_file("#{repo}/GorillaTranslate/Extensions/AppHaptics.swift"))
tests.source_build_phase.add_file_reference(project.main_group.new_file("#{repo}/Tests/TripReplayUITests.swift"))
%w[Models/SpeedGForce.swift Models/TripReplay.swift Models/TripReplayStore.swift].each do |file|
  tests.source_build_phase.add_file_reference(project.main_group.new_file("#{repo}/GorillaTranslate/#{file}"))
end
stub = <<~SWIFT
  import Foundation
  import Combine
  final class GForceParallaxMotion: ObservableObject {
    static let shared = GForceParallaxMotion()
    @Published var reading: SpeedGForce?
    func start(consumer: String = "speed") {}
    func stop(consumer: String = "speed") {}
    func setScreenRotation(_ angle: Double) {}
  }
SWIFT
File.write("#{root}/TestMotionStub.swift", stub)
tests.source_build_phase.add_file_reference(project.main_group.new_file("#{root}/TestMotionStub.swift"))
group = project.main_group.new_variant_group('Localizable.strings')
%w[en zh-Hant zh-Hans ja].each do |locale|
  ref = group.new_file("#{repo}/GorillaTranslate/Resources/Localization/#{locale}.lproj/Localizable.strings")
  ref.name = locale
end
app.resources_build_phase.add_file_reference(group)
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
