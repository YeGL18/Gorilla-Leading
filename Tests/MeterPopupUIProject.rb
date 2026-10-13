require 'xcodeproj'
require 'fileutils'

repo = File.expand_path('..', __dir__)
root = '/private/tmp/GorillaMeterPopupUI'
FileUtils.mkdir_p(root)
views = File.read("#{repo}/GorillaTranslate/Views/ParkingMeterViews.swift")
popups = views[views.index('private enum MeterPopupStyle')...views.index("@MainActor\nenum MeterPayment")]
colors = views[views.index('extension MeterDisplayState')...views.index('final class MeterAnnotation:')]
manager = File.read("#{repo}/GorillaTranslate/Models/ParkingMeterManager.swift")
notice = manager[manager.index('struct MeterNotice:')...manager.index('@MainActor')]
policy = File.read("#{repo}/GorillaTranslate/Models/TimePhase.swift")
policy = policy[policy.index('enum GorillaColorGroup:')...policy.index('// MARK: - Time Phase Model')]
content = File.read("#{repo}/GorillaTranslate/ContentView.swift")
glass = content[content.index('enum GorillaGlassStyle {')...content.index('private struct GorillaCapsuleGlass:')]
fixture = <<~SWIFT
  import SwiftUI
  import MapKit
  #{policy}
  #{glass}
  enum GorillaActivityLocalization { static let sharedLanguageKey = "testLanguage" }
  @MainActor final class ParkingMeterManager: ObservableObject {
      @Published var statusRefreshing = false
      let vehicle = MeterVehicle.privateCar
      let lastStatusFetch: Date? = Date(timeIntervalSince1970: 1700000000)
      let statusErrorMessage: String? = nil
      func state(_ meter: ParkingMeter) -> MeterDisplayState { .vacant }
      func refreshStatus(force: Bool) async {}
  }
  #{colors}
  #{notice}
  #{popups}
  struct PopupFixture: View {
      @StateObject private var manager = ParkingMeterManager()
      @State private var actions = 0
      let arguments = ProcessInfo.processInfo.arguments
      let meter = ParkingMeter(id: "7802A", poleId: "7802", district: "九龍城", street: "牧愛街",
          streetKey: "test", latitude: 22.32, longitude: 114.18, bayType: .general,
          lpp: 120, operatingPeriod: "D", paymentUnit: 2, timeUnit: 15,
          englishStreet: "Shepherd Street")
      var region: MeterPopupRegion {
          if arguments.contains("--upper") { return .upperHalf }
          if arguments.contains("--left") { return .leftHalf }
          return .full
      }
      var body: some View {
          ZStack {
              Color(uiColor: .secondarySystemBackground).ignoresSafeArea()
              if arguments.contains("--notice") {
                  MeterNoticeOverlay(notice: MeterNotice(kind: arguments.contains("--stationary") ? .stationary : .nearby,
                      meter: meter, count: 12, destinationName: "University", expiresAt: Date().addingTimeInterval(30)),
                      onCancel: { actions += 1 }, onAction: { actions += 1 }, onPay: { actions += 1 }, region: region)
              } else {
                  MeterDetailOverlay(meter: meter, manager: manager, onClose: { actions += 1 },
                      onNavigate: { actions += 1 }, onPay: { actions += 1 }, region: region)
              }
          }
          .overlay(alignment: .top) { Text("Actions: \\(actions)").accessibilityIdentifier("actions") }
          .preferredColorScheme(arguments.contains("--dark") ? .dark : .light)
      }
  }
  @main struct MeterPopupCheckApp: App {
      init() {
          UserDefaults.standard.set(ProcessInfo.processInfo.arguments.contains("--glass-dark"), forKey: "capsuleDarkGlassEnabled")
          LanguageManager.refresh()
      }
      var body: some Scene { WindowGroup { PopupFixture().environment(\\.locale, LanguageManager.locale) } }
  }
SWIFT
File.write("#{root}/Fixture.swift", fixture)
project = Xcodeproj::Project.new("#{root}/MeterPopupChecks.xcodeproj")
app = project.new_target(:application, 'MeterPopupChecks', :ios, '26.0')
tests = project.new_target(:ui_test_bundle, 'MeterPopupUITests', :ios, '26.0')
app.source_build_phase.add_file_reference(project.main_group.new_file("#{root}/Fixture.swift"))
%w[Models/MeterData.swift Models/LanguageManager.swift].each do |file|
  app.source_build_phase.add_file_reference(project.main_group.new_file("#{repo}/GorillaTranslate/#{file}"))
end
tests.source_build_phase.add_file_reference(project.main_group.new_file("#{repo}/Tests/MeterPopupUITests.swift"))
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
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.gorilla.meter-popup-checks'
  config.build_settings['INFOPLIST_KEY_UIApplicationSceneManifest_Generation'] = 'YES'
  config.build_settings['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
  config.build_settings['INFOPLIST_KEY_UISupportedInterfaceOrientations'] = 'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight'
end
tests.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.gorilla.meter-popup-uitests'
  config.build_settings['TEST_TARGET_NAME'] = 'MeterPopupChecks'
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_build_target(tests)
scheme.add_test_target(tests)
scheme.set_launch_target(app)
scheme.save_as(project.path, 'MeterPopupChecks', true)
