import SwiftUI
import CoreMotion

struct TripReplayCapture: View {
    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.scenePhase) private var phase
    @ObservedObject var telemetry: ACTelemetry
    var driving = false
    @ObservedObject private var destinations = DestinationManager.shared
    @ObservedObject private var parking = ParkingFloorStore.shared
    @ObservedObject private var predictor = TripPredictor.shared
    private let store = TripReplayStore.shared

    var body: some View {
        Color.clear
            .onAppear { updateContext(); store.setDriving(driving); updateVisits(locationManager.visits) }
            .onChange(of: driving) { _, value in store.setDriving(value) }
            .onChange(of: phase) { _, _ in updateContext() }
            .onChange(of: telemetry.isReceiving) { _, _ in updateContext() }
            .onDisappear { store.setContext(foreground: false, game: false) }
            .onReceive(locationManager.$lastLocation) { location in
                guard let location else { return }
                store.setDriving(driving)
                let motion = locationManager.currentMotionActivity
                let fresh = motion.map { $0.confidence != .low } ?? false
                store.record(location, automotive: fresh && motion?.automotive == true,
                    pedestrian: fresh && (motion?.walking == true || motion?.running == true || motion?.cycling == true))
            }
            .onReceive(locationManager.$visits, perform: updateVisits)
            .onReceive(destinations.$destinations) { _ in Task { @MainActor in updatePlaces() } }
            .onReceive(parking.$lots) { _ in Task { @MainActor in updatePlaces(); updateVisits(locationManager.visits) } }
            .onReceive(predictor.$placeCatalog) { _ in Task { @MainActor in updatePlaces(); updateVisits(locationManager.visits) } }
            .onReceive(predictor.$pendingConfirm) { value in notePrediction(value) }
            .onReceive(predictor.$pendingToast) { value in notePrediction(value) }
            .task(id: phase) {
                guard phase == .active else { return }
                while !Task.isCancelled {
                    // A candidate can qualify without another native callback.
                    updateVisits(locationManager.visits)
                    updatePlaces()
                    do { try await Task.sleep(for: .seconds(60)) } catch { return }
                }
            }
    }

    private func updateContext() { store.setContext(foreground: phase == .active, game: telemetry.isReceiving) }
    private func notePrediction(_ value: PendingTripPrediction?) {
        guard let value else { return }
        store.notePrediction(.init(createdAt: value.createdAt,
                                   latitude: value.predicted.latitude, longitude: value.predicted.longitude))
    }
    private func updatePlaces() {
        let lots = parking.lots.compactMap { lot -> TripReplayPlace? in
            guard let name = lot.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
            return TripReplayPlace(name: name, latitude: lot.centerLatitude, longitude: lot.centerLongitude,
                                   radius: min(250, lot.radiusMeters), priority: 0)
        }
        let saved = destinations.destinations.map {
            TripReplayPlace(name: $0.name, latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude,
                            radius: 100, priority: 1)
        }
        let learned = predictor.placeCatalog.values.sorted { $0.key < $1.key }.map {
            TripReplayPlace(name: $0.displayName, latitude: $0.latitude, longitude: $0.longitude,
                            radius: 180, priority: 2)
        }
        store.updatePlaces(lots + saved + learned)
    }
    private func updateVisits(_ visits: [LocationManager.VisitRecord]) {
        let defaults = UserDefaults.standard
        func number(_ key: String, _ fallback: Int) -> Int {
            defaults.object(forKey: key) == nil ? fallback : defaults.integer(forKey: key)
        }
        let rules = VisitTimelineRules(newPlaceMinutes: number("visitMinimumNewMinutes", 10),
            activePlaceMinutes: number("visitMinimumActiveMinutes", 10), activateMinutes: number("visitActivateMinutes", 15),
            radiusMeters: Double(number("visitMatchRadiusMeters", 100)),
            mergeConsecutive: defaults.object(forKey: "visitMergeConsecutive") as? Bool ?? true,
            mergeMinutes: number("visitMergeMinutes", 20), deactivateDays: number("visitDeactivateDays", 0))
        let accepted = VisitTimeline.make(visits, rules: rules, now: .now).map(\.record)
        store.link(visits: accepted.map {
            TripReplayVisit(id: $0.id, arrival: $0.arrivalDate, departure: $0.departureDate,
                latitude: $0.latitude, longitude: $0.longitude, name: parking.displayName(for: $0))
        })
    }
}
