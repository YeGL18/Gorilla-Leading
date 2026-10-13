import XCTest
import Combine
import MapKit
@testable import GorillaEnergyChecks

@MainActor
final class EnergyRuntimeTests: XCTestCase {
    private let source = CLLocationCoordinate2D(latitude: 22.32, longitude: 114.17)
    private let target = CLLocationCoordinate2D(latitude: 22.34, longitude: 114.19)

    func testAutomaticRequestsCoalesceAndBackOff() async {
        var callbacks: [(MKDirections.Response?, Error?) -> Void] = []
        let manager = DestinationManager { _, callback in callbacks.append(callback) }
        for _ in 0..<120 {
            manager.requestRoute(from: source, to: target) { _ in }
        }
        XCTAssertEqual(callbacks.count, 1)
        let forced = expectation(description: "Explicit route action joins the ETA request")
        manager.requestRoute(from: source, to: target, force: true) { _ in forced.fulfill() }
        XCTAssertEqual(callbacks.count, 1)
        callbacks[0](nil, URLError(.notConnectedToInternet))
        await fulfillment(of: [forced], timeout: 2)
        for _ in 0..<120 { manager.requestRoute(from: source, to: target) { _ in } }
        XCTAssertEqual(callbacks.count, 1, "Failures cannot trigger one network request per fix")
    }

    func testDestinationChangeCancelsOldCallbacks() async {
        var callbacks: [(MKDirections.Response?, Error?) -> Void] = []
        let manager = DestinationManager { _, callback in callbacks.append(callback) }
        var oldReplies = 0
        manager.requestRoute(from: source, to: target) { _ in oldReplies += 1 }
        let other = CLLocationCoordinate2D(latitude: 22.4, longitude: 114.2)
        let finished = expectation(description: "New destination completes")
        manager.requestRoute(from: source, to: other) { _ in finished.fulfill() }
        XCTAssertEqual(oldReplies, 1, "Cancellation resolves the old request once")
        XCTAssertEqual(callbacks.count, 2)
        callbacks[0](nil, URLError(.cancelled))
        callbacks[1](nil, URLError(.notConnectedToInternet))
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(oldReplies, 1, "Late old callbacks cannot overwrite the new destination")
    }

    func testSavingAnotherDestinationDoesNotCancelSelectedRoute() async {
        var callbacks: [(MKDirections.Response?, Error?) -> Void] = []
        let manager = DestinationManager { _, reply in callbacks.append(reply) }
        let selected = expectation(description: "Selected route remains pending")
        var selectedReplies = 0
        manager.requestRoute(from: source, to: target) { _ in selectedReplies += 1; selected.fulfill() }
        let added = expectation(description: "Independent saved-place lookup completes")
        manager.calculateRoute(from: source, to: .init(latitude: 22.4, longitude: 114.2)) { _, _ in added.fulfill() }
        XCTAssertEqual(selectedReplies, 0)
        XCTAssertEqual(callbacks.count, 2)
        manager.requestRoute(from: source, to: target) { _ in }
        XCTAssertEqual(callbacks.count, 2, "GPS fixes still join the selected route")
        callbacks[1](nil, URLError(.notConnectedToInternet))
        await fulfillment(of: [added], timeout: 2)
        XCTAssertEqual(selectedReplies, 0)
        callbacks[0](nil, URLError(.notConnectedToInternet))
        await fulfillment(of: [selected], timeout: 2)
        XCTAssertEqual(selectedReplies, 1)
    }

    func testClockStopsOnlyAfterLastVisibleConsumer() async throws {
        let clock = AnimationClock()
        let first = UUID(), second = UUID()
        clock.acquire(first)
        clock.acquire(second)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertGreaterThan(clock.elapsed, 0)
        clock.release(first)
        let before = clock.elapsed
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertGreaterThan(clock.elapsed, before)
        clock.release(second)
        let stopped = clock.elapsed
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(clock.elapsed, stopped)
        clock.acquire(first)
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertGreaterThan(clock.elapsed, stopped)
        clock.release(first)
    }

    func testDayNightDoesNotPublishIdenticalValues() async throws {
        let phase = TimePhaseManager()
        phase.setPreviewHour(12)
        var notifications = 0
        let subscription = phase.objectWillChange.sink { notifications += 1 }
        phase.start()
        try await Task.sleep(nanoseconds: 2_300_000_000)
        phase.stop()
        XCTAssertEqual(notifications, 0, "An unchanged preview must not publish every timer tick")
        withExtendedLifetime(subscription) {}
    }

