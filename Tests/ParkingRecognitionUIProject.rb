require 'xcodeproj'
require 'fileutils'
require 'json'

repo = File.expand_path('..', __dir__)
root = '/private/tmp/GorillaParkingRecognitionUI'
FileUtils.mkdir_p("#{root}/Assets.xcassets")
FileUtils.cp_r("#{repo}/GorillaTranslate/Assets.xcassets/AccentColor.colorset", "#{root}/Assets.xcassets")
colors = JSON.parse(File.read("#{root}/Assets.xcassets/AccentColor.colorset/Contents.json"))['colors']
dark = colors.find { |c| (c['appearances'] || []).any? { |a| a['value'] == 'dark' } }['color']['components']
expected = { 'red' => 0.2, 'green' => 0.5, 'blue' => 0.8, 'alpha' => 1.0 }
abort 'Keep the original blue accent; white belongs only to specific alerts' unless expected.all? { |key, value| dark[key].to_f == value }
alert_source = File.read("#{repo}/GorillaTranslate/Views/VLMActionPrompt.swift")
abort 'Parking information must keep its scoped white tint' unless alert_source.include?('alert.view.tintColor = dark ? .white :')
File.write("#{root}/Fixture.swift", <<~SWIFT)
  import SwiftUI
  @main struct ParkingRecognitionUIApp: App {
      var body: some Scene { WindowGroup { Fixture() } }
  }
  struct Fixture: View {
      @State private var showing = true
      @State private var action = ""
      private var dark: Bool { !ProcessInfo.processInfo.arguments.contains("--light") }
      var body: some View {
          ZStack {
              Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
              VStack {
                  Text(action).accessibilityIdentifier("result")
                  Button("Reopen") { showing = true }
                  Text("Accent").foregroundStyle(Color.accentColor)
              }
          }
          .modifier(ParkingRecognitionInfoAlert(
                      isPresented: $showing,
                      message: "車位：A123\\n區域：綠色\\n樓層：B2\\n識別邏輯：柱子清楚標示區域及樓層，大堂的 3 字不作樓層。",
                      onEdit: { action = "edit"; showing = false },
                      onClear: { action = "clear"; showing = false },
                      onConfirm: { action = "confirm"; showing = false }))
          .preferredColorScheme(dark ? .dark : .light)
      }
  }
SWIFT
project = Xcodeproj::Project.new("#{root}/ParkingRecognitionUI.xcodeproj")
app = project.new_target(:application, 'ParkingRecognitionUI', :ios, '18.0')
tests = project.new_target(:ui_test_bundle, 'ParkingRecognitionUITests', :ios, '18.0')
["#{root}/Fixture.swift", "#{repo}/GorillaTranslate/Views/VLMActionPrompt.swift"].each do |path|
  app.source_build_phase.add_file_reference(project.main_group.new_file(path))
end
app.resources_build_phase.add_file_reference(project.main_group.new_file("#{root}/Assets.xcassets"))
tests.source_build_phase.add_file_reference(project.main_group.new_file("#{repo}/Tests/ParkingRecognitionUITests.swift"))
tests.add_dependency(app)
[app, tests].each do |target|
  target.build_configurations.each do |config|
    config.build_settings['SWIFT_VERSION'] = '5.0'
    config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
    config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  end
end
app.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.gorilla.parking-recognition-ui'
  config.build_settings['INFOPLIST_KEY_UIApplicationSceneManifest_Generation'] = 'YES'
  config.build_settings['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
  config.build_settings['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = 'AccentColor'
  config.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = ''
end
tests.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.gorilla.parking-recognition-uitests'
  config.build_settings['TEST_TARGET_NAME'] = 'ParkingRecognitionUI'
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_build_target(tests)
scheme.add_test_target(tests)
scheme.set_launch_target(app)
scheme.save_as(project.path, 'ParkingRecognitionUI', true)
