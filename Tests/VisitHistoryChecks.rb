require 'fileutils'

source = File.read(File.expand_path('../GorillaTranslate/Models/LocationManager.swift', __dir__))
def section(source, first, last)
  start = source.index(first) or abort "Missing #{first}"
  finish = source.index(last, start) or abort "Missing #{last}"
  source[start...finish]
end

record = section(source, '    struct VisitRecord:', '    @Published var speed:')
native_event = section(source, 'struct NativeVisitEvent:', '// MARK: - Kalman')
dedupe = section(source, '    private func dedupeVisits(', '    func clearVisits(').sub('private func', 'func')
later = section(source, '    private static func laterDate(', '    private func trimAndSaveMotionSegments(')
append = section(source, '    private func appendSegment(', '    private static func laterDate(').sub('private func', 'func')
timeline = section(source, '    func tripTimeline(', '    /// Stable pedestrian/cycling')
moving = section(source, '    func tripSegments(', '    /// A complete,')
classification = section(source, '    func classifyTrip(', '    private func transportTypeFromSpeed(').gsub('private func', 'func')
policy = section(source, 'struct VisitTimelineRules:', '/// CMMotionActivity 交通模式分段')
segment = section(source, 'struct MotionSegment:', 'struct ParkingPointRecord:')
name = section(source, '    func displayName(for visit:', '    func clearAll()')
session = section(source, '    var currentPoint:', '    /// 更新活躍停車點')
snapshot = section(source, 'struct ParkingSessionSnapshot {', 'final class ParkingFloorStore:')
points = section(source, '    var allPoints:', '    var mapPoints:')
batch_flags = section(source, '    func updateAutomotiveFlags(', '    func recordParkingPoint(')
motion_persistence = section(source, '    private func trimAndSaveMotionSegments(', '    /// 重啟後回填')
  .gsub('private func', 'func').gsub('UserDefaults.standard', 'motionPreferences')
fixtures = <<~SWIFT
  struct PointFixture {
    var latitude: Double; var longitude: Double; var createdAt: Date; var address: String
    var id = UUID(); var isAutomotive = true; var llmFloorText: String?; var displayFloor: String?
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
    static let shared = ParkingFloorStore()
    var floorMode = 0
    var lots: [LotFixture] = [] { didSet { cachedPoints = nil } }
    var cachedPoints: [ParkingPointRecord]?; var activeLotID: UUID?
    func lot(containing id: UUID) -> LotFixture? { lots.first { $0.points.contains { $0.id == id } } }
    static func cleanFloorText(_ text: String?, coordinate: CLLocationCoordinate2D) -> String? { text }
    func updateAutomotiveFlag(createdAt: Date, isAutomotive: Bool) {
      for i in lots.indices {
        for j in lots[i].points.indices where abs(lots[i].points[j].createdAt.timeIntervalSince(createdAt)) < 60 {
          lots[i].points[j].isAutomotive = isAutomotive
        }
      }
      cachedPoints = nil
    }
    var persistCount = 0
    func persist() { persistCount += 1 }
  #{batch_flags}
  #{points}
  #{session}
  #{name}
  }
SWIFT
preferences = <<~SWIFT
  final class MotionPreferencesFixture {
    var values: [String: Data] = [:]
    func data(forKey key: String) -> Data? { values[key] }
    func set(_ data: Data, forKey key: String) { values[key] = data }
  }
SWIFT
generated = "import Foundation\nimport CoreLocation\n#{preferences}\n#{native_event}\nclass LocationManager {\n#{record}\nvar motionSegments: [MotionSegment] = []\nvar visits: [VisitRecord] = []\nvar motionHistoryFrom: Date?\nvar motionHistoryThrough: Date?\nlet motionPreferences = MotionPreferencesFixture()\nlet motionSegmentsKey = \"motion_segments\"\nfunc saveVisits() {}\n@MainActor func learnAvailableTrips() {}\n#{motion_persistence}\n#{dedupe}\n#{later}\n#{append}\n#{timeline}\n#{moving}\n#{classification}\n}\n#{policy}\n#{segment}\n#{fixtures}"
directory = '/private/tmp/gorilla-visit-history-tests'
FileUtils.mkdir_p(directory)
File.write("#{directory}/Models.swift", generated)
checks = File.expand_path('VisitHistoryChecks.swift', __dir__)
abort 'Compilation failed' unless system('swiftc', '-module-cache-path', '/private/tmp/gorilla-swift-test-cache', "#{directory}/Models.swift", checks, '-o', "#{directory}/checks")
abort 'Tests failed' unless system("#{directory}/checks")
