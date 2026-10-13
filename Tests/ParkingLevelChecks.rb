require 'fileutils'

repo = File.expand_path('..', __dir__)
source = File.read("#{repo}/GorillaTranslate/Models/LocationManager.swift")
def section(source, first, last)
  start = source.index(first) or abort "Missing #{first}"
  finish = source.index(last, start) or abort "Missing #{last}"
  source[start...finish]
end

points = section(source, 'struct ParkingPointRecord:', '// MARK: - GCJ-02 Coordinate Transformation')
store = section(source, 'enum ParkingFloorMode:', '/// 樓層慣例標註小膠囊')
manager = section(source, 'struct BarometerSample:', '    struct WindowResult {') + "}\n"
visit = section(source, '    struct VisitRecord:', '    @Published var speed:')
native_event = section(source, 'struct NativeVisitEvent:', '// MARK: - Kalman')
suite = "gorilla.parking-level-tests.#{Process.pid}"
models = points + store + manager
models.gsub!('group.com.gorilla.translate', suite)
models.gsub!('UserDefaults.standard', 'TestDefaults.standard')
models.gsub!('Date()', 'TestClock.now')
models.gsub!('ProcessInfo.processInfo.systemUptime', 'TestClock.uptime')
# Tests use the real storage implementation, but never write the user's Documents backup.
models.sub!(/private var backupFileURL: URL\? \{.*?\n    \}/m, 'private var backupFileURL: URL? { nil }')
fixtures = File.read("#{repo}/Tests/ParkingSessionFixtures.swift") + <<~SWIFT
  enum TestDefaults {
    static let standard = UserDefaults(suiteName: "#{suite}")!
  }
  struct PlaceInfo: Codable, Hashable {
    var key = "test"; var displayName = "Test"; var latitude = 22.3; var longitude = 114.17
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
  }
  final class TripPredictor {
    static let shared = TripPredictor()
    func reconcilePlaceNames(with lots: [ParkingLotRecord]) {}
    func resolvePlace(coordinate: CLLocationCoordinate2D, address: String, parkingLots: [ParkingLotRecord]) -> PlaceInfo { PlaceInfo() }
    func renameLotPlace(lotID: UUID, newName: String) {}
    func syncClusterName(nearLatitude: Double, longitude: Double, newName: String?) {}
    func removePlace(key: String) {}
    func restorePlace(_ place: PlaceInfo) {}
  }
  class LocationManager {
  #{visit}
  }
SWIFT
directory = '/private/tmp/gorilla-parking-level-tests'
FileUtils.mkdir_p(directory)
File.write("#{directory}/Models.swift", "import Foundation\nimport CoreLocation\nimport Combine\n#{native_event}\n#{fixtures}\n#{models}")
abort 'Compilation failed' unless system('swiftc', '-module-cache-path', '/private/tmp/gorilla-swift-test-cache',
  "#{directory}/Models.swift", "#{repo}/Tests/ParkingLevelChecks.swift", '-o', "#{directory}/checks")
abort 'Tests failed' unless system("#{directory}/checks", suite)
