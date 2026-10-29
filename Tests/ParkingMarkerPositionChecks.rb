require 'fileutils'

repo = File.expand_path('..', __dir__)
map = File.read("#{repo}/GorillaTranslate/Views/MapView.swift")
model = File.read("#{repo}/GorillaTranslate/Models/LocationManager.swift")
abort 'Neighbour separation returned' if map.include?('displayOffset') || model.include?('enum ParkingLevelLayout')
start = map.index('        private func configureParkingMarker(') or abort 'Missing marker configuration'
finish = map.index('        func applyParkingSelection(', start) or abort 'Missing selection method'
configure = map[start...finish].sub('private func', 'func')
root = '/private/tmp/gorilla-marker-position-checks'
FileUtils.mkdir_p(root)
File.write("#{root}/Checks.swift", <<~SWIFT)
  import Foundation
  import CoreGraphics
  enum UIColor { case systemOrange, systemTeal }
  enum Priority { case required, defaultHigh }
  final class ParkingPointAnnotation {
      var isAutomotive = true, isLatest = false
      var recordCount = 1
      var title: String?, subtitle: String?
  }
  final class ParkingRecordMarkerView {
      var canShowCallout = true, isDraggable = true, isHolding = false
      var centerOffset = CGPoint.zero
      var displayPriority = Priority.defaultHigh
      var sizeScale: CGFloat = 1
      func configure(tint: UIColor, glyph: String, title: String?, subtitle: String?, scale: CGFloat) {}
  }
  struct Coordinator {
  #{configure}
  }
  let coordinator = Coordinator()
  for previousOffset in [-96.0, -48, 0, 48, 96] {
      for automotive in [true, false] {
          let annotation = ParkingPointAnnotation()
          annotation.isAutomotive = automotive
          let view = ParkingRecordMarkerView()
          view.centerOffset = CGPoint(x: previousOffset, y: -22)
          for latest in [false, true] {
              annotation.isLatest = latest
              for holding in [false, true] {
                  view.isHolding = holding
                  for count in [1, 2, 10] {
                      annotation.recordCount = count
                      coordinator.configureParkingMarker(view, annotation: annotation)
                      precondition(view.centerOffset == CGPoint(x: 0, y: -22),
                                   "Reused, dragged and grouped markers must never spread sideways")
                      precondition(!view.isDraggable)
                  }
              }
          }
      }
  }
  print("PASS: 120 marker configurations preserve fixed anchoring across reuse, hold, group count and parking/stay type")
SWIFT
abort 'Compilation failed' unless system('swiftc', '-module-cache-path', '/private/tmp/gorilla-swift-test-cache', "#{root}/Checks.swift", '-o', "#{root}/checks")
abort 'Tests failed' unless system("#{root}/checks")
