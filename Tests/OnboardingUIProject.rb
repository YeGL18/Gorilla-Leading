require 'xcodeproj'
require 'fileutils'
repo = File.expand_path('..', __dir__)
root = '/private/tmp/GorillaOnboardingUI'
FileUtils.mkdir_p(root)
settings = File.read("#{repo}/GorillaTranslate/Views/SettingsView.swift")
about_start = settings.index("                Section {\n                    NavigationLink {\n                        GorillaPageView()") or abort 'Missing settings About section'
about_end = settings.index("\n            }\n            .scrollContentBackground", about_start) or abort 'Missing settings list boundary'
about_section = settings[about_start...about_end]
File.write("#{root}/Fixture.swift", <<~SWIFT)
  import SwiftUI
  import CoreLocation
  extension CLLocationCoordinate2D { var wgs84ToGCJ02: Self { self } }
  final class LocationManager: ObservableObject {
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    func startLocationServicesIfNeeded() {}
  }
  @main struct OnboardingCheckApp: App {
    @StateObject private var manager = LocationManager()
    init() {
      if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--parking-color=") }) {
        UserDefaults.standard.set(String(argument.dropFirst("--parking-color=".count)), forKey: "parkingTimerColorHex")
      }
    }
    var body: some Scene {
      WindowGroup {
        Group {
          if ProcessInfo.processInfo.arguments.contains("--settings-about") {
            NavigationStack { List { #{about_section} } }
          } else {
            GorillaOnboardingView(isReplay: true) {}
          }
        }.environmentObject(manager)
      }
    }
  }
SWIFT
project = Xcodeproj::Project.new("#{root}/OnboardingChecks.xcodeproj")
app = project.new_target(:application, 'OnboardingChecks', :ios, '26.0')
tests = project.new_target(:ui_test_bundle, 'OnboardingUITests', :ios, '26.0')
["#{root}/Fixture.swift", "#{repo}/GorillaTranslate/Views/GorillaOnboardingView.swift", "#{repo}/GorillaTranslate/Views/GorillaPageView.swift", "#{repo}/GorillaTranslate/Extensions/ColorExtension.swift", "#{repo}/GorillaTranslate/Models/TrafficCamera.swift"].each do |file|
  app.source_build_phase.add_file_reference(project.main_group.new_file(file))
end
app.resources_build_phase.add_file_reference(project.main_group.new_file("#{repo}/GorillaTranslate/Assets.xcassets"))
app.resources_build_phase.add_file_reference(project.main_group.new_file("#{repo}/GorillaTranslate/Resources/traffic_cameras.json"))
tests.source_build_phase.add_file_reference(project.main_group.new_file("#{repo}/Tests/OnboardingUITests.swift"))
tour_source = File.read("#{repo}/GorillaTranslate/Views/GorillaOnboardingView.swift")
motion_start = tour_source.index('struct LeadingJourneyMotion {') or abort 'Missing journey motion model'
motion_end = tour_source.index('private enum LeadingTourPage:', motion_start) or abort 'Missing tour page boundary'
File.write("#{root}/Motion.swift", "import Foundation\n" + tour_source[motion_start...motion_end])
tests.source_build_phase.add_file_reference(project.main_group.new_file("#{root}/Motion.swift"))
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
end
tests.build_configurations.each { |config| config.build_settings['TEST_TARGET_NAME'] = app.name }
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_build_target(tests)
scheme.add_test_target(tests)
scheme.set_launch_target(app)
scheme.save_as(project.path, app.name, true)
