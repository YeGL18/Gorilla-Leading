require 'fileutils'
require 'json'
root = '/private/tmp/gorilla-camera-checks'
FileUtils.mkdir_p(root)
repo = File.expand_path('..', __dir__)
source = File.read("#{repo}/GorillaTranslate/Models/TrafficCamera.swift")
policy = source[source.index('struct TrafficCamera:')...source.index('@MainActor')]
File.write("#{root}/Policy.swift", "import Foundation\nimport CoreLocation\n" + policy)
abort 'Compile failed' unless system('swiftc', '-module-cache-path', '/private/tmp/gorilla-swift-test-cache',
  "#{root}/Policy.swift", "#{repo}/Tests/TrafficCameraChecks.swift", '-o', "#{root}/checks")
abort 'Checks failed' unless system("#{root}/checks", "#{repo}/GorillaTranslate/Resources/traffic_cameras.json")
rows = JSON.parse(File.read("#{repo}/GorillaTranslate/Resources/traffic_cameras.json")).fetch('cameras')
abort 'Invalid bundled data' unless rows.size == 394 && rows.map { |r| r.fetch('id') }.uniq.size == 394
abort 'Invalid position' unless rows.all? { |r| (22.1..22.6).cover?(r['latitude']) && (113.8..114.5).cover?(r['longitude']) }
puts 'PASS: 394 unique official camera sites with Hong Kong coordinates'
matched = rows.select { |r| r['roadSpeedLimitKmh'] }
abort 'Missing road references' if matched.empty?
abort 'Unsafe reference match' unless matched.all? { |r| (10..110).cover?(r['roadSpeedLimitKmh']) && r['roadSpeedMatchDistance'] <= 45 && r['roadRouteID'] && r['roadSpeedLimitID'] && r['matchedRoadName'] }
puts "PASS: #{matched.size} preserved road references; unmatched sites display a labelled 50 km/h default"
