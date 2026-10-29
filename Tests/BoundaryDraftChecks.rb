require 'fileutils'
repo = File.expand_path('..', __dir__)
source = File.read("#{repo}/GorillaTranslate/ContentView.swift")
callbacks = source[source.index('        boundaryDrawBridge.onVertexMove = {')...source.index('        boundaryDrawBridge.initialFocus = (lot.centerCoordinate')]
callbacks = callbacks.gsub('= { index, coordinate in', '= { [self] index, coordinate in')
undo = source[source.index('    private func undoBoundaryEdit()')...source.index('    /// 「加點」：')].sub('private func', 'func')
root = '/private/tmp/gorilla-boundary-draft-checks'
FileUtils.mkdir_p(root)
File.write("#{root}/Checks.swift", <<~SWIFT)
  import Foundation
  struct Coordinate { var latitude: Double; var longitude: Double }
  struct ParkingBoundaryVertex: Equatable { var latitude: Double; var longitude: Double }
  final class Bridge {
      var sessionID = UUID()
      var isReady = true
      var isDraggingVertex = false
      var onVertexMove: ((Int, Coordinate) -> Void)?
      var onVertexInsert: ((Int, Coordinate) -> Void)?
  }
  final class Draft {
      var boundaryDrawBridge = Bridge()
      var boundaryDrawLot: Int? = 1
      var boundaryDrawVertices: [ParkingBoundaryVertex] = []
      var boundaryDrawUndoHistory: [[ParkingBoundaryVertex]] = []
      func activate() {
          let sessionID = boundaryDrawBridge.sessionID
          #{callbacks}
      }
      #{undo}
  }
  let draft = Draft()
  let original = (0..<4).map { ParkingBoundaryVertex(latitude: Double($0), longitude: 0) }
  draft.boundaryDrawVertices = original
  draft.activate()
  draft.boundaryDrawBridge.onVertexInsert?(1, Coordinate(latitude: 0.5, longitude: 0))
  precondition(draft.boundaryDrawVertices.count == 5 && draft.boundaryDrawVertices[1].latitude == 0.5)
  draft.undoBoundaryEdit()
  precondition(draft.boundaryDrawVertices == original, "Undo must remove the inserted edge point, not the last corner")
  draft.boundaryDrawBridge.onVertexMove?(2, Coordinate(latitude: 9, longitude: 9))
  draft.boundaryDrawBridge.isDraggingVertex = true
  draft.undoBoundaryEdit()
  precondition(draft.boundaryDrawVertices[2].latitude == 9, "Undo must be disabled during a drag")
  draft.boundaryDrawBridge.isDraggingVertex = false
  draft.undoBoundaryEdit()
  precondition(draft.boundaryDrawVertices == original)
  draft.boundaryDrawVertices = Array(repeating: original[0], count: 24)
  draft.boundaryDrawBridge.onVertexInsert?(1, Coordinate(latitude: 1, longitude: 1))
  precondition(draft.boundaryDrawVertices.count == 24 && draft.boundaryDrawUndoHistory.isEmpty)
  draft.boundaryDrawVertices = original
  draft.boundaryDrawBridge.sessionID = UUID()
  draft.boundaryDrawBridge.onVertexInsert?(1, Coordinate(latitude: 1, longitude: 1))
  precondition(draft.boundaryDrawVertices == original, "An old editing session must not insert a vertex")
  print("PASS: edge insertion order, move/insert undo, drag lock, 24-point limit and stale-session rejection")
SWIFT
abort 'Compile failed' unless system('swiftc', '-module-cache-path', '/private/tmp/gorilla-swift-test-cache', "#{root}/Checks.swift", '-o', "#{root}/checks")
abort 'Checks failed' unless system("#{root}/checks")
