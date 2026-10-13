require 'xcodeproj'
require 'fileutils'

repo = File.expand_path('..', __dir__)
root = '/private/tmp/GorillaVisitSettingsUI'
FileUtils.mkdir_p(root)
source = File.read("#{repo}/GorillaTranslate/Views/SettingsView.swift")
first = source.index('struct VisitRecordingSettingsView:') or abort 'Missing visit preferences'
last = source.index('struct VisitRecordsTestView:', first) or abort 'Missing view boundary'
fixture = <<~SWIFT
  import SwiftUI
  #{source[first...last]}
  @main struct CheckApp: App {
    init() {
      for key in ["visitMinimumNewMinutes", "visitMinimumActiveMinutes", "visitActivateMinutes",
                  "visitMatchRadiusMeters", "visitMergeConsecutive", "visitMergeMinutes", "visitDeactivateDays"] {
        UserDefaults.standard.removeObject(forKey: key)
      }
    }
    var body: some Scene { WindowGroup { NavigationStack { VisitRecordingSettingsView() } } }
  }
SWIFT
File.write("#{root}/Fixture.swift", fixture)
project = Xcodeproj::Project.new("#{root}/VisitSettingsChecks.xcodeproj")
app = project.new_target(:application, 'VisitSettingsChecks', :ios, '26.0')
tests = project.new_target(:ui_test_bundle, 'VisitSettingsUITests', :ios, '26.0')
app.source_build_phase.add_file_reference(project.main_group.new_file("#{root}/Fixture.swift"))
tests.source_build_phase.add_file_reference(project.main_group.new_file("#{repo}/Tests/VisitSettingsUITests.swift"))
localization = project.main_group.new_variant_group('Localizable.strings')
%w[en zh-Hant zh-Hans ja].each do |language|
  ref = localization.new_file("#{repo}/GorillaTranslate/Resources/Localization/#{language}.lproj/Localizable.strings")
  ref.name = language
end
app.resources_build_phase.add_file_reference(localization)
project.root_object.known_regions = %w[en zh-Hant zh-Hans ja]
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
