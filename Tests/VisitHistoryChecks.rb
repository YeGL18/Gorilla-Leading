require 'fileutils'

source = File.read(File.expand_path('../GorillaTranslate/Models/LocationManager.swift', __dir__))
def section(source, first, last)
  start = source.index(first) or abort "Missing #{first}"
  finish = source.index(last, start) or abort "Missing #{last}"
  source[start...finish]
end

record = section(source, '    struct VisitRecord:', '    @Published var speed:')
dedupe = section(source, '    private func dedupeVisits(', '    func clearVisits(').sub('private func', 'func')
later = section(source, '    private static func laterDate(', '    private func trimAndSaveMotionSegments(')
append = section(source, '    private func appendSegment(', '    private static func laterDate(').sub('private func', 'func')
timeline = section(source, '    func tripTimeline(', '    /// 「全程揸車先算」')
segment = section(source, 'struct MotionSegment:', 'struct ParkingPointRecord:')
name = section(source, '    func displayName(for visit:', '    func clearAll()')
session = section(source, '    var currentPoint:', '    /// 更新活躍停車點')
snapshot = section(source, 'struct ParkingSessionSnapshot {', 'final class ParkingFloorStore:')
points = section(source, '    var allPoints:', '    var mapPoints:')
fixtures = <<~SWIFT
  struct PointFixture {
    var latitude: Double; var longitude: Double; var createdAt: Date; var address: String
    var id = UUID(); var llmFloorText: String?; var displayFloor: String?
    var manualFloorIndex: Int?; var predictedFloorIndex: Int?
    var llmSpotNumber: String?; var llmAreaCode: String?
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
  }
  typealias ParkingPointRecord = PointFixture
  struct LotFixture {
    var preferredDisplayName: String?; var radiusMeters: Double; var points: [PointFixture]; var id = UUID()
    var name: String? { preferredDisplayName }
    func displayName(for point: PointFixture, mode: Int) -> String? { preferredDisplayName }
  }
  #{snapshot}
  class ParkingFloorStore {
    var floorMode = 0
    var lots: [LotFixture] = [] { didSet { cachedPoints = nil } }
    var cachedPoints: [ParkingPointRecord]?; var activeLotID: UUID?
    func lot(containing id: UUID) -> LotFixture? { lots.first { $0.points.contains { $0.id == id } } }
    static func cleanFloorText(_ text: String?, coordinate: CLLocationCoordinate2D) -> String? { text }
  #{points}
  #{session}
  #{name}
  }
SWIFT
generated = "import Foundation\nimport CoreLocation\nclass LocationManager {\n#{record}\nvar motionSegments: [MotionSegment] = []\n#{dedupe}\n#{later}\n#{append}\n#{timeline}\n}\n#{segment}\n#{fixtures}"
directory = '/private/tmp/gorilla-visit-history-tests'
FileUtils.mkdir_p(directory)
File.write("#{directory}/Models.swift", generated)
checks = File.expand_path('VisitHistoryChecks.swift', __dir__)
abort 'Compilation failed' unless system('swiftc', '-module-cache-path', '/private/tmp/gorilla-swift-test-cache', "#{directory}/Models.swift", checks, '-o', "#{directory}/checks")
abort 'Tests failed' unless system("#{directory}/checks")