    func testRealDawnCannotSwallowTheDaytimePalettes() {
        for (dawn, rise, set) in [(5.8, 6.2, 18.0), (5.3, 5.7, 19.1), (6.5, 6.9, 17.6)] {
            let schedule = TimePhaseSchedule(civilDawn: dawn, sunrise: rise, sunset: set)
            var observed = Set<TimePhase>()
            for minute in 0..<1440 {
                let hour = Double(minute) / 60
                let state = schedule.state(at: hour)
                observed.insert(state.phase)
                let covering = schedule.segments.filter { hour >= $0.start && hour < $0.end }
                XCTAssertEqual(covering.count, 1, "No overlapping or missing timeline intervals")
                XCTAssertEqual(covering.first?.phase, state.phase)
                XCTAssertTrue((0...1).contains(state.progress))
            }
            XCTAssertEqual(observed, Set(TimePhase.allCases))
            XCTAssertEqual(schedule.state(at: 12).phase, .morning)
            XCTAssertEqual(schedule.state(at: set).phase, .deepNight)
            XCTAssertEqual(schedule.state(at: 24).phase, schedule.state(at: 0).phase)
            XCTAssertEqual(schedule.segments.reduce(0) { $0 + $1.end - $1.start }, 24, accuracy: 0.0001)
        }
    }

    func testNightFadeUsesTheFullThirtyMinutesBeforeSunset() {
        let schedule = TimePhaseSchedule(civilDawn: 5.8, sunrise: 6.2, sunset: 18.1)
        for (minutes, progress) in [(30.0, 0.0), (15.0, 0.5), (1.0, 29.0 / 30)] {
            let state = schedule.state(at: 18.1 - minutes / 60)
            XCTAssertEqual(state.phase, .sunset)
            XCTAssertEqual(state.next, .deepNight)
            XCTAssertEqual(state.progress, progress, accuracy: 0.0001)
        }
        XCTAssertEqual(schedule.state(at: 18.1).phase, .deepNight)
        XCTAssertFalse(SunPosition.calculate(hour: 18.2, sunrise: 6.2, sunset: 18.1).visible)
        XCTAssertEqual(BlendedPhaseColors.blend(from: TimePhase.sunset.colors,
            to: TimePhase.deepNight.colors, progress: 0.75).sunOpacity, 0.25)
    }

