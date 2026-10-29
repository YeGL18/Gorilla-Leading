import Foundation
import CoreLocation
import Combine

@main
struct ParkingLevelChecks {
    static let coordinate = CLLocationCoordinate2D(latitude: 22.316, longitude: 114.18)

    static func point(_ floor: Int?, date: TimeInterval, delta: Double? = nil) -> ParkingPointRecord {
        ParkingPointRecord(id: UUID(), address: "Test", latitude: coordinate.latitude,
            longitude: coordinate.longitude, createdAt: TestClock.now.addingTimeInterval(date),
            predictedFloorIndex: floor, manualFloorIndex: floor,
            barometerAltitudeDeltaMeters: delta, barometerSampleCount: 40,
            barometerCalibrationEligible: delta != nil)
    }

    static func lot(_ points: [ParkingPointRecord]) -> ParkingLotRecord {
        ParkingLotRecord(id: UUID(), name: "Residence", centerLatitude: coordinate.latitude,
            centerLongitude: coordinate.longitude, radiusMeters: 180,
            createdAt: TestClock.now, updatedAt: TestClock.now, points: points)
    }

    static func freezeCapture(in store: ParkingFloorStore, floor: Int,
                              whileCapturing: (Date) -> Void = { _ in }) -> UUID {
        let manager = store.barometer
        let sensor = CMAltimeter.latest!
        manager.updateDriving(speed: 30, timestamp: TestClock.now, coordinate: coordinate)
        TestClock.now += 1
        TestClock.uptime += 1
        manager.updateDriving(speed: 10, timestamp: TestClock.now, coordinate: coordinate)
        for i in 0..<20 {
            TestClock.now += 1
            TestClock.uptime += 1
            manager.updateDriving(speed: i < 3 ? 10 : 0, timestamp: TestClock.now, coordinate: coordinate)
            sensor.emit(i < 3 ? 0 : Double(floor * 3))
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
            if i == 5 { whileCapturing(TestClock.now) }
        }
        let id = manager.captureID!
        if manager.completedResult == nil {
            precondition(manager.confirmParking(captureID: id, promptID: manager.stopConfirmationID!))
        }
        manager.setFloor(floor, userConfirmed: true, captureID: id)
        return id
    }

