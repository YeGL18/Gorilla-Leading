require 'fileutils'
require 'xcodeproj'

repo = File.expand_path('..', __dir__)
root = '/private/tmp/GorillaHomeMapSessionChecks'
FileUtils.mkdir_p(root)
map = File.read("#{repo}/GorillaTranslate/Views/MapView.swift")
first = map.index('struct HomeMapContext {') or abort 'Missing home map session'
last = map.index('struct MapView: UIViewRepresentable {', first) or abort 'Missing map boundary'
File.write("#{root}/HomeMapSession.swift", "import SwiftUI\nimport MapKit\n" + map[first...last])
project = Xcodeproj::Project.new("#{root}/HomeMapSessionChecks.xcodeproj")
app = project.new_target(:application, 'HomeMapSessionChecks', :ios, '18.0')
tests = project.new_target(:unit_test_bundle, 'HomeMapSessionTests', :ios, '18.0')
ui_tests = project.new_target(:ui_test_bundle, 'DuoSettingsMapUITests', :ios, '18.0')
group = project.main_group.new_group('Sources')
app.source_build_phase.add_file_reference(group.new_file("#{root}/HomeMapSession.swift"))
app.source_build_phase.add_file_reference(group.new_file("#{repo}/Tests/HomeMapSessionFixture.swift"))
tests.source_build_phase.add_file_reference(group.new_file("#{repo}/Tests/HomeMapSessionTests.swift"))
ui_tests.source_build_phase.add_file_reference(group.new_file("#{repo}/Tests/DuoSettingsMapUITests.swift"))
[tests, ui_tests].each { |t| t.add_dependency(app) }
[app, tests, ui_tests].each do |target|
  target.build_configurations.each do |config|
    config.build_settings.merge!('SWIFT_VERSION' => '5.0', 'GENERATE_INFOPLIST_FILE' => 'YES',
      'TARGETED_DEVICE_FAMILY' => '1,2', 'CODE_SIGNING_ALLOWED' => 'NO', 'ENABLE_TESTABILITY' => 'YES')
  end
end
app.build_configurations.each do |config|
  config.build_settings.merge!('PRODUCT_BUNDLE_IDENTIFIER' => 'com.gorilla.home-map-session-checks',
    'INFOPLIST_KEY_UIApplicationSceneManifest_Generation' => 'YES', 'INFOPLIST_KEY_UILaunchScreen_Generation' => 'YES')
end
tests.build_configurations.each do |config|
  config.build_settings.merge!('PRODUCT_BUNDLE_IDENTIFIER' => 'com.gorilla.home-map-session-tests',
    'TEST_HOST' => '$(BUILT_PRODUCTS_DIR)/HomeMapSessionChecks.app/HomeMapSessionChecks',
    'BUNDLE_LOADER' => '$(TEST_HOST)')
end
ui_tests.build_configurations.each do |config|
  config.build_settings.merge!('PRODUCT_BUNDLE_IDENTIFIER' => 'com.gorilla.duo-settings-map-tests',
    'TEST_TARGET_NAME' => 'HomeMapSessionChecks')
end
project.save
scheme = Xcodeproj::XCScheme.new
[app, tests, ui_tests].each { |target| scheme.add_build_target(target) }
[tests, ui_tests].each { |target| scheme.add_test_target(target) }
scheme.set_launch_target(app)
scheme.save_as(project.path, 'HomeMapSessionChecks', true)
