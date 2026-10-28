require 'fileutils'
repo = File.expand_path('..', __dir__)
source = File.read("#{repo}/GorillaTranslate/ContentView.swift")
geometry = source[source.index('struct AddressCapsuleDragGeometry {')...source.index('struct ParkingPreviewBreathingPhase {')]
next_slot = source[source.index('    private func nextCompactSlot()')...source.index('    /// 每格時長')].sub('private func', 'func')
advance = source[source.index('    private func advanceCompactSlot()')...source.index('    private func nextCompactSlot()')].sub('private func', 'func')
root = '/private/tmp/gorilla-address-capsule-checks'
FileUtils.mkdir_p(root)
File.write("#{root}/Checks.swift", "import Foundation\n" + geometry + <<~SWIFT)
  struct TestAnimation {
      static func timingCurve(_ a: Double, _ b: Double, _ c: Double, _ d: Double, duration: Double) -> Self { Self() }
  }
  func withAnimation(_ animation: TestAnimation, _ body: () -> Void) { body() }
  final class Carousel {
      enum CompactSlot { case speed, address, status }
      var compactSlot: CompactSlot = .speed
      var isCapsuleExpanded = false
      var isParkingMemoryExpanded = false
      var scheduled = 0
      var addressRestarts = 0
      func scheduleCompactSlot() { scheduled += 1 }
      func startAddressAlternatingIfNeeded(force: Bool) { precondition(force); addressRestarts += 1 }
      #{next_slot}
      #{advance}
  }
  for offset in 0...200 {
      precondition(AddressCapsuleDragGeometry.height(expanded: true, direction: -1, offset: CGFloat(offset)) >= 182)
      precondition(AddressCapsuleDragGeometry.height(expanded: false, direction: -1, offset: CGFloat(offset)) <= 182)
  }
  precondition(AddressCapsuleDragGeometry.height(expanded: true, direction: 1, offset: 138) == 44)
  let carousel = Carousel()
  carousel.advanceCompactSlot()
  precondition(carousel.compactSlot == .address && carousel.addressRestarts == 1 && carousel.scheduled == 1)
  carousel.advanceCompactSlot()
  precondition(carousel.compactSlot == .status && carousel.scheduled == 2)
  carousel.advanceCompactSlot()
  precondition(carousel.compactSlot == .speed && carousel.scheduled == 3)
  carousel.isCapsuleExpanded = true
  carousel.advanceCompactSlot()
  precondition(carousel.compactSlot == .speed && carousel.scheduled == 3)
  carousel.isCapsuleExpanded = false
  carousel.isParkingMemoryExpanded = true
  carousel.advanceCompactSlot()
  precondition(carousel.compactSlot == .speed && carousel.scheduled == 3)
  print("PASS: expanded upward rubber-band geometry; manual/automatic carousel cycle, timer rescheduling and expanded-state guards")
SWIFT
abort 'Compile failed' unless system('swiftc', '-module-cache-path', '/private/tmp/gorilla-swift-test-cache', "#{root}/Checks.swift", '-o', "#{root}/checks")
abort 'Checks failed' unless system("#{root}/checks")
