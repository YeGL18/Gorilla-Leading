require 'fileutils'

repo = File.expand_path('..', __dir__)
source = File.read("#{repo}/GorillaTranslate/Models/LocationManager.swift")
first = source.index('struct ParkingPointMeterAnnotation {') or abort 'Missing meter annotation model'
last = source.index("\n}", first) or abort 'Missing meter annotation boundary'
directory = '/private/tmp/gorilla-meter-notice-tests'
FileUtils.mkdir_p(directory)
File.write("#{directory}/Annotation.swift", "import CoreLocation\n" + source[first..last + 1] + "\n")
abort 'Compilation failed' unless system('swiftc', '-module-cache-path', '/private/tmp/gorilla-swift-test-cache',
  "#{directory}/Annotation.swift", "#{repo}/GorillaTranslate/Models/MeterData.swift",
  "#{repo}/GorillaTranslate/Models/ParkingMeterManager.swift", "#{repo}/Tests/MeterNoticeChecks.swift",
  '-o', "#{directory}/checks")
abort 'Tests failed' unless system("#{directory}/checks")
