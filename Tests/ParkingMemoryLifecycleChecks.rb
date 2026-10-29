require 'fileutils'
repo = File.expand_path('..', __dir__)
source = File.read("#{repo}/GorillaTranslate/ContentView.swift")
shared = File.read("#{repo}/Shared/GorillaActivityAttributes.swift")
clock = shared[shared.index('enum ParkingEntryClock {')...shared.index('enum GorillaActivityLocalization {')]
refresh = source[source.index('    private func refreshVisitAndTimersForForeground()')...source.index('    private func startPersistentTimer()')].sub('private func', 'func')
fields = %w[locationManager manualParkingStartedAt hasDeparted parkingVisitsDismissedThrough manualDeparted timerRunning parkingTimer departureElapsedTimer departureTime departureElapsed parkingStartTime parkingEntryTime lastKnownArrivalDate parkingElapsed capsuleDuration parkingFloorStore timeAdjustAccumulated]
# The production method lives on a SwiftUI value. Qualify captures for this reference-type harness.
fields.each { |name| refresh = refresh.gsub(/(?<![.\w])#{name}\b/, "self.#{name}") }
root = '/private/tmp/gorilla-parking-memory-lifecycle'
FileUtils.mkdir_p(root)
File.write("#{root}/Checks.swift", <<~SWIFT)
  import Foundation
  #{clock}
  struct Visit { var arrivalDate: Date; var departureDate: Date? }
  final class Manager { var hasLoadedVisits = true; var visits: [Visit] = [] }
  final class Floors { func acceptPredictedFloorAtDeparture() {} }
  final class GorillaActivityManager {
      static let shared = GorillaActivityManager()
      func end() {}
  }
  final class Memory {
      static var appGroupDefaults: UserDefaults?
      let locationManager = Manager()
      let parkingFloorStore = Floors()
      var manualParkingStartedAt: Date?
      var parkingVisitsDismissedThrough: Date?
      var hasDeparted = false, manualDeparted = false, timerRunning = false
      var parkingTimer: Timer?, departureElapsedTimer: Timer?
      var departureTime: Date?, lastKnownArrivalDate: Date?
      var departureElapsed = 0.0, parkingElapsed = 0.0, capsuleDuration = 0.0
      var parkingStartTime = Date(), parkingEntryTime = Date()
      var timeAdjustAccumulated = 0, stationaryResumes = 0, pointChecks = 0
      func updateVisitStatus() {}
      func ensureManualParkingPoint() { pointChecks += 1 }
      func ensureStationaryTimerRunning() { stationaryResumes += 1 }
      func saveParkingState() {}
      func resetParkingTimeAdjustment() { timeAdjustAccumulated = 0 }
      func showAdjustText() {}
      func startPersistentTimer() {
          timerRunning = true
          parkingElapsed = Date().timeIntervalSince(parkingEntryTime)
          capsuleDuration = parkingElapsed
      }
      #{refresh}
  }
  let suite = "gorilla.parking-memory-lifecycle.\\(ProcessInfo.processInfo.processIdentifier)"
  let defaults = UserDefaults(suiteName: suite)!
  defer { defaults.removePersistentDomain(forName: suite) }
  Memory.appGroupDefaults = defaults
  let now = Date()
  let originalArrival = now.addingTimeInterval(-7200)
  let stoppedAt = now.addingTimeInterval(-5400)
  let manualStart = now.addingTimeInterval(-3600)
  let stopped = Memory()
  stopped.parkingStartTime = originalArrival
  stopped.parkingVisitsDismissedThrough = stoppedAt
  stopped.hasDeparted = true
  stopped.manualDeparted = true
  stopped.locationManager.visits = [Visit(arrivalDate: originalArrival)]
  stopped.refreshVisitAndTimersForForeground()
  precondition(stopped.hasDeparted && !stopped.timerRunning && stopped.stationaryResumes == 1)
  ParkingEntryClock.save(arrival: manualStart, entry: manualStart, defaults: defaults)
  defaults.set(manualStart, forKey: "manualParkingStartedAt")
  defaults.set(manualStart, forKey: "parkingVisitsDismissedThrough")
  let reopened = UserDefaults(suiteName: suite)!
  let manual = Memory()
  manual.manualParkingStartedAt = reopened.object(forKey: "manualParkingStartedAt") as? Date
  manual.parkingVisitsDismissedThrough = reopened.object(forKey: "parkingVisitsDismissedThrough") as? Date
  manual.parkingStartTime = reopened.object(forKey: "parkingStartTime") as! Date
  manual.parkingEntryTime = ParkingEntryClock.restoredEntry(for: manual.parkingStartTime, defaults: reopened)
  manual.locationManager.visits = [Visit(arrivalDate: originalArrival)]
  manual.refreshVisitAndTimersForForeground()
  precondition(manual.timerRunning && !manual.hasDeparted && manual.parkingStartTime == manualStart)
  precondition(abs(manual.parkingElapsed - 3600) < 2, "Relaunch must not revert the timer to the two-hour-old visit")
  manual.locationManager.visits = [Visit(arrivalDate: originalArrival, departureDate: stoppedAt)]
  manual.refreshVisitAndTimersForForeground()
  precondition(manual.timerRunning && !manual.hasDeparted && manual.parkingStartTime == manualStart)
  manual.locationManager.visits = []
  manual.refreshVisitAndTimersForForeground()
  precondition(manual.timerRunning && manual.parkingStartTime == manualStart)
  let nextArrival = now.addingTimeInterval(-120)
  manual.locationManager.visits = [Visit(arrivalDate: nextArrival)]
  manual.refreshVisitAndTimersForForeground()
  precondition(manual.manualParkingStartedAt == nil && manual.parkingStartTime == nextArrival)
  precondition(manual.parkingEntryTime == nextArrival && !manual.hasDeparted)
  print("PASS: actual foreground lifecycle preserves manual departure, manual restart, relaunch, late old departure, no visits and genuine new arrival")
SWIFT
abort 'Compile failed' unless system('swiftc', '-module-cache-path', '/private/tmp/gorilla-swift-test-cache', "#{root}/Checks.swift", '-o', "#{root}/checks")
abort 'Checks failed' unless system("#{root}/checks")