    func testActualSunTimesDriveTheManagerAndPreviewTogether() {
        let service = WeatherService()
        func date(_ hour: Int, _ minute: Int) -> Date {
            Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())!
        }
        service.sunTimes = SunTimes(sunrise: date(6, 12), sunset: date(18, 6),
                                   civilDawn: date(5, 48), civilDusk: date(18, 30))
        let manager = TimePhaseManager(weatherService: service)
        for segment in manager.schedule.segments {
            manager.setPreviewHour((segment.start + segment.end) / 2)
            XCTAssertEqual(manager.currentPhase, segment.phase)
        }
        manager.setPreviewHour(12.5)
        XCTAssertEqual(manager.currentPhase, .morning)
        manager.setPreviewHour(18.1)
        XCTAssertEqual(manager.currentPhase, .deepNight)
    }

    func testLateSunResponseUpdatesAllExistingManagers() {
        let service = WeatherService()
        let home = TimePhaseManager(weatherService: service)
        let preview = TimePhaseManager(weatherService: service)
        preview.setPreviewHour(18.75)
        func date(_ hour: Int, _ minute: Int) -> Date {
            Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())!
        }
        XCTAssertEqual(preview.schedule.sunsetHour, 18)
        XCTAssertFalse(preview.hasActualSunTimes)
        service.sunTimes = SunTimes(sunrise: date(5, 42), sunset: date(19, 6),
                                   civilDawn: date(5, 18), civilDusk: date(19, 30))
        XCTAssertEqual(home.schedule.sunriseHour, 5.7, accuracy: 0.001)
        XCTAssertEqual(preview.schedule.sunsetHour, 19.1, accuracy: 0.001)
        XCTAssertEqual(preview.currentPhase, .sunset)
        XCTAssertEqual(home.schedule, preview.schedule)
        XCTAssertTrue(preview.hasActualSunTimes)
    }

    func testSunRequestsUseLocalDateAndRefreshOnNextDay() async {
        var time = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 10,
                                                             hour: 0, minute: 5))!
        var urls: [URL] = []
        var replies: [(Data?) -> Void] = []
        let service = WeatherService(now: { time }, fetch: { url, reply in
            urls.append(url)
            replies.append(reply)
        })
        func response() -> Data {
            let formatter = ISO8601DateFormatter()
            func stamp(_ hour: Int) -> String {
                formatter.string(from: Calendar.current.date(bySettingHour: hour, minute: 15,
                                                              second: 0, of: time)!)
            }
            return try! JSONSerialization.data(withJSONObject: ["status": "OK", "results": [
                "sunrise": stamp(6), "sunset": stamp(18),
                "civil_twilight_begin": stamp(5), "civil_twilight_end": stamp(19)]])
        }
        let first = expectation(description: "Today's sun data")
        service.fetchSunTimes(for: source) { _ in first.fulfill() }
        XCTAssertEqual(URLComponents(url: urls[0], resolvingAgainstBaseURL: false)?.queryItems?
            .first { $0.name == "date" }?.value, "2026-10-10")
        replies[0](response())
        await fulfillment(of: [first], timeout: 2)
        service.fetchSunTimes(for: source) { _ in }
        XCTAssertEqual(urls.count, 1)
        time = Calendar.current.date(byAdding: .day, value: 1, to: time)!
        let second = expectation(description: "Tomorrow refreshes the cache")
        service.fetchSunTimes(for: source) { _ in second.fulfill() }
        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(URLComponents(url: urls[1], resolvingAgainstBaseURL: false)?.queryItems?
            .first { $0.name == "date" }?.value, "2026-10-11")
        replies[1](response())
        await fulfillment(of: [second], timeout: 2)
    }

    func testStoppingCancelsEntranceAndCannotRestartItself() async throws {
        let phase = TimePhaseManager()
        phase.startWithEntranceAnimation()
        try await Task.sleep(nanoseconds: 100_000_000)
        phase.stop()
        let frozen = phase.blendedColors
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(phase.blendedColors, frozen)
        phase.start()
        phase.stop()
    }

    func testSheenSleepsForPauseAndRetainsSweepCadence() {
        let schedule = SheenTimelineSchedule()
        let dates = schedule.entries(from: Date(timeIntervalSinceReferenceDate: 5.5), mode: .normal).makeIterator()
        let pause = dates.next()!
        let sweep = dates.next()!
        XCTAssertFalse(schedule.state(at: pause).sweeping)
        XCTAssertEqual(sweep.timeIntervalSinceReferenceDate, 7.2, accuracy: 0.000_01)
        XCTAssertTrue(schedule.state(at: sweep).sweeping)
        XCTAssertEqual(dates.next()!.timeIntervalSince(sweep), 1.0 / 120.0, accuracy: 0.000_01)
        let slowDates = schedule.entries(from: sweep, mode: .lowFrequency).makeIterator()
        _ = slowDates.next()
        XCTAssertEqual(slowDates.next()!.timeIntervalSince(sweep), 1.0 / 30.0, accuracy: 0.000_01)
    }

    func testSunRequestsCoalesceAndFailuresWaitBeforeRetry() async {
        var time = Date()
        var callbacks: [(Data?) -> Void] = []
        let service = WeatherService(now: { time }, fetch: { _, reply in callbacks.append(reply) })
        let failed = expectation(description: "Every waiting caller completes")
        failed.expectedFulfillmentCount = 120
        for _ in 0..<120 { service.fetchSunTimes(for: source) { _ in failed.fulfill() } }
        XCTAssertEqual(callbacks.count, 1)
        callbacks[0](nil)
        await fulfillment(of: [failed], timeout: 2)
        for _ in 0..<120 { service.fetchSunTimes(for: source) { _ in } }
        XCTAssertEqual(callbacks.count, 1)
        time = time.addingTimeInterval(61)
        let retried = expectation(description: "A later fix retries")
        service.fetchSunTimes(for: source) { _ in retried.fulfill() }
        XCTAssertEqual(callbacks.count, 2)
        callbacks[1](nil)
        await fulfillment(of: [retried], timeout: 2)
    }

    func testSunDatesWithAndWithoutFractionalSecondsAreCached() async {
        for fractional in [false, true] {
            var callbacks: [(Data?) -> Void] = []
            let service = WeatherService(fetch: { _, reply in callbacks.append(reply) })
            let complete = expectation(description: "ISO date is decoded")
            service.fetchSunTimes(for: source) { XCTAssertNotNil($0); complete.fulfill() }
            let suffix = fractional ? ".000Z" : "Z"
            let payload: [String: Any] = ["status": "OK", "results": [
                "sunrise": "2026-10-09T06:00:00" + suffix,
                "sunset": "2026-10-09T18:00:00" + suffix,
                "civil_twilight_begin": "2026-10-09T05:30:00" + suffix,
                "civil_twilight_end": "2026-10-09T18:30:00" + suffix]]
            callbacks[0](try! JSONSerialization.data(withJSONObject: payload))
            await fulfillment(of: [complete], timeout: 2)
            service.fetchSunTimes(for: source) { XCTAssertNotNil($0) }
            XCTAssertEqual(callbacks.count, 1, "The successful daily cache prevents another request")
        }
    }

    func testMapEffectDoesNotAddAnotherMapOrInterceptTouches() {
        let container = MapPresentationContainer(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        let map = MKMapView(frame: container.bounds)
        container.addSubview(map)
        container.softenEdges(cornerRadius: 100)
        container.layoutIfNeeded()
        XCTAssertEqual(container.subviews.compactMap { $0 as? MKMapView }.count, 1)
        let effect = container.subviews.compactMap { $0 as? UIVisualEffectView }.first
        XCTAssertNotNil(effect?.mask)
        XCTAssertEqual(effect?.isUserInteractionEnabled, false)
        let mask = container.layer.mask
        for _ in 0..<120 { container.softenEdges(cornerRadius: 100); container.setNeedsLayout(); container.layoutIfNeeded() }
        XCTAssertTrue(container.layer.mask === mask, "Camera updates must not regenerate masks")
        container.bounds.size = CGSize(width: 700, height: 390)
        container.setNeedsLayout()
        container.layoutIfNeeded()
        XCTAssertFalse(container.layer.mask === mask, "Rotation regenerates masks")
        container.softenEdges(cornerRadius: nil)
        XCTAssertNil(container.layer.mask)
        XCTAssertEqual(container.subviews.count, 1)
    }
}
