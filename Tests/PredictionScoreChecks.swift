import Foundation
import CoreLocation

@main
struct PredictionScoreChecks {
    static func main() {
        let home = PlaceInfo(key: "home", kind: .addressCluster, displayName: "Lake Silver",
            latitude: 22.430, longitude: 114.243, updatedAt: Date())
        let duplicate = PlaceInfo(key: "duplicate", kind: .addressCluster, displayName: "銀湖·天峰",
            latitude: 22.4301, longitude: 114.2431, updatedAt: Date())
        let other = PlaceInfo(key: "other", kind: .addressCluster, displayName: "Other",
            latitude: 22.390, longitude: 114.230, updatedAt: Date())
        precondition(home.isSameLocation(as: duplicate))
        precondition(!home.isSameLocation(as: other))
        precondition(home.contains(duplicate.coordinate))
        let predictionTime = Date(timeIntervalSince1970: 1_000_000)
        let predictionKey = TripPatternKey(fromKey: home.key,
            weekday: Calendar.current.component(.weekday, from: predictionTime),
            timeSlot: TripTimeSlot(date: predictionTime), twoGramFromFromKey: nil)
        let fixture = PredictionFixture()
        fixture.placeCatalog = [home.key: home, duplicate.key: duplicate, other.key: other]
        fixture.patterns[fixture.patternID(predictionKey)] = TripPatternRecord(key: predictionKey,
            candidates: [duplicate.key: TripNextCandidate(toPlaceKey: duplicate.key,
                hitCount: 1, correctFeedbackCount: 0, denyCount: 0)],
            createdAt: predictionTime, updatedAt: predictionTime)
        if case .ignore = fixture.predictNext(currentPlace: home, atDate: predictionTime) { }
        else { preconditionFailure("The origin's alias must not become a destination") }
        fixture.patterns[fixture.patternID(predictionKey)]!.candidates[other.key] =
            TripNextCandidate(toPlaceKey: other.key, hitCount: 1, correctFeedbackCount: 0, denyCount: 0)
        if case .askConfirm(let destination, _, _, _) = fixture.predictNext(currentPlace: home, atDate: predictionTime) {
            precondition(destination.key == other.key)
        } else { preconditionFailure("A valid different destination must remain eligible") }
        if case .ignore = fixture.predictNext(currentPlace: home, atDate: predictionTime,
                                              currentCoordinate: other.coordinate) { }
        else { preconditionFailure("Never predict the place where the user already is") }
        precondition(fixture.pendingConfirm == nil && fixture.pendingToast == nil)
        let key = TripPatternKey(fromKey: "home", weekday: 2, timeSlot: .afternoon, twoGramFromFromKey: nil)
        let first = TripNextCandidate(toPlaceKey: "office", hitCount: 1, correctFeedbackCount: 0, denyCount: 0)
        var record = TripPatternRecord(key: key, candidates: ["office": first], createdAt: Date(), updatedAt: Date())
        precondition(record.totalSamples == 1 && record.confidence(for: first) == 1)
        let alternative = TripNextCandidate(toPlaceKey: "other", hitCount: 2, correctFeedbackCount: 0, denyCount: 0)
        record.candidates["other"] = alternative
        precondition(abs(record.confidence(for: first) - 1.0 / 3) < 0.0001)
        let denied = TripNextCandidate(toPlaceKey: "office", hitCount: 1, correctFeedbackCount: 0, denyCount: 1)
        record.candidates["office"] = denied
        precondition(record.confidence(for: denied) == 0)
        let corrected = TripNextCandidate(toPlaceKey: "office", hitCount: 1, correctFeedbackCount: 1, denyCount: 0)
        record.candidates["office"] = corrected
        precondition(abs(record.confidence(for: corrected) - 2.2 / 4.2) < 0.0001)
        record.candidates = ["office": denied]
        precondition(record.totalEffectiveScore == 0 && record.confidence(for: denied) == 0)
        print("PASS: one sample = 100%, competing destinations, feedback weights and zero scores")
        let predictor = TripPredictor.shared
        let start = Date(timeIntervalSince1970: 1_000_000)
        let origin = LocationManager.VisitRecord(id: UUID(), address: "A", latitude: 22.3, longitude: 114.1,
            arrivalDate: start, transportType: "Walking", isAutomotive: false)
        let departure = start.addingTimeInterval(300)
        predictor.predictDrivingDeparture(from: origin, at: departure)
        predictor.predictDrivingDeparture(from: origin, at: departure.addingTimeInterval(30))
        precondition(predictor.predictions == 1)
        precondition(predictor.observedDrivingDeparture(for: origin, before: departure) == nil)
        precondition(predictor.observedDrivingDeparture(for: origin, before: departure.addingTimeInterval(1)) == departure)
        let manager = LocationManager()
        let destination = LocationManager.VisitRecord(id: UUID(), address: "B", latitude: 22.4, longitude: 114.2,
            arrivalDate: start.addingTimeInterval(900), transportType: "Driving")
        manager.visits = [destination, origin]
        manager.learnAvailableTrips()
        precondition(predictor.learned.count == 1 && predictor.learned[0].date == departure)
        precondition(manager.visits.allSatisfy { $0.departureDate == nil })
        let restarted = LocationManager()
        restarted.visits = manager.visits
        restarted.learnedDepartureVisits = Set((manager.testDefaults.stringArray(forKey: manager.learnedTripsKey) ?? []).compactMap(UUID.init(uuidString:)))
        restarted.learnAvailableTrips()
        precondition(predictor.learned.count == 1)
        let later = LocationManager.VisitRecord(id: UUID(), address: "C", latitude: 22.5, longitude: 114.3,
            arrivalDate: start.addingTimeInterval(2000), transportType: "Driving")
        manager.visits.insert(later, at: 0)
        manager.learnAvailableTrips()
        precondition(predictor.learned.count == 1)
        manager.visits[1].departureDate = start.addingTimeInterval(1400)
        manager.learnAvailableTrips()
        precondition(predictor.learned.count == 2 && predictor.learned[1].from == "B" && predictor.learned[1].to == "C")
        print("PASS: non-driving arrival can trigger driving prediction, no stoplight repeats, observed departure survives, arrival learning, persistent dedup and late native departure retry")
        predictor.pendingConfirm = 1
        predictor.postponeDeparturePrediction()
        precondition(predictor.observedDrivingDeparture(for: origin, before: destination.arrivalDate) == nil)
        predictor.predictDrivingDeparture(from: origin, at: departure.addingTimeInterval(60))
        precondition(predictor.predictions == 2, "Postponing allows the later real departure to try again")
    }
}
