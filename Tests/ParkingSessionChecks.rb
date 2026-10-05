require 'fileutils'

repo = File.expand_path('..', __dir__)
source = File.read("#{repo}/GorillaTranslate/Models/LocationManager.swift")
first = source.index('struct BarometerSample:') or abort 'Missing capture model'
last = source.index('    struct WindowResult {', first) or abort 'Missing manager boundary'
# Run the actual manager with a deterministic clock and a fake Core Motion device.
isolated_suite = "gorilla.parking-session-tests.#{Process.pid}"
model = source[first...last].gsub('Date()', 'TestClock.now')
model = model.gsub('ProcessInfo.processInfo.systemUptime', 'TestClock.uptime')
model = model.gsub('group.com.gorilla.translate', isolated_suite) + "}\n"
directory = '/private/tmp/gorilla-parking-session-tests'
FileUtils.mkdir_p(directory)
fixtures = File.read("#{repo}/Tests/ParkingSessionFixtures.swift")
File.write("#{directory}/Models.swift", "import Foundation\nimport CoreLocation\nimport Combine\n#{fixtures}\n#{model}")
checks = "#{repo}/Tests/ParkingSessionChecks.swift"
abort 'Compilation failed' unless system('swiftc', '-module-cache-path', '/private/tmp/gorilla-swift-test-cache', "#{directory}/Models.swift", checks, '-o', "#{directory}/checks")
abort 'Tests failed' unless system("#{directory}/checks", isolated_suite)
