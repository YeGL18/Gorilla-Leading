require 'fileutils'
require 'xcodeproj'

repo = File.expand_path('..', __dir__)
root = '/private/tmp/GorillaEnergyChecks'
FileUtils.mkdir_p(root)
map = File.read("#{repo}/GorillaTranslate/Views/MapView.swift")
first = map.index('final class MapPresentationContainer:') or abort 'Missing map container'
last = map.index('final class NonSelectableUserLocationView:', first) or abort 'Missing container boundary'
File.write("#{root}/MapPresentationContainer.swift", "import UIKit\nimport CoreImage\n" + map[first...last])
project = Xcodeproj::Project.new("#{root}/EnergyChecks.xcodeproj")
app = project.new_target(:application, 'GorillaEnergyChecks', :ios, '18.0')
tests = project.new_target(:unit_test_bundle, 'EnergyRuntimeTests', :ios, '18.0')
ui_tests = project.new_target(:ui_test_bundle, 'EnergyVisualTests', :ios, '18.0')
group = project.main_group.new_group('Sources')
%w[GorillaTranslate/Models/Destination.swift GorillaTranslate/Models/AnimationClock.swift
   GorillaTranslate/Models/TimePhase.swift GorillaTranslate/Models/WeatherService.swift
   GorillaTranslate/Views/TimeBasedOrbView.swift
   GorillaTranslate/Extensions/ColorExtension.swift
   Tests/EnergyRuntimeFixture.swift].each do |path|
  app.source_build_phase.add_file_reference(group.new_file("#{repo}/#{path}"))
end
app.source_build_phase.add_file_reference(group.new_file("#{root}/MapPresentationContainer.swift"))
tests.source_build_phase.add_file_reference(group.new_file("#{repo}/Tests/EnergyRuntimeTests.swift"))
ui_tests.source_build_phase.add_file_reference(group.new_file("#{repo}/Tests/EnergyVisualTests.swift"))
[tests, ui_tests].each { |t| t.add_dependency(app) }
[app, tests, ui_tests].each do |target|
  target.build_configurations.each do |config|
    config.build_settings.merge!('SWIFT_VERSION' => '5.0', 'GENERATE_INFOPLIST_FILE' => 'YES',
      'TARGETED_DEVICE_FAMILY' => '1,2', 'CODE_SIGNING_ALLOWED' => 'NO', 'ENABLE_TESTABILITY' => 'YES')
  end
end
app.build_configurations.each do |config|
  config.build_settings.merge!('PRODUCT_BUNDLE_IDENTIFIER' => 'com.gorilla.energy-checks',
    'INFOPLIST_KEY_UIApplicationSceneManifest_Generation' => 'YES', 'INFOPLIST_KEY_UILaunchScreen_Generation' => 'YES')
end
tests.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.gorilla.energy-runtime-tests'
  config.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/GorillaEnergyChecks.app/GorillaEnergyChecks'
  config.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
end
ui_tests.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.gorilla.energy-visual-tests'
  config.build_settings['TEST_TARGET_NAME'] = 'GorillaEnergyChecks'
end
project.save
scheme = Xcodeproj::XCScheme.new
[app, tests, ui_tests].each { |target| scheme.add_build_target(target) }
[tests, ui_tests].each { |target| scheme.add_test_target(target) }
scheme.set_launch_target(app)
scheme.save_as(project.path, 'EnergyChecks', true)