    static func main() throws {
        let suite = CommandLine.arguments[1]
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var stay = point(5, date: -1200, delta: 15)
        stay.isAutomotive = false
        stay.llmFloorText = "5/F"
        stay.floorConfirmedByUser = true
        precondition(stay.displayFloor == nil && stay.effectiveFloorIndex == nil && !stay.isFloorConfirmed)
        precondition(stay.floorStatusLabel.isEmpty)
        let stayLot = lot([stay])
        precondition(stayLot.displayName(for: stay, mode: .perVisit) == "Residence")
        stay.isAutomotive = true
        precondition(stay.displayFloor != nil && stay.effectiveFloorIndex == 5)

        let first = point(-3, date: -600, delta: -9)
        let second = point(-4, date: -300, delta: -12)
        var ground = point(0, date: -900, delta: 0)
        ground.predictedFloorIndex = 0
        var original = lot([first, second, ground])
        original.fixedFloorIndex = -3
        original.learnedMetersPerFloor = 3
        original.learnedOffsetMeters = 0
        original.floorLearningHistory = [first, second].map {
            ParkingLotFloorLearning(createdAt: $0.createdAt, manualFloorIndex: $0.manualFloorIndex!,
                altitudeDeltaMeters: $0.barometerAltitudeDeltaMeters!, metersPerFloor: 3,
                lotID: original.id, pointID: $0.id, calibrationEligible: true)
        }
        defaults.set(try JSONEncoder().encode([original]), forKey: "parking_floor_store_v1")
        let store = ParkingFloorStore()
        store.prepare()
        precondition(store.floorMode == .fixed)
        precondition(store.estimatedFloor(near: coordinate, delta: -12) == -3)
        store.setFloorMode(.perVisit)
        precondition(store.lots[0].points == original.points, "Changing mode altered history")
        precondition(store.estimatedFloor(near: coordinate, delta: -12) == -4)
        precondition(store.estimatedFloor(near: coordinate, delta: -3, referenceFloor: -3) == -4)
        store.setFloorName(lotID: original.id, floor: 0, name: "Drop-off")
        store.setFloorName(lotID: original.id, floor: -4, name: "Residents")
        precondition(store.lotNameByPointID[ground.id] == "Residence Drop-off")
        precondition(store.lotNameByPointID[second.id] == "Residence Residents")
        precondition(store.currentSession?.locationName == "Residence Residents")
        store.setManualFloor(pointID: first.id, floorIndex: -2)
        store.setManualFloor(pointID: first.id, floorIndex: -3)
        store.setManualFloor(pointID: second.id, floorIndex: -3)
        store.setManualFloor(pointID: second.id, floorIndex: -4)
        precondition(store.lots[0].floorLearningHistory?.count == 2, "A correction duplicated training")
        precondition(abs((store.lots[0].learnedMetersPerFloor ?? 0) - 3) < 0.0001)
        precondition(store.allPoints.first { $0.id == ground.id }?.predictedFloorIndex == 0)
        precondition(store.allPoints.first { $0.id == first.id }?.manualFloorIndex == -3)
        store.setFloorMode(.fixed)
        store.setFloorMode(.perVisit)
        precondition(store.lotNameByPointID[second.id] == "Residence Residents")
        let reload = ParkingFloorStore()
        reload.prepare()
        precondition(reload.floorMode == .perVisit && reload.lots == store.lots)

        var oldJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        oldJSON.removeValue(forKey: "fixedFloorIndex")
        oldJSON.removeValue(forKey: "floorNames")
        oldJSON.removeValue(forKey: "floorScopeIndex")
        oldJSON.removeValue(forKey: "boundaryVertices")
        let legacy = try JSONDecoder().decode(ParkingLotRecord.self,
            from: JSONSerialization.data(withJSONObject: oldJSON))
        precondition(legacy.points == original.points && legacy.floorNames == nil && legacy.boundaryVertices == nil)

        let closeGroups = ParkingRecordGroup.make(lots: [lot([ground, first])], mode: .perVisit)
        precondition(closeGroups.count == 2)
        for group in closeGroups {
            precondition(group.mapCoordinate.latitude == group.latest.latitude)
            precondition(group.mapCoordinate.longitude == group.latest.longitude,
                         "Nearby floors must keep their real map positions")
        }

        let groundLot = lot([ground])
        let undergroundLot = lot([first])
        defaults.set(try JSONEncoder().encode([groundLot, undergroundLot]), forKey: "parking_floor_store_v1")
        let split = ParkingFloorStore()
        split.prepare()
        split.setLotFloorScope(lotID: groundLot.id, floor: 0)
        split.setLotFloorScope(lotID: undergroundLot.id, floor: -3)
        precondition(split.findLotIndex(near: coordinate, radiusMeters: 180, floorIndex: 0)
            .map { split.lots[$0].id } == groundLot.id)
        precondition(split.findLotIndex(near: coordinate, radiusMeters: 180, floorIndex: -3)
            .map { split.lots[$0].id } == undergroundLot.id)
        precondition(split.findLotIndex(near: coordinate, radiusMeters: 180) == nil,
                     "Unknown floor must not choose arbitrarily between overlapping facilities")

        var wrong = ParkingLotFloorLearning(createdAt: TestClock.now, manualFloorIndex: -3,
            altitudeDeltaMeters: 9, metersPerFloor: -3, lotID: original.id, pointID: UUID(), calibrationEligible: true)
        precondition(ParkingFloorCalibration.learn([wrong]) == nil)
        wrong.altitudeDeltaMeters = -30
        precondition(ParkingFloorCalibration.learn([wrong]) == nil)
        let relative = ParkingLotFloorLearning(createdAt: TestClock.now, manualFloorIndex: -4,
            altitudeDeltaMeters: -3, metersPerFloor: 3, lotID: original.id, pointID: UUID(), referenceFloorIndex: -3,
            calibrationEligible: true)
        precondition(ParkingFloorCalibration.learn([relative])?.metersPerFloor == 3)
        let podium = [9.6, 9.7].map { height in
            ParkingLotFloorLearning(createdAt: TestClock.now, manualFloorIndex: 1,
                altitudeDeltaMeters: height, metersPerFloor: height, lotID: original.id,
                pointID: UUID(), calibrationEligible: true)
        }
        let excluded = ParkingLotFloorLearning(createdAt: TestClock.now, manualFloorIndex: 1,
            altitudeDeltaMeters: 2, metersPerFloor: 2, lotID: original.id, pointID: UUID())
        let profiles = ParkingFloorCalibration.profiles(podium + [excluded])
        precondition(profiles.count == 1 && profiles[0].count == 2)
        precondition(abs(profiles[0].height - 9.65) < 0.001, "Incomplete and legacy measurements must not dilute podium height")
        defaults.set(try JSONEncoder().encode([original]), forKey: "parking_floor_store_v1")
        let reviewStore = ParkingFloorStore()
        reviewStore.prepare()
        let captureID = freezeCapture(in: reviewStore, floor: -5)
        reviewStore.requestFloorReview(captureID: captureID)
        precondition(reviewStore.floorReview?.previousPointID == second.id)
        reviewStore.resolveFloorReview(correctPrevious: false)
        precondition(reviewStore.allPoints.first { $0.id == second.id }?.manualFloorIndex == -4)
        let nextCaptureID = freezeCapture(in: reviewStore, floor: -5)
        reviewStore.requestFloorReview(captureID: nextCaptureID)
        reviewStore.resolveFloorReview(correctPrevious: true)
        precondition(reviewStore.allPoints.first { $0.id == second.id }?.manualFloorIndex == -5)
        precondition(reviewStore.allPoints.first { $0.id == first.id }?.manualFloorIndex == -3)
        precondition(reviewStore.barometer.completedResult?.selectedFloor == -5)
        reviewStore.setReferenceFloor(pointID: second.id, floor: -1)
        precondition(reviewStore.allPoints.first { $0.id == second.id }?.barometerReferenceFloorIndex == -1)
        var scopedGround = groundLot
        var scopedUnderground = undergroundLot
        scopedGround.floorScopeIndex = 0
        scopedUnderground.floorScopeIndex = -3
        defaults.set(try JSONEncoder().encode([scopedGround, scopedUnderground]), forKey: "parking_floor_store_v1")
        let rematchStore = ParkingFloorStore()
        rematchStore.prepare()
        var newPointID: UUID!
        let rematchCapture = freezeCapture(in: rematchStore, floor: -3) { date in
            rematchStore.recordParkingPoint(coordinate: coordinate, address: "Unknown floor", createdAt: date,
                predictedFloorIndex: nil, manualFloorIndex: nil, confidence: nil)
            newPointID = rematchStore.currentPoint!.id
        }
        rematchStore.saveCapturedFloor(captureID: rematchCapture, floor: -3, userConfirmed: true)
        precondition(rematchStore.lot(containing: newPointID)?.id == scopedUnderground.id,
                     "A delayed floor result did not resolve an initially unknown facility")
        TestClock.now += 60
        TestClock.uptime += 60
        let protectedCapture = freezeCapture(in: rematchStore, floor: -3) { date in
            rematchStore.recordParkingPoint(coordinate: coordinate, address: "User choice", createdAt: date,
                predictedFloorIndex: nil, manualFloorIndex: nil, confidence: nil)
            newPointID = rematchStore.currentPoint!.id
            precondition(rematchStore.movePoint(newPointID, toLotID: scopedGround.id))
        }
        rematchStore.saveCapturedFloor(captureID: protectedCapture, floor: -3, userConfirmed: true)
        precondition(rematchStore.lot(containing: newPointID)?.id == scopedGround.id,
                     "An automatic floor result undid a manual facility assignment")
        try checkDelayedFloor(defaults: defaults)
        try checkUnattendedCapture(defaults: defaults)
        try checkEarlyVisitFloor(defaults: defaults)
        try checkStableGroupAnchor(defaults: defaults)
        try checkRecordGroups(defaults: defaults)
        try checkBoundariesAndMerge(defaults: defaults)
        try checkPodiumCalibration(defaults: defaults)
        try checkManualCorrections(defaults: defaults)
        print("PASS: reversible modes, per-visit floors, shared calibration, named levels, scoped facilities, legacy storage and unshifted positions")
    }

