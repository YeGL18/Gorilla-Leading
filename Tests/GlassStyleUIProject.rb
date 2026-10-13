require 'xcodeproj'
require 'fileutils'

repo = File.expand_path('..', __dir__)
root = '/private/tmp/GorillaGlassStyleUI'
FileUtils.mkdir_p(root)
content = File.read("#{repo}/GorillaTranslate/ContentView.swift")
policy = File.read("#{repo}/GorillaTranslate/Models/TimePhase.swift")
policy = policy[policy.index('enum GorillaColorGroup:')...policy.index('// MARK: - Time Phase Model')]
first = content.index('enum GorillaGlassStyle {') or abort 'Missing glass policy'
last = content.index('private struct DuoHingeStateReader:', first) or abort 'Missing glass boundary'
appearance_first = content.index('    private static func tabBarAppearance(') or abort 'Missing bar appearance'
appearance_last = content.index("    @ViewBuilder\n    private var orbBackground:", appearance_first)
abort 'Missing bar appearance boundary' unless appearance_last
appearance = content[appearance_first...appearance_last].sub('private static func', 'static func')
settings = File.read("#{repo}/GorillaTranslate/Views/SettingsView.swift")
picker_first = settings.index('                    Picker(String(localized: "玻璃樣式")') or abort 'Missing glass picker'
picker_last = settings.index('                    Picker(String(localized: "膠囊動畫")', picker_first) or abort 'Missing picker boundary'
map = File.read("#{repo}/GorillaTranslate/Views/MapView.swift")
compass_first = map.index('enum MapCompassAppearance {') or abort 'Missing compass appearance'
compass_last = map.index('/// 藍色定位點標註 view。', compass_first) or abort 'Missing compass boundary'
fixture = <<~SWIFT
  import SwiftUI
  import UIKit
  import MapKit
  #{policy}
  #{content[first...last]}
  #{map[compass_first...compass_last]}
  enum BarFixture {
  #{appearance}
  }
  struct TabBarAudit: UIViewRepresentable {
    let dark: Bool
    let tab: Int
    func makeUIView(context: Context) -> UILabel {
      let label = UILabel()
      label.accessibilityIdentifier = "actualTabBarAppearance"
      label.isAccessibilityElement = true
      return label
    }
    func updateUIView(_ label: UILabel, context: Context) {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak label] in
        guard let label, let root = label.window?.rootViewController,
              let bar = Self.tabController(in: root)?.tabBar else { return }
        // A nil color is the system's untinted appearance, not a black fill.
        let standardAlpha = bar.standardAppearance.backgroundColor?.cgColor.alpha ?? 0
        let scrollAlpha = (bar.scrollEdgeAppearance ?? bar.standardAppearance).backgroundColor?.cgColor.alpha ?? 0
        label.text = String(format: "%.2f/%.2f", Double(standardAlpha), Double(scrollAlpha))
      }
    }
    private static func tabController(in controller: UIViewController) -> UITabBarController? {
      if let tab = controller as? UITabBarController { return tab }
      for child in controller.children {
        if let tab = tabController(in: child) { return tab }
      }
      return nil
    }
  }
  struct GlassFixture: View {
    @AppStorage("capsuleDarkGlassEnabled") private var capsuleDarkGlassEnabled = true
    @AppStorage("darkKnightMode") private var darkKnightMode = false
    @AppStorage("colorGroupMode") private var colorGroupRaw = -1
    private var colorGroup: GorillaColorGroup { .resolve(raw: colorGroupRaw, legacyDarkKnight: darkKnightMode) }
    @State private var selectedTab = 0
    @State private var taps = 0
    @State private var settingsDark = false
    @State private var searchRadius = 500.0
    @State private var launchAnimation = true
    @StateObject private var compassBridge = MapCompassBridge()
    private var usesDarkGlass: Bool {
      GorillaGlassStyle.usesDarkGlass(preferredDark: capsuleDarkGlassEnabled, darkKnightMode: darkKnightMode)
    }
    var body: some View {
      TabView(selection: $selectedTab) {
        NavigationStack {
          Map(initialPosition: .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 22.32, longitude: 114.18),
            latitudinalMeters: 900, longitudinalMeters: 900)))
            .overlay(alignment: .topTrailing) {
              VStack {
                Text("GPS Ready").padding(16)
                  .modifier(GorillaCapsuleGlass(cornerRadius: 22))
                MapCompassToolbarView(bridge: compassBridge).frame(width: 44, height: 44)
              }.padding(20)
            }
            .overlay(alignment: .leading) {
              VStack(spacing: 10) {
                Button { taps += 1 } label: {
                  Image(systemName: "location.fill")
                    .font(.system(size: 20, weight: .medium)).frame(width: 44, height: 44)
                }
                  .buttonStyle(.glass).modifier(GorillaMapControlAppearance())
                  .accessibilityIdentifier("headingControl")
                Menu { Button("Destination") {} } label: {
                  Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .medium)).frame(width: 44, height: 44)
                }
                  .buttonStyle(.glass).modifier(GorillaMapControlAppearance())
                  .accessibilityIdentifier("searchControl")
                Button {} label: {
                  Image(systemName: "map.fill")
                    .font(.system(size: 20, weight: .medium)).frame(width: 44, height: 44)
                }
                  .buttonStyle(.glass).modifier(GorillaMapControlAppearance())
                  .accessibilityIdentifier("mapControl")
              }.padding(16)
            }
            .overlay(alignment: .bottom) {
              VStack {
                Text(usesDarkGlass ? "Dark" : "Clear").accessibilityIdentifier("glassMode")
                Text(capsuleDarkGlassEnabled ? "Dark" : "Clear").accessibilityIdentifier("glassPreference")
                Text("Taps: \\(taps)").accessibilityIdentifier("controlTaps")
              }.padding(24).frame(width: 240)
                .modifier(GorillaCapsuleGlass(cornerRadius: 34)).padding(.bottom, 24)
            }
        }
        .environment(\\.colorScheme, settingsDark ? .dark : .light)
        .tabItem { Label("Home", systemImage: "house.fill") }.tag(0)
        NavigationStack {
          Form {
            Picker("Appearance", selection: $settingsDark) {
              Text("Light").tag(false)
              Text("Dark").tag(true)
            }.accessibilityIdentifier("settingsAppearancePicker")
            #{settings[picker_first...picker_last]}
              .accessibilityIdentifier("glassStylePicker")
            Toggle("Dark Knight", isOn: $darkKnightMode).accessibilityIdentifier("darkKnightToggle")
            Toggle("Launch Animation", isOn: $launchAnimation)
            Button("Preview Driving") {}.accessibilityIdentifier("settingsPreview")
            Slider(value: $searchRadius, in: 100...800, step: 10) {
              Text("Search Radius")
            }
            SettingsColorAudit().accessibilityIdentifier("settingsColorAudit")
          }.navigationTitle("Settings")
        }
        .environment(\\.colorScheme, settingsDark ? .dark : .light)
        .tint(.accentColor)
        .tabItem { Label("Settings", systemImage: "gearshape") }.tag(1)
      }
      .modifier(GorillaTabBarStyle())
      .preferredColorScheme(settingsDark ? .dark : .light)
      .background {
        GorillaTabBarAppearanceReader(appearance: BarFixture.tabBarAppearance(darkGlassEnabled: usesDarkGlass))
      }
      .overlay(alignment: .topLeading) {
        TabBarAudit(dark: usesDarkGlass, tab: selectedTab).frame(width: 1, height: 1)
          .allowsHitTesting(false)
      }
      .overlay(alignment: .topTrailing) {
        CompassAudit(dark: usesDarkGlass, tab: selectedTab).frame(width: 1, height: 1)
          .allowsHitTesting(false)
      }
      .overlay(alignment: .bottomTrailing) {
        SettingsColorAudit()
          .environment(\\.colorScheme, settingsDark ? .dark : .light)
          .tint(.accentColor)
          .accessibilityIdentifier("normalSettingsColors")
          .frame(width: 1, height: 1).allowsHitTesting(false)
      }
      .onChange(of: usesDarkGlass) { _, dark in
        let appearance = BarFixture.tabBarAppearance(darkGlassEnabled: dark)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
      }
    }
  }
  struct SettingsColorAudit: View {
    @Environment(\\.self) private var environment
    var body: some View {
      let primary = Color.primary.resolve(in: environment)
      let accent = Color.accentColor.resolve(in: environment)
      Text(String(format: "%@/%.2f/%.2f/%.2f/%.2f",
                  environment.colorScheme == .dark ? "dark" : "light",
                  Double(primary.red), Double(accent.red), Double(accent.green), Double(accent.blue)))
    }
  }
  struct CompassAudit: UIViewRepresentable {
    let dark: Bool
    let tab: Int
    func makeUIView(context: Context) -> UILabel {
      let label = UILabel()
      label.accessibilityIdentifier = "actualCompassAppearance"
      label.isAccessibilityElement = true
      return label
    }
    func updateUIView(_ label: UILabel, context: Context) {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak label] in
        guard let label, let window = label.window,
              let container = Self.findCompass(in: window) else { return }
        let compass = container.compass
        let style = compass.overrideUserInterfaceStyle
        let expected = style == .unspecified ? container.traitCollection.userInterfaceStyle : style
        let matches = compass.traitCollection.userInterfaceStyle == expected ? "matched" : "mismatched"
        label.text = "\\(style.rawValue)/\\(matches)/\\(Int(compass.bounds.width))/\\(Int(compass.bounds.height))"
      }
    }
    private static func findCompass(in view: UIView) -> CompassContainerView? {
      if let container = view as? CompassContainerView { return container }
      for child in view.subviews {
        if let container = findCompass(in: child) { return container }
      }
      return nil
    }
  }
  @main struct GlassCheckApp: App {
    init() {
      if CommandLine.arguments.contains("reset-glass") {
        UserDefaults.standard.removeObject(forKey: "capsuleDarkGlassEnabled")
        UserDefaults.standard.removeObject(forKey: "darkKnightMode")
      }
      let dark = GorillaGlassStyle.usesDarkGlass(
        preferredDark: UserDefaults.standard.object(forKey: "capsuleDarkGlassEnabled") as? Bool ?? true,
        darkKnightMode: UserDefaults.standard.bool(forKey: "darkKnightMode")
      )
      let appearance = BarFixture.tabBarAppearance(darkGlassEnabled: dark)
      UITabBar.appearance().standardAppearance = appearance
      UITabBar.appearance().scrollEdgeAppearance = appearance
    }
    var body: some Scene { WindowGroup { GlassFixture() } }
  }
