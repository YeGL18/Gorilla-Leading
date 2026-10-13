require 'xcodeproj'

# Generate a disposable simulator UI-test project without changing the app project.
repo = File.expand_path('..', __dir__)
root = ARGV.fetch(0, '/private/tmp/GorillaGestureTests')
Dir.mkdir(root) unless Dir.exist?(root)
project = Xcodeproj::Project.new("#{root}/GestureChecks.xcodeproj")
app = project.new_target(:application, 'GorillaMapChecks', :ios, '18.0')
tests = project.new_target(:ui_test_bundle, 'MapGestureUITests', :ios, '18.0')
sources = project.main_group.new_group('Sources')
['GorillaTranslate/Views/MapInteraction.swift', 'GorillaTranslate/Models/MapCameraMotion.swift', 'Tests/MapInteractionChecks.swift'].each do |path|
  app.source_build_phase.add_file_reference(sources.new_file("#{repo}/#{path}"))
end
tests.source_build_phase.add_file_reference(sources.new_file("#{repo}/Tests/MapGestureUITests.swift"))
tests.add_dependency(app)
[app, tests].each do |target|
  target.build_configurations.each do |config|
    config.build_settings['SWIFT_VERSION'] = '5.0'
    config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
    config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
  end
end
app.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.gorilla.map-interaction-checks'
  config.build_settings['INFOPLIST_KEY_UIApplicationSceneManifest_Generation'] = 'YES'
  config.build_settings['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
end
tests.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.gorilla.map-gesture-uitests'
  config.build_settings['TEST_TARGET_NAME'] = 'GorillaMapChecks'
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_build_target(tests)
scheme.add_test_target(tests)
scheme.set_launch_target(app)
scheme.save_as(project.path, 'GestureChecks', true)
