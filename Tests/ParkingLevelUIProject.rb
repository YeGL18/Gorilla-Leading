require 'xcodeproj'
require 'fileutils'

repo = File.expand_path('..', __dir__)
root = '/private/tmp/GorillaParkingLevelUI'
FileUtils.mkdir_p(root)
abort 'Generate model checks first' unless File.exist?('/private/tmp/gorilla-parking-level-tests/Models.swift')
models = File.read('/private/tmp/gorilla-parking-level-tests/Models.swift')
source = File.read("#{repo}/GorillaTranslate/Views/SettingsView.swift")
first = source.index('struct ParkingFlowTestView:') or abort 'Missing diagnostics'
last = source.index('struct AddressCapsuleBeamTestView:', first) or abort 'Missing diagnostics boundary'
fixture = <<~SWIFT
  import SwiftUI
  import MapKit
  import Charts
  #{models}
  #{source[first...last]}
  @main struct ParkingLevelCheckApp: App {
    @StateObject private var store: ParkingFloorStore
    init() {
      let date = TestClock.now
      let floors = [0, -1, -3, -4]
      let points = floors.enumerated().map { index, floor in
        ParkingPointRecord(id: UUID(), address: "Residence", latitude: 22.316, longitude: 114.18,
          createdAt: date.addingTimeInterval(Double(-index * 3600)),
          predictedFloorIndex: floor, manualFloorIndex: floor,
          barometerAltitudeDeltaMeters: Double(floor * 3), barometerSampleCount: 40)
      }
      let lot = ParkingLotRecord(id: UUID(), name: "Residence", centerLatitude: 22.316,
        centerLongitude: 114.18, radiusMeters: 180, createdAt: date, updatedAt: date, points: points)
      TestDefaults.standard.set(try! JSONEncoder().encode([lot]), forKey: "parking_floor_store_v1")
      TestDefaults.standard.set(1, forKey: "parkingFloorMode")
      let store = ParkingFloorStore()
      store.prepare()
      _store = StateObject(wrappedValue: store)
    }
    var body: some Scene {
      WindowGroup {
        NavigationStack { ParkingFlowTestView() }.environmentObject(store)
      }
    }
  }
SWIFT
File.write("#{root}/ParkingFixture.swift", fixture)
project = Xcodeproj::Project.new("#{root}/ParkingChecks.xcodeproj")
app = project.new_target(:application, 'ParkingLevelChecks', :ios, '27.1')
tests = project.new_target(:ui_test_bundle, 'ParkingLevelUITests', :ios, '27.1')
app.source_build_phase.add_file_reference(project.main_group.new_file("#{root}/ParkingFixture.swift"))
tests.source_build_phase.add_file_reference(project.main_group.new_file("#{repo}/Tests/ParkingLevelUITests.swift"))
tests.add_dependency(app)
resources = project.main_group.new_variant_group('Localizable.strings')
%w[en zh-Hant zh-Hans ja].each do |locale|
  file = resources.new_file("#{repo}/GorillaTranslate/Resources/Localization/#{locale}.lproj/Localizable.strings")
  file.name = locale
end
app.resources_build_phase.add_file_reference(resources)
[app, tests].each do |target|
  target.build_configurations.each do |config|
    config.build_settings['SWIFT_VERSION'] = '5.0'
    config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
    config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
  end
end
app.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.gorilla.parking-level-checks'
  config.build_settings['INFOPLIST_KEY_UIApplicationSceneManifest_Generation'] = 'YES'
  config.build_settings['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
end
tests.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.gorilla.parking-level-uitests'
  config.build_settings['TEST_TARGET_NAME'] = 'ParkingLevelChecks'
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_build_target(tests)
scheme.add_test_target(tests)
scheme.set_launch_target(app)
scheme.save_as(project.path, 'ParkingChecks', true)