    static func checkManualCorrections(defaults: UserDefaults) throws {
        let older = point(-1, date: -3600)
        let newer = point(-1, date: -1800)
        var a = lot([older, newer])
        func coordinate(_ east: Double, _ north: Double) -> CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: older.latitude + north / 111_000,
                                   longitude: older.longitude + east / (111_000 * cos(older.latitude * .pi / 180)))
        }
        func polygon(_ east: Double) -> [ParkingBoundaryVertex] {
            [(-25.0, -25.0), (25.0, -25.0), (25.0, 25.0), (-25.0, 25.0)].map {
                let c = coordinate(east + $0.0, $0.1)
                return ParkingBoundaryVertex(latitude: c.latitude, longitude: c.longitude)
            }
        }
        a.boundaryVertices = polygon(0)
        var bPoint = point(-3, date: -7200)
        let target = coordinate(100, 0)
        bPoint.latitude = target.latitude
        bPoint.longitude = target.longitude
        var b = lot([bPoint])
        b.name = "B"
        b.centerLatitude = target.latitude
        b.centerLongitude = target.longitude
        b.boundaryVertices = polygon(100)
        b.floorScopeIndex = -3
        defaults.set(try JSONEncoder().encode([a, b]), forKey: "parking_floor_store_v1")
        defaults.set(1, forKey: "parkingFloorMode")
        let store = ParkingFloorStore()
        store.prepare()
        store.separatePointFromGroup(older.id)
        precondition(store.recordGroup(containing: older.id)?.records.count == 1)
        precondition(store.mapPoints.contains { $0.id == older.id })
        store.setPointCoordinate(pointID: older.id, coordinate: target)
        precondition(store.lot(containing: older.id)?.id == b.id, "Dragging into B must move this record to B despite its old floor")
        precondition(store.allPoints.first { $0.id == newer.id }?.coordinate.latitude == newer.latitude)
        precondition(store.lot(containing: newer.id)?.id == a.id)
        let reopened = ParkingFloorStore()
        reopened.prepare()
        precondition(reopened.lot(containing: older.id)?.id == b.id)
        precondition(reopened.allPoints.first { $0.id == older.id }?.isDetachedFromGroup != true)
        reopened.setManualFloor(pointID: older.id, floorIndex: -3)
        precondition(reopened.recordGroup(containing: older.id)?.records.count == 2,
                     "Corrected lot and floor must aggregate regardless of the old address")
        reopened.separatePointFromGroup(older.id)
        precondition(reopened.recordGroup(containing: older.id)?.records.count == 1)
        reopened.setManualFloor(pointID: older.id, floorIndex: -3)
        precondition(reopened.recordGroup(containing: older.id)?.records.count == 2,
                     "Explicit floor correction must also repair previously detached records")
        let regrouped = ParkingFloorStore()
        regrouped.prepare()
        precondition(regrouped.recordGroup(containing: older.id)?.records.count == 2)
        reopened.recordParkingPoint(coordinate: target, address: "Manual", createdAt: TestClock.now,
            predictedFloorIndex: nil, manualFloorIndex: nil, confidence: nil, isManualEntry: true)
        precondition(reopened.currentPoint?.isManualEntry == true)
        precondition(reopened.currentPoint?.effectiveFloorIndex == nil, "A manual session must not invent a detected floor")
        let firstManualID = reopened.currentPoint!.id
        reopened.recordParkingPoint(coordinate: target, address: "Manual", createdAt: TestClock.now.addingTimeInterval(2),
            predictedFloorIndex: nil, manualFloorIndex: nil, confidence: nil, isManualEntry: true)
        precondition(reopened.currentPoint?.id != firstManualID, "Restarting manual parking must create a distinct record")
        let persisted = ParkingFloorStore()
        persisted.prepare()
        precondition(persisted.allPoints.filter { $0.isManualEntry == true }.count == 2)
        print("PASS: separated records, drag A-to-B reassignment, unchanged neighbours, persistence and independent manual sessions")
    }

    static func checkPodiumCalibration(defaults: UserDefaults) throws {
        var complete = point(1, date: -600, delta: 9.7)
        complete.floorConfirmedByUser = true
        var incomplete = point(1, date: -300, delta: 2)
        incomplete.barometerCalibrationEligible = false
        var legacy = point(1, date: -200, delta: 3)
        legacy.barometerCalibrationEligible = nil
        let residence = lot([complete, incomplete, legacy])
        defaults.set(try JSONEncoder().encode([residence]), forKey: "parking_floor_store_v1")
        let store = ParkingFloorStore()
        store.prepare()
        store.setFloorMode(.perVisit)
        store.setManualFloor(pointID: complete.id, floorIndex: 1)
        store.setManualFloor(pointID: incomplete.id, floorIndex: 1)
        store.setManualFloor(pointID: legacy.id, floorIndex: 1)
        let profiles = store.floorHeightProfiles(near: coordinate)
        precondition(profiles.count == 1 && profiles[0].count == 1)
        precondition(abs(profiles[0].height - 9.7) < 0.001)
        precondition(store.estimatedFloor(near: coordinate, delta: 9.6) == 1,
                     "Podium height must map to the confirmed floor, not three uniform floors")
        precondition(store.allPoints.count == 3, "Excluded measurements must not delete parking records")
        let reload = ParkingFloorStore()
        reload.prepare()
        precondition(reload.floorHeightProfiles(near: coordinate).first?.count == 1)
        print("PASS: podium floor prediction, same-floor confirmation, incomplete/legacy exclusion and preserved records")
    }

    static func checkEarlyVisitFloor(defaults: UserDefaults) throws {
        TestClock.now += 600
        defaults.removeObject(forKey: "parking_floor_store_v1")
        let store = ParkingFloorStore()
        store.prepare()
        store.setFloorMode(.perVisit)
        let manager = store.barometer
        let sensor = CMAltimeter.latest!
        manager.updateDriving(speed: 40, timestamp: TestClock.now, coordinate: coordinate)
        manager.updateDriving(speed: 10, timestamp: TestClock.now, coordinate: coordinate)
        for i in 0..<20 {
            TestClock.now += 1
            TestClock.uptime += 1
            manager.updateDriving(speed: i < 3 ? 10 : 0, timestamp: TestClock.now, coordinate: coordinate)
            sensor.emit(i < 3 ? 0 : 3)
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
            if i == 5 {
                store.recordParkingPoint(coordinate: coordinate, address: "Home", createdAt: TestClock.now,
                    predictedFloorIndex: nil, manualFloorIndex: nil, confidence: nil)
            }
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        precondition(store.currentPoint?.predictedFloorIndex == 1)
        precondition(store.currentPoint?.isFloorConfirmed == false)
        precondition(!manager.isUpdating, "A stable stop bound to a parking visit must freeze automatically")
        let reload = ParkingFloorStore()
        reload.prepare()
        precondition(reload.currentPoint?.predictedFloorIndex == 1)
        print("PASS: early parking visit receives an unattended stable floor estimate")
    }

    static func checkStableGroupAnchor(defaults: UserDefaults) throws {
        var old = point(1, date: -600)
        old.longitude -= 0.0005
        let history = (0..<14).map { index -> ParkingPointRecord in
            var record = old
            record.id = UUID()
            record.createdAt = old.createdAt.addingTimeInterval(Double(-index * 600))
            record.latitude += Double(index) * 0.000001
            return record
        }
        let existing = lot(history)
        defaults.set(try JSONEncoder().encode([existing]), forKey: "parking_floor_store_v1")
        let store = ParkingFloorStore()
        store.prepare()
        store.setFloorMode(.perVisit)
        store.recordParkingPoint(coordinate: coordinate, address: "Home", createdAt: TestClock.now,
            predictedFloorIndex: nil, manualFloorIndex: nil, confidence: nil)
        let newestID = store.currentPoint!.id
        store.setManualFloor(pointID: newestID, floorIndex: 1)
        let group = store.recordGroups.first { $0.id.floor == 1 }!
        precondition(group.records.count == 15 && group.latest.id == newestID)
        precondition(group.mapCoordinate.longitude == old.longitude, "New record must not move the established group")
        precondition(store.currentPoint?.longitude == coordinate.longitude, "Real visit coordinates must be preserved")
        let reload = ParkingFloorStore()
        reload.prepare()
        precondition(reload.recordGroups.first { $0.id.floor == 1 }!.mapCoordinate.longitude == old.longitude)
        store.setPointCoordinate(pointID: newestID, coordinate: coordinate)
        precondition(store.recordGroups.first { $0.id.floor == 1 }!.mapCoordinate.longitude == coordinate.longitude)
        for record in history {
            let saved = store.allPoints.first { $0.id == record.id }!
            precondition(saved.latitude == record.latitude && saved.longitude == record.longitude)
        }
        print("PASS: stable group anchor, latest metadata, reload and explicit drag without moving history")
    }

    static func checkUnattendedCapture(defaults: UserDefaults) throws {
        UIApplication.shared.applicationState = .background
        TestClock.now += 600
        TestClock.uptime += 600
        defaults.removeObject(forKey: "parking_floor_store_v1")
        let store = ParkingFloorStore()
        store.prepare()
        store.setFloorMode(.perVisit)
        let manager = store.barometer
        let sensor = CMAltimeter.latest!
        manager.updateDriving(speed: 40, timestamp: TestClock.now, coordinate: coordinate)
        precondition(manager.captureID == nil, "High speed must not capture")
        manager.updateDriving(speed: 30, timestamp: TestClock.now, coordinate: coordinate)
        precondition(manager.captureID == nil, "Exactly 30 is outside the detection threshold")
        manager.updateDriving(speed: 29, timestamp: TestClock.now, coordinate: coordinate)
        let id = manager.captureID!
        for i in 1...15 {
            TestClock.now += 1
            TestClock.uptime += 1
            manager.updateDriving(speed: i < 4 ? 25 : 0, timestamp: TestClock.now, coordinate: coordinate)
            sensor.emit(i < 4 ? 0 : -6)
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
            precondition(manager.captureID == id, "25 km/h must keep the same continuous capture")
        }
        let arrival = TestClock.now.addingTimeInterval(-10)
        precondition(manager.completedResult == nil, "Ignoring the prompt should keep background sampling")
        manager.suspendCapture()
        precondition(manager.isUpdating && manager.completedResult == nil,
                     "Backgrounding must keep the same capture running")
        UIApplication.shared.applicationState = .background
        let visit = LocationManager.VisitRecord(id: UUID(), address: "Unattended garage",
            latitude: coordinate.latitude, longitude: coordinate.longitude, arrivalDate: arrival,
            transportType: "Driving", isAutomotive: true)
        store.recordParkingPoint(from: visit)
        UIApplication.shared.applicationState = .active
        precondition(store.currentPoint?.predictedFloorIndex == -2 && store.currentPoint?.displayFloor != nil,
                     "A later visit must use the saved barometer estimate without a manual tick")
        precondition(store.currentPoint?.isFloorConfirmed == false,
                     "Saving an estimate is not human confirmation")
        let reload = ParkingFloorStore()
        reload.prepare()
        precondition(reload.currentPoint?.predictedFloorIndex == -2,
                     "Unattended estimate must survive storage reload")
        print("PASS: 30 km/h boundary, continuous 25 km/h capture and unattended background floor persistence")
    }

    static func checkDelayedFloor(defaults: UserDefaults) throws {
        TestClock.now += 600
        TestClock.uptime += 600
        defaults.set(try JSONEncoder().encode([lot([point(-1, date: -3600)])]), forKey: "parking_floor_store_v1")
        let store = ParkingFloorStore()
        store.prepare()
        store.setFloorMode(.perVisit)
        let previous = store.allPoints[0]
        let manager = store.barometer
        let sensor = CMAltimeter.latest!
        manager.updateDriving(speed: 30, timestamp: TestClock.now, coordinate: coordinate)
        var arrival = TestClock.now
        var pointID: UUID!
        for i in 1...260 {
            TestClock.now += 1
            TestClock.uptime += 1
            manager.updateDriving(speed: i <= 240 ? 5 : 0, timestamp: TestClock.now, coordinate: coordinate)
            sensor.emit(i < 4 ? 0 : -9)
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
            if i == 10 {
                arrival = TestClock.now
                let visit = LocationManager.VisitRecord(id: UUID(), address: "Garage", latitude: coordinate.latitude,
                    longitude: coordinate.longitude, arrivalDate: arrival, transportType: "Driving", isAutomotive: true)
                store.recordParkingPoint(from: visit)
                pointID = store.currentPoint!.id
                precondition(store.currentPoint?.isFloorConfirmed == false,
                             "Historical fallback must remain an unconfirmed estimate")
                store.updateLLMData(spotNumber: nil, areaCode: nil, floorText: "Unknown", floorIndex: nil)
                // Duplicate visit delivery must retain the same point/capture link.
                store.recordParkingPoint(from: visit)
            }
        }
        let captureID = manager.captureID!
        precondition(manager.completedResult != nil,
                     "A bound visit must finish automatically when its height stabilizes")
        precondition(manager.completedResult?.pointID == pointID,
                     "An early visit was not bound to the continuous capture")
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        precondition(store.allPoints.first { $0.id == pointID }?.predictedFloorIndex == -3,
                     "A finished capture must publish its estimate without a UI confirmation")
        precondition(store.allPoints.first { $0.id == pointID }?.isFloorConfirmed == false)
        store.saveCapturedFloor(captureID: captureID, floor: -3, userConfirmed: false)
        precondition(store.allPoints.first { $0.id == pointID }?.predictedFloorIndex == -3,
                     "Delayed automatic floor must update the existing map point")
        store.saveCapturedFloor(captureID: captureID, floor: -4, userConfirmed: true)
        precondition(store.allPoints.count == 2 && store.allPoints.first { $0.id == pointID }?.manualFloorIndex == -4,
                     "Floor adjustment must update the original point, not insert another one")
        precondition(store.allPoints.first { $0.id == previous.id } == previous,
                     "A floor update changed a previous visit at the same garage")
        precondition(store.session(forArrival: arrival)?.floorIndex == -4)
        let reload = ParkingFloorStore()
        reload.prepare()
        precondition(reload.allPoints.first { $0.id == pointID }?.manualFloorIndex == -4,
                     "Updated floor did not survive reload")
        precondition(manager.result(for: arrival, coordinate: coordinate)?.selectedFloor == -4)
        precondition(manager.result(for: previous.createdAt, coordinate: coordinate) == nil,
                     "A capture must never be reused for another visit")
        let unbound = ParkingAltitudeResult(id: UUID(), startedAt: arrival.addingTimeInterval(-10),
            stoppedAt: arrival.addingTimeInterval(250), arrivalDate: arrival.addingTimeInterval(230),
            latitude: coordinate.latitude, longitude: coordinate.longitude, referenceAltitude: 0,
            finalAltitude: -9, sampleCount: 260)
        precondition(unbound.matches(arrival: arrival, coordinate: coordinate),
                     "A delayed visit must match the whole capture, not only its last two minutes")
        precondition(!unbound.matches(arrival: arrival.addingTimeInterval(-3600), coordinate: coordinate))
        print("PASS: early visit, four-minute delay, floor correction, cached map point, session snapshot and reload")
    }

    static func checkRecordGroups(defaults: UserDefaults) throws {
        TestClock.now += 600
        let b1 = point(-1, date: -240, delta: -3)
        let b2 = point(-2, date: -120, delta: -6)
        var estimated = point(-1, date: 0, delta: -3)
        estimated.manualFloorIndex = nil
        estimated.floorConfirmedByUser = false
        let original = lot([b1, b2, estimated])
        defaults.set(try JSONEncoder().encode([original]), forKey: "parking_floor_store_v1")
        let store = ParkingFloorStore()
        store.prepare()
        store.setFloorMode(.perVisit)
        var groups = ParkingRecordGroup.make(lots: store.lots, mode: store.floorMode)
        precondition(groups.count == 2 && groups.first { $0.id.floor == -1 }?.records.count == 2)
        precondition(store.recordGroup(containing: b2.id)?.id.floor == -2)
        precondition(!estimated.isFloorConfirmed && b1.isFloorConfirmed)
        let coordinates = Dictionary(uniqueKeysWithValues: store.allPoints.map { ($0.id, [$0.latitude, $0.longitude]) })
        store.setManualFloors(pointIDs: [b1.id, b2.id], floorIndex: -1)
        groups = ParkingRecordGroup.make(lots: store.lots, mode: store.floorMode)
        precondition(groups.count == 1 && groups[0].records.count == 3 && groups[0].id.floor == -1,
                     "Correcting all visits to B1 must remove the empty B2 display group")
        precondition(store.lots.count == 1 && store.lots[0].id == original.id,
                     "Correcting a floor created or moved a parking area")
        for record in store.allPoints {
            precondition(coordinates[record.id] == [record.latitude, record.longitude], "Grouping changed actual coordinates")
        }
        precondition(store.allPoints.first { $0.id == estimated.id }?.isFloorConfirmed == false,
                     "Batch editing confirmed an unselected visit")
        store.setManualFloor(pointID: b2.id, floorIndex: -2)
        precondition(ParkingRecordGroup.make(lots: store.lots, mode: store.floorMode).count == 2)
        precondition(store.lots[0].floorLearningHistory?.count == 2,
                     "Correcting the same visit duplicated training evidence")
        precondition(abs((store.lots[0].learnedMetersPerFloor ?? 0) - 3) < 0.001)
        precondition(store.estimatedFloor(near: coordinate, delta: -9) == -3,
                     "A multi-floor area was locked to its last manually confirmed floor")
        store.updateLLMData(spotNumber: "12", areaCode: nil, floorText: "B3", floorIndex: -3)
        precondition(store.currentPoint?.isFloorConfirmed == false)
        precondition(store.lots[0].floorLearningHistory?.count == 2, "A photo estimate trained the floor model")
        store.updateLLMData(spotNumber: "12", areaCode: nil, floorText: "B1", floorIndex: -1, userConfirmedFloor: true)
        precondition(store.currentPoint?.isFloorConfirmed == true)
        store.updateLLMData(spotNumber: "13", areaCode: nil, floorText: "B4", floorIndex: -4)
        precondition(store.currentPoint?.effectiveFloorIndex == -1, "A later photo replaced a confirmed floor")
        let reload = ParkingFloorStore()
        reload.prepare()
        precondition(reload.lots == store.lots)
        let oldData = try JSONSerialization.jsonObject(with: JSONEncoder().encode(b1)) as! [String: Any]
        precondition(oldData["floorConfirmedByUser"] == nil)
        let legacy = try JSONDecoder().decode(ParkingPointRecord.self, from: JSONSerialization.data(withJSONObject: oldData))
        precondition(legacy.isFloorConfirmed && legacy.id == b1.id)
        print("PASS: floor groups, single/batch corrections, empty-group removal, unchanged GPS/area, photo estimates and reversible learning")
    }

    static func checkBoundariesAndMerge(defaults: UserDefaults) throws {
        func vertex(_ x: Double, _ y: Double) -> ParkingBoundaryVertex {
            ParkingBoundaryVertex(latitude: coordinate.latitude + y / 111_000,
                longitude: coordinate.longitude + x / (111_000 * cos(coordinate.latitude * .pi / 180)))
        }
        let square = [vertex(-60, -60), vertex(60, -60), vertex(60, 60), vertex(-60, 60)]
        precondition(ParkingBoundaryGeometry.isValid(square))
        precondition(ParkingBoundaryGeometry.contains(coordinate, vertices: square))
        precondition(ParkingBoundaryGeometry.contains(vertex(60, 0).coordinate, vertices: square))
        precondition(!ParkingBoundaryGeometry.contains(vertex(70, 0).coordinate, vertices: square))
        precondition(!ParkingBoundaryGeometry.isValid([square[0], square[2], square[1], square[3]]))
        precondition(!ParkingBoundaryGeometry.isValid([vertex(0, 0), vertex(1, 0), vertex(1, 1)]))
        var five = square
        five.insert(vertex(0, -60), at: 1)
        precondition(ParkingBoundaryGeometry.isValid(five), "Adding a midpoint must keep the polygon valid")
        let concave = [vertex(-60, -60), vertex(60, -60), vertex(0, 0), vertex(60, 60), vertex(-60, 60)]
        precondition(ParkingBoundaryGeometry.isValid(concave))
        precondition(!ParkingBoundaryGeometry.contains(vertex(50, 0).coordinate, vertices: concave))

        let first = point(-1, date: -300, delta: -3)
        let latest = point(-1, date: 0, delta: -3)
        var destination = lot([first])
        destination.floorLearningHistory = [ParkingLotFloorLearning(createdAt: first.createdAt, manualFloorIndex: -1,
            altitudeDeltaMeters: -3, metersPerFloor: 3, lotID: destination.id, pointID: first.id, calibrationEligible: true)]
        destination.floorNames = ["-1": "Residents"]
        destination.floorScopeIndex = -1
        var source = lot([latest])
        source.floorLearningHistory = [ParkingLotFloorLearning(createdAt: latest.createdAt, manualFloorIndex: -1,
            altitudeDeltaMeters: -3, metersPerFloor: 3, lotID: source.id, pointID: latest.id, calibrationEligible: true)]
        source.name = "Residence · Annex"
        source.floorNames = ["-1": "Other", "-2": "Basement 2"]
        source.floorScopeIndex = -2
        defaults.set(try JSONEncoder().encode([destination, source]), forKey: "parking_floor_store_v1")
        let store = ParkingFloorStore()
        store.prepare()
        store.setFloorMode(.perVisit)
        precondition(store.setBoundary(lotID: destination.id, vertices: square))
        store.activeLotID = source.id
        let before = store.allPoints.sorted { $0.id.uuidString < $1.id.uuidString }
        precondition(!store.mergeLot(destination.id, into: destination.id))
        precondition(!store.mergeLot(UUID(), into: destination.id))
        precondition(store.mergeLot(source.id, into: destination.id))
        precondition(store.lots.count == 1 && store.lots[0].id == destination.id)
        precondition(store.currentPoint?.id == latest.id)
        precondition(store.activeLotID == destination.id)
        precondition(store.lots[0].floorLearningHistory?.count == 2)
        precondition(store.lots[0].floorLearningHistory?.allSatisfy { $0.lotID == destination.id } == true)
        precondition(abs((store.lots[0].learnedMetersPerFloor ?? 0) - 3) < 0.001)
        let after = store.allPoints.sorted { $0.id.uuidString < $1.id.uuidString }
        for (a, b) in zip(before, after) {
            precondition(a.id == b.id && a.createdAt == b.createdAt && a.latitude == b.latitude && a.longitude == b.longitude)
            precondition(a.effectiveFloorIndex == b.effectiveFloorIndex)
        }
        precondition(store.recordGroups.count == 1 && store.recordGroups[0].records.count == 2)
        precondition(store.lots[0].floorNames?["-1"] == "Residents")
        precondition(store.lots[0].floorNames?["-2"] == "Basement 2")
        precondition(store.lots[0].floorScopeIndex == nil && store.lots[0].boundaryVertices == square)
        precondition(store.findLotIndex(near: vertex(50, 0).coordinate, radiusMeters: 25, floorIndex: -1) == 0,
                     "Custom boundary must take priority over the old radius")
        precondition(store.findLotIndex(near: vertex(70, 0).coordinate, radiusMeters: 180, floorIndex: -1) == nil)
        store.setPointCoordinate(pointID: latest.id, coordinate: vertex(2, 2).coordinate)
        precondition(store.lots[0].boundaryVertices == square)
        store.setFloorName(lotID: destination.id, floor: -1, name: "  ")
        precondition(store.lotNameByPointID[latest.id] == "Residence", "Clearing a floor alias must restore the place name")
        let reload = ParkingFloorStore()
        reload.prepare()
        precondition(reload.lots == store.lots, "Custom boundary and merged visits must survive reload")
        let revisionBeforeReset = store.mapRevision
        var publishedRevision = revisionBeforeReset
        let revisionObserver = store.$mapRevision.dropFirst().sink { publishedRevision = $0 }
        precondition(store.setBoundary(lotID: destination.id, vertices: nil))
        precondition(store.lots[0].boundaryVertices == nil)
        precondition(publishedRevision > revisionBeforeReset && publishedRevision == store.mapRevision,
                     "Restoring a circle must publish a fresh map revision after boundary changes")
        precondition(store.lots[0].radiusMeters >= 25 && store.lots[0].radiusMeters <= ParkingFloorStore.defaultRadiusMeters)
        let restored = ParkingFloorStore()
        restored.prepare()
        precondition(restored.lots[0].boundaryVertices == nil && restored.lots[0].radiusMeters == store.lots[0].radiusMeters,
                     "Restored circle geometry must survive reload")
        revisionObserver.cancel()
        print("PASS: polygon validation, vertex insertion, containment, manual merge, unchanged visits, custom range persistence and clearing aliases")
    }
}
