require 'fileutils'
repo = File.expand_path('..', __dir__)
source = File.read("#{repo}/GorillaTranslate/ContentView.swift")
phase = source[source.index('struct ParkingPreviewBreathingPhase {')...source.index('private struct ParkingPreviewBreathingIcon:')]
root = '/private/tmp/gorilla-camera-breathing-checks'
FileUtils.mkdir_p(root)
File.write("#{root}/Checks.swift", "import Foundation\n" + phase + <<~SWIFT)
  precondition(ParkingPreviewBreathingPhase.period == 3)
  precondition(abs(ParkingPreviewBreathingPhase.scale(at: 0) - 1.28) < 0.000001)
  precondition(abs(ParkingPreviewBreathingPhase.scale(at: 1.5) - 1.5) < 0.000001)
  for i in 0...300 {
      let time = Double(i) / 100
      let scale = ParkingPreviewBreathingPhase.scale(at: time)
      precondition(scale >= 1.28 - 0.000001 && scale <= 1.5 + 0.000001)
      precondition(abs(scale - ParkingPreviewBreathingPhase.scale(at: time + 3)) < 0.000001)
      precondition(abs(ParkingPreviewBreathingPhase.opacity(at: time) - (0.45 + (scale - 1.28) / 0.22 * 0.25)) < 0.000001)
  }
  for i in 1...150 {
      let time = Double(i) / 100
      precondition(ParkingPreviewBreathingPhase.scale(at: time) > ParkingPreviewBreathingPhase.scale(at: time - 0.01))
      precondition(ParkingPreviewBreathingPhase.scale(at: time + 1.5) < ParkingPreviewBreathingPhase.scale(at: time + 1.49))
  }
  print("PASS: continuous three-second breathing, preserved minimum, reduced maximum and synchronized opacity")
SWIFT
abort 'Compile failed' unless system('swiftc', '-module-cache-path', '/private/tmp/gorilla-swift-test-cache', "#{root}/Checks.swift", '-o', "#{root}/checks")
abort 'Checks failed' unless system("#{root}/checks")
