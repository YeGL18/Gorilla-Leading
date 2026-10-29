import Foundation
import CoreLocation

struct CarPlayParkingPresentation: Equatable {
    enum Status { case parking, staying, departed, inactive }
    var status: Status
    var entryTime: Date?
    var location: String?
    var floor: String?
    var spot: String?

    static func load(defaults: UserDefaults, latestVisit: LocationManager.VisitRecord?,
                     session: (Date) -> ParkingSessionSnapshot?) -> Self {
        let savedArrival = defaults.object(forKey: "parkingStartTime") as? Date
        let manual = defaults.object(forKey: "manualParkingStartedAt") as? Date
        let dismissed = defaults.object(forKey: "parkingVisitsDismissedThrough") as? Date
        let ended = defaults.bool(forKey: "hasDeparted") || defaults.bool(forKey: "manualDeparted")
        var arrival = savedArrival
        var staying = defaults.bool(forKey: "isNonAutomotiveArrival")
        var active = defaults.bool(forKey: "timerRunning") && !ended
        if let visit = latestVisit {
            let ignored = ParkingEntryClock.ignoresVisit(arrival: visit.arrivalDate, dismissedThrough: dismissed)
            if !ignored && (manual.map { visit.arrivalDate > $0 } ?? true) {
                arrival = visit.arrivalDate
                staying = !visit.isAutomotive
                active = visit.departureDate == nil && !(ended && savedArrival == arrival)
            } else if ignored && manual == nil {
                active = false
            }
        }
        if let manual, !ended, (latestVisit?.arrivalDate ?? .distantPast) <= manual {
            arrival = manual
            staying = false
            active = true
        }
        guard active, let arrival else {
            return Self(status: ended || latestVisit?.departureDate != nil ? .departed : .inactive)
        }
        guard !staying else { return Self(status: .staying) }
        let info = session(arrival)
        let fallback = savedArrival == arrival ? defaults.string(forKey: "parkingEntryLocation") : latestVisit?.address
        return Self(status: .parking, entryTime: ParkingEntryClock.restoredEntry(for: arrival, defaults: defaults),
                    location: info?.locationName ?? fallback, floor: info?.floorDisplay, spot: info?.spotNumber)
    }

    var statusTitle: String {
        switch status {
        case .parking: return String(localized: "已泊車")
        case .staying: return String(localized: "逗留中")
        case .departed: return String(localized: "已離場")
        case .inactive: return String(localized: "未泊車")
        }
    }

