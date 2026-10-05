require 'fileutils'

repo = File.expand_path('..', __dir__)
source = File.read("#{repo}/Shared/GorillaActivityAttributes.swift")
first = source.index('enum ParkingEntryClock {') or abort 'Missing entry clock'
last = source.index('enum GorillaActivityLocalization {', first) or abort 'Missing clock boundary'
directory = '/private/tmp/gorilla-parking-entry-tests'
FileUtils.mkdir_p(directory)
File.write("#{directory}/Clock.swift", "import Foundation\n#{source[first...last]}")
abort 'Compilation failed' unless system('swiftc', '-module-cache-path', '/private/tmp/gorilla-swift-test-cache',
  "#{directory}/Clock.swift", "#{repo}/Tests/ParkingEntryClockChecks.swift", '-o', "#{directory}/checks")
abort 'Tests failed' unless system("#{directory}/checks")

view = File.read("#{repo}/GorillaTranslate/ContentView.swift")
abort 'Live Activity still uses the original arrival' unless view.include?("activityState = (isNonAutomotiveArrival && !hasParkingSpotData) ? .nonAutomotiveParking : .parking\n            anchor = parkingEntryTime")
abort 'Adjustment not persisted and pushed immediately' unless view.match?(/private func adjustParkingEntryTime.*?saveParkingState\(\).*?syncLiveActivity\(forceRefresh: true\)/m)
widget = File.read("#{repo}/ParkingTimerWidget/ParkingTimerWidget.swift")
abort 'Widget not using adjusted entry clock' unless widget.include?('ParkingEntryClock.restoredEntry(for: arrival, defaults: defaults)')
puts 'PASS: app, Live Activity and widget entry-clock integration checks'
