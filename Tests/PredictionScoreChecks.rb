require 'fileutils'
root = File.expand_path('..', __dir__)
source = File.read("#{root}/GorillaTranslate/Models/TripPredictor.swift")
def section(source, first, last)
  start = source.index(first) or abort "Missing #{first}"
  finish = source.index(last, start) or abort "Missing #{last}"
  source[start...finish]
end
models = "import Foundation\nimport CoreLocation\n" +
  section(source, 'enum TripTimeSlot:', '// MARK: - PlaceKind') +
  section(source, 'enum PlaceKind:', '// MARK: - TripPatternKey') +
  section(source, 'struct TripPatternKey:', '// MARK: - TripPredictionLevel')
models += section(source, 'enum TripPredictionAction:', '// MARK: - TripPredictor (main ObservableObject)')
prediction = section(source, '    func predictNext(', '    /// User 對 confirm sheet')
models += <<~SWIFT
  final class PredictionFixture {
    var patterns: [String: TripPatternRecord] = [:]
    var placeCatalog: [String: PlaceInfo] = [:]
    var recentPlaceHistory: [PlaceInfo] = []
    var pendingConfirm: PendingTripPrediction?
    var pendingToast: PendingTripPrediction?
    var lastPredictionSummary = ""
    func patternID(_ key: TripPatternKey) -> String {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      return (try! encoder.encode(key)).base64EncodedString()
    }
    func upsertPlaceInCatalog(_ place: PlaceInfo) { placeCatalog[place.key] = place }
    #{prediction}
  }
SWIFT
location = File.read("#{root}/GorillaTranslate/Models/LocationManager.swift")
departures = section(source, '    func predictDrivingDeparture(', '    /// 有 CLVisit')
learning = section(location, "    @MainActor\n    private func learnAvailableTrips()", '    func locationManagerDidChangeAuthorization(')
learning = learning.sub('@MainActor', '').sub('private func', 'func').gsub('UserDefaults.standard', 'testDefaults')
record = section(location, '    struct VisitRecord:', '    @Published var speed:')
native = section(location, 'struct NativeVisitEvent:', '// MARK: - Kalman')
models += <<~SWIFT
  import CoreLocation
  #{native}
  final class UIApplication {
    static let shared = UIApplication()
    var isProtectedDataAvailable = true
  }
  final class ParkingFloorStore {
    static let shared = ParkingFloorStore()
    func resolvePlace(coordinate: CLLocationCoordinate2D, address: String) -> String { address }
  }
  final class TripPredictor {
    static let shared = TripPredictor()
    let testDefaults = UserDefaults(suiteName: "gorilla-prediction-test-" + UUID().uuidString)!
    var pendingConfirm: Int?
    var pendingToast: Int?
    var predictions = 0
    var learned: [(from: String, to: String, date: Date)] = []
    func predictNext(currentPlace: String, atDate: Date, currentCoordinate: CLLocationCoordinate2D? = nil) -> Int { predictions += 1; return 0 }
    func recordLearning(fromPlace: String, toPlace: String, atDate: Date) {
      learned.append((fromPlace, toPlace, atDate))
    }
    #{departures.gsub('UserDefaults.standard', 'testDefaults')}
  }
  final class LocationManager {
    #{record}
    let testDefaults = UserDefaults(suiteName: "gorilla-learning-test-" + UUID().uuidString)!
    let learnedTripsKey = "learned"
    var visits: [VisitRecord] = []
    var learnedDepartureVisits: Set<UUID> = []
    #{learning}
  }
SWIFT
path = '/private/tmp/gorilla-prediction-score-checks'
FileUtils.mkdir_p(path)
File.write("#{path}/Models.swift", models)
abort 'Compile failed' unless system('swiftc', '-module-cache-path', '/private/tmp/gorilla-swift-test-cache',
  "#{path}/Models.swift", "#{root}/Tests/PredictionScoreChecks.swift", '-o', "#{path}/checks")
abort 'Checks failed' unless system("#{path}/checks")
content = File.read("#{root}/GorillaTranslate/ContentView.swift")
abort 'Missing driving triggers' unless content.scan('predictDestinationOnDriving()').count == 3
abort 'Arrival still predicts' if location.include?('predictNext(')
abort 'Feedback lost origin pattern' unless source.include?('var targetKey: TripPatternKey? = prediction.patternKey')
abort 'Wrong training timestamp' unless location.include?('atDate: departure')
abort 'Missing observed departure fallback' unless location.include?('observedDrivingDeparture(for: fv, before: latest.arrivalDate)')
puts 'PASS: driving and pre-departure hooks, no arrival prediction, fixed feedback context'
