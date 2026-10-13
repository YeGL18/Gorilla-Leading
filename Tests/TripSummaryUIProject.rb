require 'xcodeproj'
require 'fileutils'
repo = File.expand_path('..', __dir__)
root = '/private/tmp/GorillaTripSummaryUI'
FileUtils.mkdir_p(root)
source = File.read("#{repo}/GorillaTranslate/Views/SettingsView.swift")
first = source.index('private struct TripSegmentItem:') or abort 'Missing trip items'
last = source.index('struct TimeOrbAnimationTestView:', first) or abort 'Missing layout boundary'
fixture = <<~SWIFT
  import SwiftUI
  #{source[first...last]}
  struct Fixture: View {
    var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          ForEach([220.0, 320.0, 340.0], id: \\.self) { width in
            Text("Width \\(Int(width))")
            TripSegmentSummary(items: [
              TripSegmentItem(icon: "car.fill", text: "32min"),
              TripSegmentItem(icon: "figure.walk", text: "14min"),
              TripSegmentItem(icon: "ellipsis", text: "Unclassified · 2min"),
              TripSegmentItem(icon: "car.fill", text: "10min")
            ]).frame(width: min(width, 340), alignment: .leading)
              .padding(12).background(.white)
          }
        }.padding(16)
      }.background(Color.gray.opacity(0.15))
    }
  }
  @main struct CheckApp: App { var body: some Scene { WindowGroup { Fixture() } } }
SWIFT
File.write("#{root}/Fixture.swift", fixture)
project = Xcodeproj::Project.new("#{root}/TripSummaryChecks.xcodeproj")
app = project.new_target(:application, 'TripSummaryChecks', :ios, '26.0')
tests = project.new_target(:ui_test_bundle, 'TripSummaryUITests', :ios, '26.0')
app.source_build_phase.add_file_reference(project.main_group.new_file("#{root}/Fixture.swift"))
tests.source_build_phase.add_file_reference(project.main_group.new_file("#{repo}/Tests/TripSummaryUITests.swift"))
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
end
tests.build_configurations.each { |config| config.build_settings['TEST_TARGET_NAME'] = app.name }
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_build_target(tests)
scheme.add_test_target(tests)
scheme.set_launch_target(app)
scheme.save_as(project.path, app.name, true)
