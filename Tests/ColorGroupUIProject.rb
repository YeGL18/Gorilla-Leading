require 'xcodeproj'
require 'fileutils'
repo = File.expand_path('..', __dir__)
root = '/private/tmp/GorillaColorGroupUI'
FileUtils.mkdir_p(root)
policy = File.read("#{repo}/GorillaTranslate/Models/TimePhase.swift")
policy = policy[policy.index('enum GorillaColorGroup:')...policy.index('// MARK: - Time Phase Model')]
settings = File.read("#{repo}/GorillaTranslate/Views/SettingsView.swift")
picker = settings[settings.index('struct GorillaColorGroupPicker:')...settings.index('struct VisitRecordingSettingsView:')]
dots = File.read("#{repo}/GorillaTranslate/Views/DotMatrixView.swift")
dots = dots[dots.index('struct DotMatrixWebView:')..]
fixture = <<~SWIFT
  import SwiftUI
  import WebKit
  #{policy}
  #{picker}
  #{dots}
  final class TimePhaseManager {}
  struct TimeBasedOrbView: View {
    let phaseManager: TimePhaseManager
    let clock: AnimationClock
    let orbEnabled: Bool
    let orbSizeMultiplier: CGFloat
    var body: some View { Color.clear }
  }
  struct HomeFixture: View {
    @StateObject private var clock = AnimationClock()
    var body: some View {
      AnimatedBackground(clock: clock, orbEnabled: true, overlapGlowEnabled: M3ConceptPalette.homeOrbMixing,
        customOrbColors: M3ConceptPalette.homeOrbs, backgroundColorHex: M3ConceptPalette.black)
        .overlay(alignment: .topLeading) {
          Text("Gorilla").font(.largeTitle.bold()).foregroundStyle(Color(hex: M3ConceptPalette.yellow))
            .padding(30)
        }
    }
  }
  struct Fixture: View {
    @AppStorage("colorGroupMode") private var raw = -1
    @AppStorage("darkKnightMode") private var legacy = false
    private var group: GorillaColorGroup { .resolve(raw: raw, legacyDarkKnight: legacy) }
    var body: some View {
      NavigationStack {
        List {
          Section { GorillaColorGroupPicker() }
          if group.showsOrbControls { Text("Normal Orb Controls").accessibilityIdentifier("orbControls") }
          Section {
            Text(group.dotColorHex(speed: 120, preset: 0)).accessibilityIdentifier("dotColor")
            DotMatrixWebView(speed: .constant(120), canvasScale: 1,
                            dynamicColorHex: group.dotColorHex(speed: 120, preset: 0))
              .frame(height: 280)
              .listRowBackground(Color(hex: group == .m3Concept ? M3ConceptPalette.black : "000000"))
          }
        }.navigationTitle("Color Group Mode")
      }.environment(\\.colorScheme, .dark)
    }
  }
  @main struct CheckApp: App {
    init() {
      UserDefaults.standard.set(!ProcessInfo.processInfo.arguments.contains("-nativeOrbs"), forKey: "orbCanvasDitherEnabled")
      if ProcessInfo.processInfo.arguments.contains("-resetColorGroup") {
        UserDefaults.standard.removeObject(forKey: "colorGroupMode")
        UserDefaults.standard.removeObject(forKey: "darkKnightMode")
      }
    }
    var body: some Scene {
      WindowGroup {
        if ProcessInfo.processInfo.arguments.contains("-homeM3") { HomeFixture() }
        else { Fixture() }
      }
    }
  }
SWIFT
File.write("#{root}/Fixture.swift", fixture)
project = Xcodeproj::Project.new("#{root}/ColorGroupChecks.xcodeproj")
app = project.new_target(:application, 'ColorGroupChecks', :ios, '26.0')
tests = project.new_target(:ui_test_bundle, 'ColorGroupUITests', :ios, '26.0')
app.source_build_phase.add_file_reference(project.main_group.new_file("#{root}/Fixture.swift"))
app.source_build_phase.add_file_reference(project.main_group.new_file("#{repo}/GorillaTranslate/Extensions/ColorExtension.swift"))
%w[Models/AnimationClock.swift Views/AnimatedBackground.swift Shaders/MetaballEffect.metal].each do |file|
  app.source_build_phase.add_file_reference(project.main_group.new_file("#{repo}/GorillaTranslate/#{file}"))
end
tests.source_build_phase.add_file_reference(project.main_group.new_file("#{repo}/Tests/ColorGroupUITests.swift"))
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
