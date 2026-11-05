require 'xcodeproj'
require 'fileutils'
repo = File.expand_path('..', __dir__)
root = '/private/tmp/GorillaAppleLoginUI'
FileUtils.mkdir_p(root)
model = File.read("#{repo}/GorillaTranslate/Models/ParkingCommunity.swift")
view = File.read("#{repo}/GorillaTranslate/Views/ParkingCommunityView.swift")
login = view[view.index('struct CommunityLoginView:')...view.index('private struct CommunityInbox:')]
File.write("#{root}/Fixture.swift", <<~SWIFT)
  import SwiftUI
  import AuthenticationServices
  import CryptoKit
  #{model}
  // Service settings are outside the login-button fixture.
  private struct CommunityPlateSettings: View {
      let store: ParkingCommunityStore
      let introductory: Bool
      let onContinue: () -> Void
      var body: some View { Text("Service settings") }
  }
  #{login}
  final class ApplePreviewProtocol: URLProtocol, @unchecked Sendable {
      override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "apple-preview.invalid" }
      override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
      override func startLoading() {
          let path = request.url!.path
          let body: [String: Any]
          if path.hasSuffix("capabilities") {
              body = ["push": ["apns": false, "fcm": false], "auth": ["apple": true]]
          } else if path.hasSuffix("challenge") {
              body = ["challengeId": "preview-challenge", "nonce": "preview-nonce"]
          } else { body = ["token": "preview-only-token", "userId": "preview-only-user"] }
          client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
          client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: body))
          client?.urlProtocolDidFinishLoading(self)
      }
      override func stopLoading() {}
  }
  @main struct AppleLoginPreviewApp: App { var body: some Scene { WindowGroup { AppleLoginPreview() } } }
  @MainActor struct AppleLoginPreview: View {
      @StateObject private var store: ParkingCommunityStore
      @State private var ready = false
      init() {
          let config = URLSessionConfiguration.ephemeral
          config.protocolClasses = [ApplePreviewProtocol.self]
          let api = CommunityHTTPClient(baseURL: URL(string: "https://apple-preview.invalid/v1/parking-community")!, session: URLSession(configuration: config))
          _store = StateObject(wrappedValue: ParkingCommunityStore(api: api))
      }
      var body: some View {
          Group {
              if ready { CommunityLoginView(store: store, linkingApple: ProcessInfo.processInfo.arguments.contains("--link")) }
              else { ProgressView() }
          }
          .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--dark") ? .dark : .light)
          .task {
              // UI fixtures never fabricate signed-in credentials. The link case
              // checks that an unauthenticated user cannot begin authorization.
              store.api.clearSession()
              ready = true
          }
      }
  }
SWIFT
project = Xcodeproj::Project.new("#{root}/AppleLoginChecks.xcodeproj")
app = project.new_target(:application, 'AppleLoginChecks', :ios, '26.0')
tests = project.new_target(:ui_test_bundle, 'AppleLoginUITests', :ios, '26.0')
app.source_build_phase.add_file_reference(project.main_group.new_file("#{root}/Fixture.swift"))
tests.source_build_phase.add_file_reference(project.main_group.new_file("#{repo}/Tests/AppleLoginUITests.swift"))
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
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.gorilla.apple-login-checks'
  config.build_settings['INFOPLIST_KEY_UIApplicationSceneManifest_Generation'] = 'YES'
  config.build_settings['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
end
tests.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.gorilla.apple-login-uitests'
  config.build_settings['TEST_TARGET_NAME'] = 'AppleLoginChecks'
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app); scheme.add_build_target(tests); scheme.add_test_target(tests)
scheme.set_launch_target(app); scheme.save_as(project.path, 'AppleLoginChecks', true)
puts project.path