SWIFT
File.write("#{root}/Fixture.swift", fixture)
project = Xcodeproj::Project.new("#{root}/GlassStyleChecks.xcodeproj")
app = project.new_target(:application, 'GlassStyleChecks', :ios, '26.0')
tests = project.new_target(:ui_test_bundle, 'GlassStyleUITests', :ios, '26.0')
app.source_build_phase.add_file_reference(project.main_group.new_file("#{root}/Fixture.swift"))
app.source_build_phase.add_file_reference(project.main_group.new_file("#{repo}/GorillaTranslate/Extensions/ColorExtension.swift"))
tests.source_build_phase.add_file_reference(project.main_group.new_file("#{repo}/Tests/GlassStyleUITests.swift"))
tests.add_dependency(app)
resources = project.main_group.new_variant_group('Localizable.strings')
%w[en zh-Hant zh-Hans ja].each do |locale|
  file = resources.new_file("#{repo}/GorillaTranslate/Resources/Localization/#{locale}.lproj/Localizable.strings")
  file.name = locale
end
app.resources_build_phase.add_file_reference(resources)
app.resources_build_phase.add_file_reference(project.main_group.new_file("#{repo}/GorillaTranslate/Assets.xcassets"))
[app, tests].each do |target|
  target.build_configurations.each do |config|
    config.build_settings.merge!('SWIFT_VERSION' => '5.0', 'GENERATE_INFOPLIST_FILE' => 'YES',
                                'TARGETED_DEVICE_FAMILY' => '1,2', 'CODE_SIGNING_ALLOWED' => 'NO')
  end
end
app.build_configurations.each do |config|
  config.build_settings.merge!('PRODUCT_BUNDLE_IDENTIFIER' => 'com.gorilla.glass-style-checks',
    'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME' => 'AccentColor',
    'INFOPLIST_KEY_UIApplicationSceneManifest_Generation' => 'YES',
    'INFOPLIST_KEY_UILaunchScreen_Generation' => 'YES')
end
tests.build_configurations.each do |config|
  config.build_settings.merge!('PRODUCT_BUNDLE_IDENTIFIER' => 'com.gorilla.glass-style-uitests',
                              'TEST_TARGET_NAME' => 'GlassStyleChecks')
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_build_target(tests)
scheme.add_test_target(tests)
scheme.set_launch_target(app)
scheme.save_as(project.path, 'GlassStyleChecks', true)
