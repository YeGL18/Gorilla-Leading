require 'fileutils'

repo = File.expand_path('..', __dir__)
directory = '/private/tmp/gorilla-energy-policy-checks'
FileUtils.mkdir_p(directory)
destination = File.read("#{repo}/GorillaTranslate/Models/Destination.swift")
location = File.read("#{repo}/GorillaTranslate/Models/LocationManager.swift")
route = destination[destination.index('enum RouteRefreshPolicy {')..]
first = location.index('struct LocationEnergyPolicy {') or abort 'Missing energy policy'
last = location.index('/// 樓層慣例標註小膠囊', first) or abort 'Missing policy boundary'
File.write("#{directory}/Policies.swift", "import Foundation\nimport CoreLocation\n" + route + location[first...last])
abort 'Compilation failed' unless system('swiftc', '-module-cache-path', '/private/tmp/gorilla-swift-test-cache',
  "#{directory}/Policies.swift", "#{repo}/Tests/EnergyPolicyChecks.swift", '-o', "#{directory}/checks")
abort 'Tests failed' unless system("#{directory}/checks")
