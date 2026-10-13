require 'xcodeproj'
require 'fileutils'
repo = File.expand_path('..', __dir__)
root = '/private/tmp/GorillaCameraPauseUI'
FileUtils.mkdir_p(root)
def section(source, first, last)
  start = source.index(first) or abort "Missing #{first}"
  finish = source.index(last, start) or abort "Missing #{last}"
  source[start...finish]
end
content = File.read("#{repo}/GorillaTranslate/ContentView.swift")
camera = section(content, 'struct CameraPreviewView:', '// MARK: - Camera Photo Item')
button = section(content, '    private var cameraButton:', '    // MARK: - GPS Status Badge')
activity = File.read("#{repo}/ParkingTimerWidget/GorillaLiveActivity.swift")
row = section(activity, 'struct GorillaInfoRow:', '// MARK: - Preview')
fixture = <<~SWIFT
  import SwiftUI
  import UIKit
  import AVFoundation
  import CoreImage
  extension Notification.Name { static let captureParkingPhoto = Notification.Name("cameraPauseCheck") }
  #{camera}
  #{row}
  final class PhotoStorage { static let maxPhotos = 4; var photos: [Int] = [] }
  struct Fixture: View {
    @State private var active = true
    @State private var paused: UIImage?
    @State private var opacity = 0.0
    @State private var freezes = 0
    @State private var cameraButtonBlurIn = true
    @State private var showingExpandedPhotos = false
    @State private var isCapturePressed = false
    @State private var animationClock = AnimationClock()
    let photoStorage = PhotoStorage()
    func capturePhoto() {}
    #{button}
    var body: some View {
      VStack(spacing: 12) {
        GorillaInfoRow(state: GorillaActivityAttributes.ContentState(state: .stationary,
          startDate: .now, road: "CENTERED ADDRESS", etaMinutes: 7, destinationName: "Destination", distanceText: "2 km", languageCode: "en"))
          .padding(.horizontal, 16).padding(.vertical, 12).background(.black)
        ZStack {
          CameraPreviewView(sessionRunning: active, onPausedFrame: { image in
            guard !active else { return }
            paused = image; freezes += 1
            withAnimation(.easeInOut(duration: 0.8)) { opacity = 1 }
          }, onPreviewReady: {
            guard active else { return }
            withAnimation(.easeInOut(duration: 0.8)) { opacity = 0 }
          })
          if let paused {
            Image(uiImage: paused).resizable().scaledToFill().frame(width: 338, height: 235)
              .blur(radius: 16 * opacity).opacity(active ? opacity : 1)
              .accessibilityIdentifier("pausedCameraFrame")
          }
          cameraButton
        }.frame(width: 338, height: 235).clipShape(.rect(cornerRadius: 37))
        Text("\\(freezes)").accessibilityIdentifier("freezeCount")
        Button("Pause") { active = false }
        Button("Resume") { active = true }
      }.padding(.vertical, 12).background(Color.green.opacity(0.3))
    }
  }
  @main struct CheckApp: App { var body: some Scene { WindowGroup { Fixture() } } }
SWIFT
File.write("#{root}/Fixture.swift", fixture)
project = Xcodeproj::Project.new("#{root}/CameraPauseChecks.xcodeproj")
app = project.new_target(:application, 'CameraPauseChecks', :ios, '26.0')
tests = project.new_target(:ui_test_bundle, 'CameraPauseUITests', :ios, '26.0')
app.source_build_phase.add_file_reference(project.main_group.new_file("#{root}/Fixture.swift"))
app.source_build_phase.add_file_reference(project.main_group.new_file("#{repo}/Shared/GorillaActivityAttributes.swift"))
%w[Models/AnimationClock.swift Extensions/ColorExtension.swift].each do |source|
  app.source_build_phase.add_file_reference(project.main_group.new_file("#{repo}/GorillaTranslate/#{source}"))
end
tests.source_build_phase.add_file_reference(project.main_group.new_file("#{repo}/Tests/CameraPauseUITests.swift"))
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
    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = "com.gorilla.#{target.name.downcase}"
  end
end
app.build_configurations.each do |config|
  config.build_settings['INFOPLIST_KEY_UIApplicationSceneManifest_Generation'] = 'YES'
  config.build_settings['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
end
tests.build_configurations.each { |c| c.build_settings['TEST_TARGET_NAME'] = app.name }
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_build_target(tests)
scheme.add_test_target(tests)
scheme.set_launch_target(app)
scheme.save_as(project.path, app.name, true)
