require 'xcodeproj'
require 'fileutils'

repo = File.expand_path('..', __dir__)
root = '/private/tmp/GorillaSettingsSearchUI'
FileUtils.mkdir_p(root)
content = File.read("#{repo}/GorillaTranslate/ContentView.swift")
first = content.index('struct DestinationSearchMenuItems:') or abort 'Missing search menu'
last = content.index('struct ContentView:', first) or abort 'Missing search list boundary'
settings = File.read("#{repo}/GorillaTranslate/Views/SettingsView.swift")
sound_first = settings.index('private struct SoundSettingsSection:') or abort 'Missing sound settings'
sound_last = settings.index('// MARK: -', sound_first) or abort 'Missing sound section boundary'
fixture = <<~SWIFT
  import SwiftUI
  #{content[first...last]}
  #{settings[sound_first...sound_last]}
  struct SettingsSearchFixture: View {
    @State private var selected = "None"
    let items = (1...50).map {
      DestinationSearchMenuItems.Item(id: String($0), name: String(format: "Destination %02d", $0), symbol: "mappin.circle")
    }
    var body: some View {
      NavigationStack {
        VStack {
            Menu("Search Places") {
              Menu("My Destinations (50)") {
                DestinationSearchMenuItems(items: items, selectedID: selected) { selected = $0 }
              }
            }.buttonStyle(.borderless)
            Text(selected).accessibilityIdentifier("selectionResult")
          List { SoundSettingsSection() }
        }
        .navigationTitle("Settings")
      }
    }
  }
  @main struct SettingsSearchCheckApp: App {
    var body: some Scene { WindowGroup { SettingsSearchFixture() } }
  }
SWIFT
File.write("#{root}/Fixture.swift", fixture)
project = Xcodeproj::Project.new("#{root}/SettingsSearchChecks.xcodeproj")
app = project.new_target(:application, 'SettingsSearchChecks', :ios, '18.0')
tests = project.new_target(:ui_test_bundle, 'SettingsSearchUITests', :ios, '18.0')
app.source_build_phase.add_file_reference(project.main_group.new_file("#{root}/Fixture.swift"))
app.source_build_phase.add_file_reference(project.main_group.new_file("#{repo}/GorillaTranslate/Models/SFXPlayer.swift"))
tests.source_build_phase.add_file_reference(project.main_group.new_file("#{repo}/Tests/SettingsSearchUITests.swift"))
tests.add_dependency(app)
resources = project.main_group.new_variant_group('Localizable.strings')
%w[en zh-Hant zh-Hans ja].each do |locale|
  file = resources.new_file("#{repo}/GorillaTranslate/Resources/Localization/#{locale}.lproj/Localizable.strings")
  file.name = locale
end
app.resources_build_phase.add_file_reference(resources)
Dir.glob("#{repo}/GorillaTranslate/Resources/Audio/SFX/*.{mp3,caf}").each do |file|
  app.resources_build_phase.add_file_reference(project.main_group.new_file(file))
end
[app, tests].each do |target|
  target.build_configurations.each do |config|
    config.build_settings['SWIFT_VERSION'] = '5.0'
    config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
    config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
  end
end
app.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.gorilla.settings-search-checks'
  config.build_settings['INFOPLIST_KEY_UIApplicationSceneManifest_Generation'] = 'YES'
  config.build_settings['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
  config.build_settings['INFOPLIST_KEY_UISupportedInterfaceOrientations'] = 'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight'
end
tests.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.gorilla.settings-search-uitests'
  config.build_settings['TEST_TARGET_NAME'] = 'SettingsSearchChecks'
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_build_target(tests)
scheme.add_test_target(tests)
scheme.set_launch_target(app)
scheme.save_as(project.path, 'SettingsSearchChecks', true)
