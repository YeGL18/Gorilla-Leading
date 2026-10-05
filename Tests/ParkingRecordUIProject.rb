require 'xcodeproj'
require 'fileutils'

repo = File.expand_path('..', __dir__)
root = '/private/tmp/GorillaParkingRecordUI'
FileUtils.mkdir_p(root)
models = File.read('/private/tmp/gorilla-parking-level-tests/Models.swift')
views = File.read("#{repo}/GorillaTranslate/Views/ParkingRecordViews.swift")
fixture = <<~SWIFT
  import SwiftUI
  #{models}
  #{views}
  struct ParkingPointDiagnosticsView: View {
    let pointID: UUID
    var body: some View { Text(pointID.uuidString) }
  }
  struct FixtureView: View {
    @ObservedObject var store: ParkingFloorStore
    @State private var showing = false
    @State private var selected = ""
    var body: some View {
      VStack {
        Button("History") { showing = true }
        Text(selected).accessibilityIdentifier("selectedRecord")
        Text("\\(store.recordGroups.count)").accessibilityIdentifier("groupCount")
        Text("\\(store.allPoints.filter(\\.isFloorConfirmed).count)").accessibilityIdentifier("confirmedCount")
      }.sheet(isPresented: $showing) {
        ParkingRecordListView(store: store, lotID: store.lots[0].id, groupID: nil) { id in selected = id.uuidString }
      }
    }
  }
  @main struct ParkingRecordCheckApp: App {
    @StateObject private var store: ParkingFloorStore
    init() {
      let date = TestClock.now
      var points: [ParkingPointRecord] = []
      for i in 1...50 {
        points.append(ParkingPointRecord(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", i))!,
          address: "Residence", latitude: 22.316, longitude: 114.18,
          createdAt: date.addingTimeInterval(Double(-i * 3600)), predictedFloorIndex: -1,
          barometerAltitudeDeltaMeters: -3, barometerSampleCount: 40))
      }
      let lot = ParkingLotRecord(id: UUID(), name: "Residence", centerLatitude: 22.316,
        centerLongitude: 114.18, radiusMeters: 180, createdAt: date, updatedAt: date, points: points)
      TestDefaults.standard.set(try! JSONEncoder().encode([lot]), forKey: "parking_floor_store_v1")
      TestDefaults.standard.set(1, forKey: "parkingFloorMode")
      let store = ParkingFloorStore()
      store.prepare()
      _store = StateObject(wrappedValue: store)
    }
    var body: some Scene { WindowGroup { FixtureView(store: store) } }
  }
SWIFT
File.write("#{root}/RecordFixture.swift", fixture)
project = Xcodeproj::Project.new("#{root}/ParkingRecordChecks.xcodeproj")
app = project.new_target(:application, 'ParkingRecordChecks', :ios, '18.0')
tests = project.new_target(:ui_test_bundle, 'ParkingRecordUITests', :ios, '18.0')
app.source_build_phase.add_file_reference(project.main_group.new_file("#{root}/RecordFixture.swift"))
tests.source_build_phase.add_file_reference(project.main_group.new_file("#{repo}/Tests/ParkingRecordUITests.swift"))
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
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.gorilla.parking-record-checks'
  config.build_settings['INFOPLIST_KEY_UIApplicationSceneManifest_Generation'] = 'YES'
  config.build_settings['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
  config.build_settings['INFOPLIST_KEY_UISupportedInterfaceOrientations'] = 'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight'
end
tests.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.gorilla.parking-record-uitests'
  config.build_settings['TEST_TARGET_NAME'] = 'ParkingRecordChecks'
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_build_target(tests)
scheme.add_test_target(tests)
scheme.set_launch_target(app)
scheme.save_as(project.path, 'ParkingRecordChecks', true)
