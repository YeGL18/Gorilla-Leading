require 'fileutils'
require 'xcodeproj'
repo = File.expand_path('..', __dir__)
root = '/private/tmp/GorillaSpeechChecks'
FileUtils.mkdir_p(root)
source = File.read("#{repo}/GorillaTranslate/Models/TrafficCamera.swift")
# Compile the production speech policy, audio pipeline and native settings; omit unrelated map rendering.
File.write("#{root}/CameraSpeech.swift", source[0...source.index('final class TrafficCameraAnnotation:')] +
  source[source.index('struct TrafficCameraSettingsView:')..])
File.write("#{root}/Fixture.swift", <<~SWIFT)
  import SwiftUI
  enum GorillaActivityLocalization { static let sharedLanguageKey = "testLanguage" }
  enum AirportDropOffCatalog { struct Zone {} }
  @main struct SpeechCheckApp: App {
    init() {
      UserDefaults.standard.set(true, forKey: "trafficCameraEnabled")
      UserDefaults.standard.set(true, forKey: "trafficCameraSound")
      UserDefaults.standard.set("full", forKey: CameraSpeechFormat.preferenceKey)
      UserDefaults.standard.set("app", forKey: CameraSpeechLanguage.preferenceKey)
      LanguageManager.refresh()
    }
    var body: some Scene { WindowGroup {
      NavigationStack { TrafficCameraSettingsView() }
        .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--dark") ? .dark : .light)
    } }
  }
SWIFT
project = Xcodeproj::Project.new("#{root}/SpeechChecks.xcodeproj")
app = project.new_target(:application, 'CameraSpeechChecks', :ios, '26.0')
ui = project.new_target(:ui_test_bundle, 'CameraSpeechUITests', :ios, '26.0')
unit = project.new_target(:unit_test_bundle, 'CameraSpeechRuntimeTests', :ios, '26.0')
group = project.main_group
["#{root}/Fixture.swift", "#{root}/CameraSpeech.swift", "#{repo}/GorillaTranslate/Models/LanguageManager.swift"].each do |path|
  app.source_build_phase.add_file_reference(group.new_file(path))
end
app.resources_build_phase.add_file_reference(group.new_file("#{repo}/GorillaTranslate/Resources/camera_alert.wav"))
loc = group.new_variant_group('Localizable.strings')
Dir.glob("#{repo}/GorillaTranslate/Resources/Localization/*.lproj").map { |path| File.basename(path, '.lproj') }.each { |lang| loc.new_file("#{repo}/GorillaTranslate/Resources/Localization/#{lang}.lproj/Localizable.strings").name = lang }
app.resources_build_phase.add_file_reference(loc)
require 'json'
require 'open3'
expectations = Dir.glob("#{repo}/GorillaTranslate/Resources/Localization/*.lproj").map do |path|
  output, status = Open3.capture2('plutil', '-convert', 'json', '-o', '-', "#{path}/Localizable.strings")
  abort 'Invalid localization table' unless status.success?
  values = JSON.parse(output)
  { 'language' => File.basename(path, '.lproj'), 'title' => values.fetch('交通相機'), 'automatic' => values.fetch('自動聲線') }
end
File.write("#{root}/LanguageExpectations.json", JSON.generate(expectations))
ui.resources_build_phase.add_file_reference(group.new_file("#{root}/LanguageExpectations.json"))
ui.source_build_phase.add_file_reference(group.new_file("#{repo}/Tests/CameraSpeechUITests.swift"))
unit.source_build_phase.add_file_reference(group.new_file("#{repo}/Tests/CameraSpeechRuntimeTests.swift"))
[ui, unit].each { |t| t.add_dependency(app) }
[app, ui, unit].each do |target|
  target.build_configurations.each do |config|
    config.build_settings.merge!('SWIFT_VERSION' => '5.0', 'GENERATE_INFOPLIST_FILE' => 'YES',
      'CODE_SIGNING_ALLOWED' => 'NO', 'ENABLE_TESTABILITY' => 'YES', 'TARGETED_DEVICE_FAMILY' => '1,2',
      'PRODUCT_BUNDLE_IDENTIFIER' => "com.gorilla.#{target.name.downcase}")
  end
end
app.build_configurations.each do |config|
  config.build_settings.merge!('INFOPLIST_KEY_UIApplicationSceneManifest_Generation' => 'YES',
    'INFOPLIST_KEY_UILaunchScreen_Generation' => 'YES')
end
ui.build_configurations.each { |c| c.build_settings['TEST_TARGET_NAME'] = app.name }
unit.build_configurations.each do |c|
  c.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/CameraSpeechChecks.app/CameraSpeechChecks'
  c.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
end
project.save
scheme = Xcodeproj::XCScheme.new
[app, ui, unit].each { |t| scheme.add_build_target(t) }
[ui, unit].each { |t| scheme.add_test_target(t) }
scheme.set_launch_target(app)
scheme.save_as(project.path, 'SpeechChecks', true)
