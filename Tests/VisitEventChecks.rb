require 'fileutils'
source = File.read(File.expand_path('../GorillaTranslate/Models/LocationManager.swift', __dir__))
def section(source, first, last)
  start = source.index(first) or abort "Missing #{first}"
  finish = source.index(last, start) or abort "Missing #{last}"
  source[start...finish]
end
native = section(source, 'struct NativeVisitEvent:', '// MARK: - Kalman')
record = section(source, '    struct VisitRecord:', '    @Published var speed:')
queue = section(source, '    private var historyPrepared =', '    func startLocationServicesIfNeeded()')
queue.gsub!('private ', '')
queue.sub!(/var pendingVisitURL: URL \{.*?\n    \}/m, 'var pendingVisitURL: URL { fixtureRoot.appendingPathComponent("pending-native-visits.json") }')
queue.sub!('.completeFileProtectionUntilFirstUserAuthentication', '')
queue.sub!('options: [.atomic, ]', 'options: [.atomic]')
apply = section(source, '    @discardableResult\n'.gsub('\\n', "\n") + '    private func applyVisitEvent(', '    private func geocodeVisit(').gsub('private ', '')
fixture = <<~SWIFT
  import Foundation
  import CoreLocation
  #{native}
  final class UIApplication {
    static let shared = UIApplication()
    var isProtectedDataAvailable = true
  }
  final class FixtureManager {
    enum Authorization { case authorizedAlways }
    var authorizationStatus = Authorization.authorizedAlways
    var starts = 0
    func startMonitoringVisits() { starts += 1 }
  }
  final class LocationManager {
    #{record}
    let fixtureRoot: URL
    let manager = FixtureManager()
    var visits: [VisitRecord] = []
    var motionSegments: [Int] = []
    var carExitEvents: [Int] = []
    var seenBluetoothDevices: [Int] = []
    var myCarBluetooth: Int?
    var motionHistoryThrough: Date?
    var motionHistoryFrom: Date?
    var motionHistoryGeneration = UUID()
    var motionHistoryInFlight = false
    var motionHistoryAttemptAt: Date?
    var hydrationCalls = 0
    var geocoded = 0
    init(root: URL) { fixtureRoot = root }
    func loadVisits() {
      hydrationCalls += 1
      if let data = try? Data(contentsOf: fixtureRoot.appendingPathComponent("visits.json")) {
        visits = try! JSONDecoder().decode([VisitRecord].self, from: data)
      }
    }
    func loadMotionSegments() {}; func loadCarExitEvents() {}; func loadCarBluetoothState() {}
    func startCarAudioRouteMonitor() {}
    func backfillMotionSegments() {}
    func classifyTrip(tripStart: Date?, arrival: Date) -> (transportType: String, isAutomotive: Bool) { ("Driving", true) }
    func geocodeVisit(_ record: VisitRecord) { geocoded += 1 }
    func upsertVisitRecord(_ record: VisitRecord) {
      if let index = visits.firstIndex(where: { $0.id == record.id }) {
        if let departure = record.departureDate { visits[index].departureDate = departure }
      } else { visits.append(record) }
      try! JSONEncoder().encode(visits).write(to: fixtureRoot.appendingPathComponent("visits.json"))
    }
    #{queue}
    #{apply}
  }
SWIFT
root = '/private/tmp/gorilla-visit-event-tests'
FileUtils.mkdir_p(root)
File.write("#{root}/Models.swift", fixture)
checks = File.expand_path('VisitEventChecks.swift', __dir__)
abort 'Compilation failed' unless system('swiftc', '-module-cache-path', '/private/tmp/gorilla-swift-test-cache', "#{root}/Models.swift", checks, '-o', "#{root}/checks")
abort 'Tests failed' unless system("#{root}/checks")
