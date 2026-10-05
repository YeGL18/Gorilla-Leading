require 'fileutils'

source = File.read(File.expand_path('../GorillaTranslate/Models/LocationManager.swift', __dir__))
first = source.index('struct BarometerSample:') or abort 'Missing capture model'
last = source.index('final class BarometerSessionManager:', first) or abort 'Missing capture manager'
directory = '/private/tmp/gorilla-parking-altitude-tests'
FileUtils.mkdir_p(directory)
File.write("#{directory}/Models.swift", "import Foundation\nimport CoreLocation\n" + source[first...last])
checks = File.expand_path('ParkingAltitudeChecks.swift', __dir__)
abort 'Compilation failed' unless system('swiftc', '-module-cache-path', '/private/tmp/gorilla-swift-test-cache', "#{directory}/Models.swift", checks, '-o', "#{directory}/checks")
abort 'Tests failed' unless system("#{directory}/checks")