    func duration(at date: Date) -> String {
        guard let entryTime else { return "—" }
        let minutes = max(0, Int(date.timeIntervalSince(entryTime) / 60))
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}

enum CarPlayMeterNavigation {
    static func url(coordinate: CLLocationCoordinate2D, name: String) -> URL? {
        guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
        var url = URLComponents()
        url.scheme = "https"
        url.host = "maps.apple.com"
        url.path = "/"
        url.queryItems = [
            URLQueryItem(name: "daddr", value: "\(coordinate.latitude),\(coordinate.longitude)"),
            URLQueryItem(name: "dirflg", value: "d"),
            URLQueryItem(name: "q", value: name)
        ]
        return url.url
    }
}

#if canImport(CarPlay)
import CarPlay
import UIKit

@MainActor
final class GorillaCarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private weak var scene: CPTemplateApplicationScene?
    private weak var controller: CPInterfaceController?
    private var parkingTemplate: CPInformationTemplate?
    private var meterTemplate: CPListTemplate?
    private var refreshTimer: Timer?
    private var statusTask: Task<Void, Never>?

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        scene = templateApplicationScene
        controller = interfaceController
        _ = prepareAppStoresIfAvailable()
        let location = LocationManager.shared
        if location.authorizationStatus == .authorizedAlways || location.authorizationStatus == .authorizedWhenInUse {
            location.startLocationServicesIfNeeded()
        }
        ParkingMeterManager.shared.prepare()
        let template = CPInformationTemplate(title: String(localized: "泊車記憶"), layout: .twoColumn,
                                              items: [], actions: [])
        parkingTemplate = template
        refresh()
        interfaceController.setRootTemplate(template, animated: false, completion: nil)
        startRefreshing()
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        stopRefreshing()
        parkingTemplate = nil
        meterTemplate = nil
        controller = nil
        scene = nil
    }

    func sceneDidBecomeActive(_ scene: UIScene) { refresh(); startRefreshing() }
    func sceneWillResignActive(_ scene: UIScene) { stopRefreshing() }

    private func startRefreshing() {
        guard refreshTimer == nil, controller != nil else { return }
        // CarPlay permits periodic template refreshes at most once every ten seconds.
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func stopRefreshing() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        statusTask?.cancel()
        statusTask = nil
    }

    private func refresh() {
        _ = prepareAppStoresIfAvailable()
        let defaults = UserDefaults(suiteName: "group.com.gorilla.translate") ?? .standard
        let manager = LocationManager.shared
        guard !BackupController.shared.restoring, !BackupController.shared.recoveryRequired,
              UIApplication.shared.isProtectedDataAvailable || manager.hasLoadedVisits else {
            parkingTemplate?.items = [CPInformationItem(title: String(localized: "泊車狀態"),
                detail: String(localized: "資料暫時不可用"))]
            parkingTemplate?.actions = []
            meterTemplate?.updateSections([])
            return
        }
        let data = CarPlayParkingPresentation.load(defaults: defaults, latestVisit: manager.visits.first,
            session: { ParkingFloorStore.shared.session(forArrival: $0) })
        parkingTemplate?.items = [
            CPInformationItem(title: String(localized: "泊車狀態"), detail: data.statusTitle),
            CPInformationItem(title: String(localized: "泊車計時（時:分）"), detail: data.duration(at: Date())),
            CPInformationItem(title: String(localized: "停車場"), detail: data.location ?? "—"),
            CPInformationItem(title: String(localized: "樓層"), detail: data.floor ?? String(localized: "未識別樓層")),
            CPInformationItem(title: String(localized: "車位號"), detail: data.spot ?? "—")
        ]
        if ParkingMeterManager.shared.isEnabled {
            parkingTemplate?.actions = [CPTextButton(title: String(localized: "附近空置咪錶"), textStyle: .normal) { [weak self] _ in
                self?.showMeters()
            }]
            refreshMeterList()
            if statusTask == nil {
                statusTask = Task { [weak self] in
                    await ParkingMeterManager.shared.refreshStatus()
                    guard !Task.isCancelled else { return }
                    self?.refreshMeterList()
                    self?.statusTask = nil
                }
            }
        } else {
            parkingTemplate?.actions = []
            meterTemplate?.updateSections([])
        }
    }

    private func showMeters() {
        let template = CPListTemplate(title: String(localized: "附近空置咪錶"), sections: [])
        template.emptyViewTitleVariants = [String(localized: "暫無可用咪錶資料")]
        template.emptyViewSubtitleVariants = [String(localized: "只顯示附近且狀態有效的空置咪錶")]
        meterTemplate = template
        refreshMeterList()
        controller?.pushTemplate(template, animated: true, completion: nil)
    }

    private func refreshMeterList() {
        guard let meterTemplate else { return }
        let meters = ParkingMeterManager.shared.carPlayAvailableMeters(near: LocationManager.shared.lastLocation)
        let rows = meters.map { meter in
            let row = CPListItem(text: "\(meter.id) \(meter.displayStreet)", detailText: String(localized: "空置"))
            row.accessoryType = .disclosureIndicator
            row.handler = { [weak self] _, completion in
                self?.showNavigation(to: meter)
                completion()
            }
            return row
        }
        meterTemplate.updateSections(rows.isEmpty ? [] : [CPListSection(items: rows)])
    }

    private func showNavigation(to meter: ParkingMeter) {
        let name = "\(meter.id) \(meter.displayStreet)"
        let template = CPInformationTemplate(title: name, layout: .leading,
            items: [CPInformationItem(title: String(localized: "咪錶狀態"), detail: String(localized: "空置狀態可能隨時變更"))],
            actions: [CPTextButton(title: String(localized: "導航"), textStyle: .confirm) { [weak self] _ in
                self?.navigate(to: meter)
            }])
        controller?.pushTemplate(template, animated: true, completion: nil)
    }

    private func navigate(to meter: ParkingMeter) {
        guard ParkingMeterManager.shared.isEnabled, ParkingMeterManager.shared.vehicle != .unset,
              ParkingMeterManager.shared.state(meter) == .vacant else {
            showError(String(localized: "此咪錶已非空置或狀態已過期，請重新選擇。"))
            refreshMeterList()
            return
        }
        guard let url = CarPlayMeterNavigation.url(coordinate: meter.coordinate, name: "\(meter.id) \(meter.displayStreet)"),
              let scene else { return }
        // Scene.open targets the CarPlay display; UIApplication.open only targets iPhone.
        scene.open(url, options: nil) { [weak self] success in
            guard !success else { return }
            Task { @MainActor in self?.showError(String(localized: "未能開啟 Apple Maps，請稍後再試。")) }
        }
    }

    private func showError(_ message: String) {
        let alert = CPAlertTemplate(titleVariants: [message], actions: [
            CPAlertAction(title: String(localized: "確定"), style: .default) { [weak self] _ in
                self?.controller?.dismissTemplate(animated: true, completion: nil)
            }
        ])
        controller?.presentTemplate(alert, animated: true, completion: nil)
    }
}
#endif
