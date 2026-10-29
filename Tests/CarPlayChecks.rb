require 'fileutils'
require 'rexml/document'

repo = File.expand_path('..', __dir__)
source = File.read("#{repo}/GorillaTranslate/Models/GorillaCarPlay.swift")
policy = source.split('#if canImport(CarPlay)').first
shared = File.read("#{repo}/Shared/GorillaActivityAttributes.swift")
clock = shared[shared.index('enum ParkingEntryClock {')...shared.index('enum GorillaActivityLocalization {')]
abort 'CarPlay handoff must target its scene' unless source.include?('scene.open(url, options: nil)')
abort 'Do not redirect navigation to the phone' if source.include?('UIApplication.shared.open')
abort 'CarPlay refresh must not run every second' unless source.include?('Timer(timeInterval: 10,')
manifest = REXML::Document.new(File.read("#{repo}/GorillaTranslate/Info.plist"))
role = REXML::XPath.first(manifest, '//key[text()="CPTemplateApplicationSceneSessionRoleApplication"]')
abort 'Missing CarPlay scene registration' unless role
if ARGV.first
  xml = IO.popen(['plutil', '-convert', 'xml1', '-o', '-', ARGV.first], &:read)
  built = REXML::Document.new(xml)
  abort 'Build stripped the CarPlay scene registration' unless REXML::XPath.first(built, '//key[text()="CPTemplateApplicationSceneSessionRoleApplication"]')
end
entitlements = File.read("#{repo}/GorillaTranslate/GorillaTranslate.entitlements")
abort 'Do not add an unapproved CarPlay entitlement to normal builds' if entitlements.include?('com.apple.developer.carplay-')
root = '/private/tmp/gorilla-carplay-checks'
FileUtils.mkdir_p(root)
File.write("#{root}/Checks.swift", <<~SWIFT)
  import Foundation
  import CoreLocation
  #{clock}
  #{policy}
  @main struct Checks {
      static func main() {
          let suite = "gorilla.carplay-checks.\\(UUID().uuidString)"
          let defaults = UserDefaults(suiteName: suite)!
          defer { defaults.removePersistentDomain(forName: suite) }
          let now = Date(), arrival = now.addingTimeInterval(-3600)
          let info = ParkingSessionSnapshot(locationName: "Residence", spotNumber: "A123", areaCode: "A", floorDisplay: "B2", floorIndex: -2)
          func visit(_ date: Date, departure: Date? = nil, automotive: Bool = true) -> LocationManager.VisitRecord {
              .init(id: UUID(), address: "Street", latitude: 22.3, longitude: 114.17,
                    arrivalDate: date, departureDate: departure, transportType: "driving", isAutomotive: automotive)
          }
          func load(_ visit: LocationManager.VisitRecord?) -> CarPlayParkingPresentation {
              CarPlayParkingPresentation.load(defaults: defaults, latestVisit: visit, session: { _ in info })
          }
          precondition(load(nil).status == .inactive)
          defaults.set(arrival, forKey: "parkingStartTime")
          defaults.set(true, forKey: "timerRunning")
          ParkingEntryClock.save(arrival: arrival, entry: arrival.addingTimeInterval(-120), defaults: defaults)
          let active = load(visit(arrival))
          precondition(active.status == .parking && active.location == "Residence" && active.floor == "B2" && active.spot == "A123")
          precondition(active.duration(at: now) == "1:02")
          precondition(active.duration(at: arrival.addingTimeInterval(-1000)) == "0:00")
          let departed = load(visit(arrival, departure: now))
          precondition(departed.status == .departed && departed.entryTime == nil && departed.floor == nil && departed.spot == nil)
          let stay = load(visit(arrival, automotive: false))
          precondition(stay.status == .staying && stay.floor == nil && stay.spot == nil)
          defaults.set(true, forKey: "manualDeparted")
          defaults.set(true, forKey: "hasDeparted")
          defaults.set(now, forKey: "parkingVisitsDismissedThrough")
          precondition(load(visit(arrival)).entryTime == nil)
          let manual = now.addingTimeInterval(1)
          defaults.set(false, forKey: "manualDeparted")
          defaults.set(false, forKey: "hasDeparted")
          defaults.set(manual, forKey: "manualParkingStartedAt")
          defaults.set(manual, forKey: "parkingStartTime")
          ParkingEntryClock.save(arrival: manual, entry: manual.addingTimeInterval(-60), defaults: defaults)
          precondition(load(visit(arrival)).entryTime == manual.addingTimeInterval(-60), "Old visits must not rewind a manual session")
          precondition(load(nil).entryTime == manual.addingTimeInterval(-60))
          let fresh = manual.addingTimeInterval(600)
          precondition(load(visit(fresh)).entryTime == fresh, "A genuine later arrival starts its own timer")
          let reloaded = UserDefaults(suiteName: suite)!
          precondition(CarPlayParkingPresentation.load(defaults: reloaded, latestVisit: visit(arrival), session: { _ in info }).entryTime == manual.addingTimeInterval(-60))
          let coordinate = CLLocationCoordinate2D(latitude: 22.3, longitude: 114.17)
          let url = CarPlayMeterNavigation.url(coordinate: coordinate, name: "2607B 沐泰街")!
          let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
          let query = Dictionary(uniqueKeysWithValues: parts.queryItems!.map { ($0.name, $0.value!) })
          precondition(parts.scheme == "https" && parts.host == "maps.apple.com")
          precondition(query["dirflg"] == "d" && query["daddr"] == "22.3,114.17" && query["q"] == "2607B 沐泰街")
          precondition(CarPlayMeterNavigation.url(coordinate: .init(latitude: 100, longitude: 114), name: "Invalid") == nil)
          print("PASS: parking summary, timer adjustment, departure, non-driving stays, manual restart/reload, new visit and CarPlay Maps handoff URL")
      }
  }
SWIFT
abort 'Compilation failed' unless system('swiftc', '-module-cache-path', '/private/tmp/gorilla-swift-test-cache',
  '/private/tmp/gorilla-parking-level-tests/Models.swift', "#{root}/Checks.swift", '-o', "#{root}/checks")
abort 'Tests failed' unless system("#{root}/checks")
