require 'xcodeproj'
require 'fileutils'

repo = File.expand_path('..', __dir__)
root = '/private/tmp/GorillaCommunityChatUI'
FileUtils.mkdir_p(root)
model = File.read("#{repo}/GorillaTranslate/Models/ParkingCommunity.swift")
view = File.read("#{repo}/GorillaTranslate/Views/ParkingCommunityView.swift")
message = model[model.index('struct CommunityMessage:')...model.index('struct CommunityThread:')]
bubble = view[view.index('struct CommunityMessageBubble:')...view.index('private struct CommunityThreadDetail:')]
abort 'Inbox must remain directly accessible' unless view.include?('accessibilityIdentifier("community.inbox")')
File.write("#{root}/Fixture.swift", <<~SWIFT)
  import SwiftUI
  import UIKit
  #{message}
  #{bubble}
  @main struct CommunityChatCheckApp: App {
      var body: some Scene { WindowGroup { Fixture() } }
  }
  struct Fixture: View {
      private let messages = try! JSONDecoder().decode([CommunityMessage].self, from: Data(#"[{"id":"1","authorId":"other","text":"留意入返咪錶，架車仲喺度。","createdAt":1793500000,"mine":false},{"id":"2","authorId":"self","text":"唔該師兄，我而家過嚟。","createdAt":1793500040,"mine":true},{"id":"3","authorId":"other","text":"收到，唔使急。","createdAt":1793500060,"mine":false},{"id":"4","authorId":"self","text":"多謝提醒！","createdAt":1793500080,"mine":true}]"#.utf8))
      var body: some View {
          NavigationStack {
              ScrollView {
                  VStack(spacing: 12) { ForEach(messages) { CommunityMessageBubble(message: $0) } }
                      .padding(16)
              }
              .background(Color(uiColor: .systemGroupedBackground))
              .navigationTitle("AB 1234").navigationBarTitleDisplayMode(.inline)
          }
          .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--dark") ? .dark : .light)
      }
  }
SWIFT
project = Xcodeproj::Project.new("#{root}/CommunityChatChecks.xcodeproj")
app = project.new_target(:application, 'CommunityChatChecks', :ios, '26.0')
tests = project.new_target(:ui_test_bundle, 'CommunityChatUITests', :ios, '26.0')
app.source_build_phase.add_file_reference(project.main_group.new_file("#{root}/Fixture.swift"))
tests.source_build_phase.add_file_reference(project.main_group.new_file("#{repo}/Tests/CommunityChatUITests.swift"))
tests.add_dependency(app)
[app, tests].each do |target|
  target.build_configurations.each do |config|
    config.build_settings['SWIFT_VERSION'] = '5.0'
    config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
    config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  end
end
app.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.gorilla.community-chat-checks'
  config.build_settings['INFOPLIST_KEY_UIApplicationSceneManifest_Generation'] = 'YES'
  config.build_settings['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
end
tests.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.gorilla.community-chat-uitests'
  config.build_settings['TEST_TARGET_NAME'] = 'CommunityChatChecks'
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_build_target(tests)
scheme.add_test_target(tests)
scheme.set_launch_target(app)
scheme.save_as(project.path, 'CommunityChatChecks', true)
