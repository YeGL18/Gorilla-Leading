require 'fileutils'
require 'xcodeproj'

repo = File.expand_path('..', __dir__)
root = '/private/tmp/GorillaDataToolsChecks'
FileUtils.mkdir_p(root)
project = Xcodeproj::Project.open("#{repo}/GorillaTranslation.xcodeproj")
# Clone the real app into a disposable test project, never edit the user's project.
project.files.each do |file|
  next unless ['<group>', 'SOURCE_ROOT'].include?(file.source_tree)
  real = file.real_path.to_s
  next unless File.exist?(real)
  file.path = real
  file.source_tree = '<absolute>'
end
project.objects.grep(Xcodeproj::Project::Object::PBXFileSystemSynchronizedRootGroup).each do |group|
  group.path = File.join(repo, group.path)
  group.source_tree = '<absolute>'
end
app = project.targets.find { |target| target.name == 'GorillaTranslate' }
project.targets.each do |target|
  target.build_configurations.each do |config|
    config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
    config.build_settings['PODS_ROOT'] = "#{repo}/Pods"
    config.build_settings['PODS_PODFILE_DIR_PATH'] = repo
    if config.build_settings['INFOPLIST_FILE']
      config.build_settings['INFOPLIST_FILE'] = File.join(repo, config.build_settings['INFOPLIST_FILE'])
    end
    if config.build_settings['CODE_SIGN_ENTITLEMENTS']
      config.build_settings['CODE_SIGN_ENTITLEMENTS'] = File.join(repo, config.build_settings['CODE_SIGN_ENTITLEMENTS'])
    end
  end
end
tests = project.new_target(:unit_test_bundle, 'DataToolsTests', :ios, '26.0')
tests.add_dependency(app)
test_file = project.main_group.new_file("#{repo}/Tests/DataToolsTests.swift")
test_file.path = "#{repo}/Tests/DataToolsTests.swift"
test_file.source_tree = '<absolute>'
tests.source_build_phase.add_file_reference(test_file)
orb_tests = project.main_group.new_file("#{repo}/Tests/OrbRenderingTests.swift")
orb_tests.path = "#{repo}/Tests/OrbRenderingTests.swift"
orb_tests.source_tree = '<absolute>'
tests.source_build_phase.add_file_reference(orb_tests)
tests.build_configurations.each do |config|
  config.build_settings.merge!(
    'SWIFT_VERSION' => '5.0', 'GENERATE_INFOPLIST_FILE' => 'YES',
    'TARGETED_DEVICE_FAMILY' => '1,2', 'CODE_SIGNING_ALLOWED' => 'NO',
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.gorilla.data-tools-tests',
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'TEST_HOST' => '$(BUILT_PRODUCTS_DIR)/GorillaTranslate.app/GorillaTranslate',
    'BUNDLE_LOADER' => '$(TEST_HOST)'
  )
end
project.save("#{root}/DataToolsChecks.xcodeproj")
project = Xcodeproj::Project.open("#{root}/DataToolsChecks.xcodeproj")
app = project.targets.find { |target| target.name == 'GorillaTranslate' }
tests = project.targets.find { |target| target.name == 'DataToolsTests' }
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_build_target(tests)
scheme.add_test_target(tests)
scheme.set_launch_target(app)
scheme.save_as("#{root}/DataToolsChecks.xcodeproj", 'DataToolsChecks', true)
workspace = Xcodeproj::Workspace.new(nil)
workspace << "#{root}/DataToolsChecks.xcodeproj"
workspace << "#{repo}/Pods/Pods.xcodeproj"
workspace.save_as("#{root}/DataToolsChecks.xcworkspace")
puts "#{root}/DataToolsChecks.xcworkspace"
