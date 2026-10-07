import SwiftUI
import MapKit
import Combine

private let hongKongMapFallback = CLLocation(
    latitude: 22.3193,
    longitude: 114.1694
)

@MainActor
final class MapCompassBridge: ObservableObject {
    weak var mapView: MKMapView?
    @Published private(set) var revision = 0

    func connect(_ mapView: MKMapView) {
        guard self.mapView !== mapView else { return }
        self.mapView = mapView
        revision &+= 1
    }
}

final class CompassContainerView: UIView {
    private static let itemSize = CGSize(width: 44, height: 44)
    let compass: MKCompassButton

    override var intrinsicContentSize: CGSize { Self.itemSize }

    init(compass: MKCompassButton) {
        self.compass = compass
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)
        addSubview(compass)
        compass.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            compass.centerXAnchor.constraint(equalTo: centerXAnchor),
            compass.centerYAnchor.constraint(equalTo: centerYAnchor),
            compass.widthAnchor.constraint(equalToConstant: 44),
            compass.heightAnchor.constraint(equalToConstant: 44),
            widthAnchor.constraint(equalToConstant: Self.itemSize.width),
            heightAnchor.constraint(equalToConstant: Self.itemSize.height),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

struct MapCompassToolbarView: UIViewRepresentable {
    @ObservedObject var bridge: MapCompassBridge

    func makeUIView(context: Context) -> CompassContainerView {
        let compass = MKCompassButton(mapView: bridge.mapView)
        compass.compassVisibility = .visible
        return CompassContainerView(compass: compass)
    }

    func updateUIView(_ container: CompassContainerView, context: Context) {
        _ = bridge.revision
        container.compass.mapView = bridge.mapView
        container.compass.compassVisibility = .visible
    }
}

/// 帶放大比例嘅停車點 marker。
/// MapKit 會自己寫 annotation view 嘅 `transform`（地圖跟 heading 旋轉時做反旋轉、
/// 飛行／縮放動畫時做移位），所以「最新點大 30%」唔可以直接擺落 `transform`，
/// 一被 MapKit 覆寫就返返去原大（要等到下次 configure 先再變大）。
/// 呢個 subclass 將「MapKit 嘅 transform」同「我哋嘅放大」分開：
/// 每次 MapKit 寫入都自動重新疊加放大比例。
final class ScaledMarkerAnnotationView: FadingMarkerAnnotationView {
    /// 1.0 = 原大；1.3 = 大 30%
    var sizeScale: CGFloat = 1 {
        didSet {
            guard sizeScale != oldValue else { return }
            applyScaledTransform()
        }
    }
    /// MapKit 寫入嘅原始 transform（唔包我哋嘅放大）
    private var mapTransform: CGAffineTransform = .identity

    override var transform: CGAffineTransform {
        // getter 返「MapKit 原始值」：萬一 MapKit read-modify-write（讀咗再轉再寫返），
        // 都唔會將我哋嘅放大重複疊加。
        get { mapTransform }
        set {
            mapTransform = newValue
            applyScaledTransform()
        }
    }

    private func applyScaledTransform() {
        super.transform = mapTransform.scaledBy(x: sizeScale, y: sizeScale)
    }
}

/// 藍色定位點標註 view。
/// 預設個 view 連埋準確度光環，hit area 好大；同停車點標示疊埋或者太近嗰陣，
/// MapKit 內建 tap-to-select 會判斷做「撳咗藍點」，跟手 deselect 停車點，
/// 停車彈窗就出一下就即刻消失。呢度整到藍點食唔到 hit test／selection，
/// 撳停車點先會贏到呢場判斷。
final class NonSelectableUserLocationView: MKUserLocationView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { false }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}

final class ParkingPointAnnotation: NSObject, MKAnnotation {
    let pointID: UUID
    dynamic var coordinate: CLLocationCoordinate2D
    dynamic var title: String?
    dynamic var subtitle: String?
    var isAutomotive: Bool
    var isLatest = false
    var recordCount = 1
    var displayOffset = CGPoint(x: 0, y: -10)

    init(pointID: UUID, coordinate: CLLocationCoordinate2D, title: String?, subtitle: String?, isAutomotive: Bool = true) {
        self.pointID = pointID
        self.coordinate = coordinate
        self.title = title
        self.subtitle = subtitle
        self.isAutomotive = isAutomotive
        super.init()
    }
}

/// 綠色範圍「彈出彈入」曲線：現身略過衝（easeOutBack），消失加速縮細。
enum ParkingRangePop {
    static let hiddenScale: CGFloat = 0.72

    /// 彈出（出現）：0.72 → 過衝 ~1.05 → 1.0
    static func appearScale(_ t: CGFloat) -> CGFloat {
        let c1: CGFloat = 1.70158
        let c3 = c1 + 1
        let u = 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
        return hiddenScale + (1 - hiddenScale) * u
    }

    /// 彈入（消失）：1.0 → 加速收細到 0.72
    static func dismissScale(_ t: CGFloat) -> CGFloat {
        1 - (1 - hiddenScale) * t * t
    }

    static func appearAlpha(_ t: CGFloat) -> CGFloat { min(1, t * 2) }

    static func dismissAlpha(_ t: CGFloat) -> CGFloat { 1 - t * t }
}

final class ParkingRangeRenderer: MKCircleRenderer {
    /// 彈出彈入進度用嘅縮放（0.72=收埋，1=完全彈出）。改咗即刻作廢舊路徑。
    var popScale: CGFloat = 1 {
        didSet { if popScale != oldValue { path = nil } }
    }

    override func createPath() {
        guard let circle = overlay as? MKCircle else {
            super.createPath()
            return
        }
        if popScale >= 0.999 {
            super.createPath()
            return
        }
        // 彈出彈入：圍住圓心縮放圓半徑
        let centerMapPoint = MKMapPoint(circle.coordinate)
        let center = point(for: centerMapPoint)
        let radiusMapPoints = circle.radius / MKMetersPerMapPointAtLatitude(circle.coordinate.latitude)
        let edge = point(for: MKMapPoint(x: centerMapPoint.x + radiusMapPoints, y: centerMapPoint.y))
        let radius = hypot(edge.x - center.x, edge.y - center.y) * popScale
        path = CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                        width: radius * 2, height: radius * 2), transform: nil)
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        context.saveGState()
        context.setShadow(offset: .zero, blur: 8, color: parkingBoundaryGreen.withAlphaComponent(0.35).cgColor)
        super.draw(mapRect, zoomScale: zoomScale, in: context)
        context.restoreGState()
    }
}

struct MapView: UIViewRepresentable {
    @ObservedObject private var meterManager = ParkingMeterManager.shared
    @Binding var savedRegion: MKCoordinateRegion?
    @Binding var savedCamera: MKMapCamera?
    @Binding var flyTrigger: Int
    var isLandscape: Bool
    var routeOverlay: MKPolyline?
    var routeAnimationOverlay: MKPolyline?
    var followHeading: Bool
    var continuousFollow: Bool = false
    var hkDetailMode: Bool = false
    var northOverrideTrackingToken: Int
    var parkingPoints: [ParkingPointRecord]
    var parkingPointTitlePrefixesByID: [UUID: String]
    var selectedParkingPointID: UUID?
    var onSelectParkingPoint: (UUID?) -> Void
    var onMoveParkingPoint: (UUID, CLLocationCoordinate2D) -> Void
    var routePriorityToken: UUID?
    var routePriorityAnchor: CLLocationCoordinate2D?
    var meterNavigationTargetID: String? = nil
    var meterNavigationTargetCoordinate: CLLocationCoordinate2D? = nil
    var routeOverlayToken: UUID?
    var routeOverlayAnimationToken: UUID?
    var mapStyleIndex: Int = 0
    var showSatellite: Bool = false
    var centerOffsetX: CGFloat = 0
    var centerOffsetY: CGFloat = 0
    var hideCompass: Bool = false
    var compassBridge: MapCompassBridge? = nil
    /// Called when the user taps an empty (annotation-free) area of the map.
    /// Used to collapse the expanded capsule without blocking map pan/zoom.
    var onMapBlankTap: (() -> Void)? = nil
    /// Called when the user selects/deselects an HK annotation.
    var onSelectHKLocation: ((String, CLLocationCoordinate2D)?) -> Void = { _ in }
    /// 繪製停車場範圍模式：非 nil 時顯示中心指針＋逐點繪製圖層，並停用泊車點點擊／拖曳。
    var boundaryDrawVertices: [ParkingBoundaryVertex]? = nil
    /// 「加點」時透過佢讀取指針對準嘅座標，進入模式時讀取一次性鏡頭目標。
    var boundaryDrawBridge: BoundaryDrawMapBridge? = nil
    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.clipsToBounds = true
        let mapView = NonAdjustingMapView()
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .none
        mapView.showsCompass = false
        mapView.pointOfInterestFilter = .excludingAll
        mapView.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        if showSatellite {
            // 衛星3D模式：hybrid flyover
            if #available(iOS 16.0, *) {
                let config = MKHybridMapConfiguration()
                config.elevationStyle = .realistic
                mapView.preferredConfiguration = config
            } else {
                mapView.mapType = .hybridFlyover
            }
        } else if mapStyleIndex == 1 {
            mapView.mapType = .standard
            if #available(iOS 16.0, *) {
                let config = MKStandardMapConfiguration()
                config.emphasisStyle = .muted
                config.elevationStyle = .realistic
                mapView.preferredConfiguration = config
            }
        } else {
            mapView.mapType = .standard
        }
        mapView.delegate = context.coordinator
        context.coordinator.mapView = mapView
#if DEBUG
        if context.coordinator.cameraChecksEnabled {
            container.isAccessibilityElement = true
            container.accessibilityIdentifier = "mapCameraChecks"
            container.accessibilityLabel = "Map camera checks"
        }
#endif
        context.coordinator.showSatellite = showSatellite
        context.coordinator.mapStyleIndex = mapStyleIndex
        compassBridge?.connect(mapView)

        // 只採用 app 已確認仍然有效的 GPS fix。MapKit 在未有定位時可能回傳
        // 模擬器／系統預設的美國座標，會令首次飛入由 San Francisco 開始。
        let center = locationManager.mapReferenceLocation?.coordinate
            ?? hongKongMapFallback.coordinate
        mapView.allowCameraChange = true
        let camera = MKMapCamera()
        camera.centerCoordinate = center
        camera.centerCoordinateDistance = 50000
        mapView.setCamera(camera, animated: false)
        mapView.allowCameraChange = false

        mapView.onTouchBegan = { [weak coordinator = context.coordinator] in
            coordinator?.beginManualCameraControl()
        }
        mapView.onTouchEnded = { [weak coordinator = context.coordinator] in
            coordinator?.endManualCameraControl()
        }
        let blankTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleBlankTap(_:)))
        blankTap.cancelsTouchesInView = false
        blankTap.delegate = context.coordinator
        mapView.addGestureRecognizer(blankTap)

        let parkingDrag = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleParkingDrag(_:)))
        parkingDrag.minimumPressDuration = 0.12
        parkingDrag.allowableMovement = 10
        parkingDrag.cancelsTouchesInView = false
        parkingDrag.name = "parkingPointDrag"
        parkingDrag.delegate = context.coordinator
        mapView.addGestureRecognizer(parkingDrag)

        let parkingTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleParkingTap(_:)))
        parkingTap.name = "parkingPointTap"
        // 撳中停車點就唔好再俾 touch 落去 MapKit——內建 tap-to-select 喺疊位／近位
        // 會判斷做藍點／咪錶群組，抽走停車點 selection，彈窗出一下就即刻消失。
        parkingTap.cancelsTouchesInView = true
        parkingTap.delegate = context.coordinator
        parkingTap.require(toFail: parkingDrag)
        mapView.addGestureRecognizer(parkingTap)

        let compassButton = MKCompassButton(mapView: mapView)
        compassButton.compassVisibility = self.hideCompass ? .hidden : .visible
        compassButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(compassButton)
        let top = compassButton.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 70)
        NSLayoutConstraint.activate([
            top,
            compassButton.trailingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.trailingAnchor, constant: -16)
        ])
        context.coordinator.compassButton = compassButton
        context.coordinator.compassTopConstraint = top

        container.addSubview(mapView)
        container.bringSubviewToFront(compassButton)
        context.coordinator.container = container
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        context.coordinator.parent = self
        guard let mapView = context.coordinator.mapView else { return }

        // 更新指南針可見性
        if let compass = context.coordinator.compassButton {
            compass.compassVisibility = hideCompass ? .hidden : .visible
            context.coordinator.compassTopConstraint?.constant = container.bounds.width > container.bounds.height ? 70 : 150
        }

        // 地圖模式切換（衛星3D）
        if showSatellite != context.coordinator.showSatellite || mapStyleIndex != context.coordinator.mapStyleIndex {
            context.coordinator.showSatellite = showSatellite
            context.coordinator.mapStyleIndex = mapStyleIndex
            if showSatellite {
                if #available(iOS 16.0, *) {
                    let config = MKHybridMapConfiguration()
                    config.elevationStyle = .realistic
                    mapView.preferredConfiguration = config
                } else {
                    mapView.mapType = .hybridFlyover
                }
            } else {
                if #available(iOS 16.0, *), mapStyleIndex == 1 {
                    let config = MKStandardMapConfiguration()
                    config.emphasisStyle = .muted
                    config.elevationStyle = .realistic
                    mapView.preferredConfiguration = config
                } else if #available(iOS 16.0, *) {
                    let config = MKStandardMapConfiguration()
                    mapView.preferredConfiguration = config
                } else {
                    mapView.mapType = .standard
                }
            }
        }

        if context.coordinator.lastNorthOverrideTrackingToken != northOverrideTrackingToken {
            context.coordinator.lastNorthOverrideTrackingToken = northOverrideTrackingToken
            context.coordinator.northOverrideArmed = true
        }
        let landscapeChanged = context.coordinator.isLandscape != isLandscape
        context.coordinator.isLandscape = isLandscape

        // 擴展 map frame 覆蓋全屏，同時將視覺中心偏移。
        // 用 min(0, …) 確保 frame 起點唔會離開容器左/上邊緣，避免留出空隙。
        let targetFrame = NonAdjustingMapView.displayFrame(
            in: container.bounds.size, centerOffset: CGPoint(x: centerOffsetX, y: centerOffsetY)
        )
        if centerOffsetX != context.coordinator.centerOffsetX || centerOffsetY != context.coordinator.centerOffsetY {
            context.coordinator.centerOffsetX = centerOffsetX
            context.coordinator.centerOffsetY = centerOffsetY
            UIView.animate(withDuration: 0.40, delay: 0, options: .curveEaseInOut) {
                mapView.frame = targetFrame
            }
        } else if mapView.frame != targetFrame {
            mapView.frame = targetFrame
        }

        let targetStyle: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        if mapView.overrideUserInterfaceStyle != targetStyle {
            mapView.overrideUserInterfaceStyle = targetStyle
        }

        if landscapeChanged {
            // Update headingOrientation so heading tracks screen top in new orientation
            context.coordinator.parent.locationManager.manager.headingOrientation = LocationManager.currentDeviceOrientation()
            mapView.allowCameraChange = false
            context.coordinator.autoZoomTimer?.invalidate()
            context.coordinator.autoZoomTimer = nil
        }
        context.coordinator.updateMeterDetailSelection(meterManager.selectedMeter)
        context.coordinator.updateMeterNoticeOverview(meterManager.notice)

        // 繪製停車場範圍模式：進入時建疊圖層、退出時清除，頂點變更時重畫。
        if boundaryDrawVertices != nil {
            if context.coordinator.boundaryCanvas == nil {
                context.coordinator.beginBoundaryDraw(on: mapView)
            }
            context.coordinator.refreshBoundaryCanvas()
        } else if context.coordinator.boundaryCanvas != nil {
            context.coordinator.endBoundaryDraw(on: mapView)
        }
        
        if flyTrigger > 0 && flyTrigger != context.coordinator.lastFlyTrigger {
            context.coordinator.lastFlyTrigger = flyTrigger
            if routePriorityToken == nil {
                if landscapeChanged {
                    let coordinator = context.coordinator
                    let generation = coordinator.cameraAnimationGeneration
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        guard coordinator.cameraAnimationGeneration == generation,
                              coordinator.parent.routePriorityToken == nil else { return }
                        coordinator.startTracking(useHongKongFallback: true)
                    }
                } else {
                    context.coordinator.startTracking(useHongKongFallback: true)
                }
            }
        }

        // 路线覆盖层
        if let overlay = routeOverlay {
            let tokenChanged = context.coordinator.currentRouteToken != routeOverlayToken
            let overlayChanged = context.coordinator.currentRouteOverlay == nil || context.coordinator.currentRouteOverlay !== overlay
            let animOverlay = routeAnimationOverlay
            let animChanged = context.coordinator.currentRouteAnimationOverlay !== animOverlay
            if tokenChanged || overlayChanged || animChanged {
                let coordinator = context.coordinator
                let shouldAnimateRouteZoom = tokenChanged && routeOverlayToken != nil && routeOverlayToken == routeOverlayAnimationToken
                let shouldAnimateDraw = animOverlay != nil
                coordinator.prepareRouteDrawAnimation(shouldAnimate: shouldAnimateDraw)
                if let cur = coordinator.currentRouteOverlay {
                    mapView.removeOverlay(cur)
                }
                if let cur = coordinator.currentRouteAnimationOverlay {
                    mapView.removeOverlay(cur)
                }
                coordinator.currentRouteOverlay = overlay
                coordinator.currentRouteAnimationOverlay = animOverlay
                coordinator.currentRouteToken = routeOverlayToken
                mapView.addOverlay(overlay)
                if let animOverlay = animOverlay, shouldAnimateDraw {
                    mapView.addOverlay(animOverlay)
                }

                if shouldAnimateRouteZoom && !coordinator.meterDetailTracking.isPresented {
                    coordinator.endMeterOverview()
                    coordinator.manualCameraControl = false
                    mapView.allowsUserCameraChanges = false
                    coordinator.meterDetailTracking.resume()
                    coordinator.freezeAutomaticCamera()
                    let generation = coordinator.cameraAnimationGeneration
                    // 用 Timer 手动控制缩放动画，时长 1.5 秒
                    let targetRect = overlay.boundingMapRect
                    let startCenter = mapView.camera.centerCoordinate
                    let startDistance = mapView.camera.centerCoordinateDistance
                    // 从 MKMapRect 精确计算中心和所需距离
                    let topLeft = MKMapPoint(x: targetRect.origin.x, y: targetRect.origin.y).coordinate
                    let bottomRight = MKMapPoint(x: targetRect.origin.x + targetRect.size.width,
                                                 y: targetRect.origin.y + targetRect.size.height).coordinate
                    let targetCenter = CLLocationCoordinate2D(
                        latitude: (topLeft.latitude + bottomRight.latitude) / 2,
                        longitude: (topLeft.longitude + bottomRight.longitude) / 2
                    )
                    let latSpan = abs(topLeft.latitude - bottomRight.latitude)
                    let lonSpan = abs(topLeft.longitude - bottomRight.longitude)
                    // centerCoordinateDistance 控制垂直可见范围，需要覆盖最大跨度
                    let targetDistance = max(latSpan, lonSpan) * 111000 * 4.0
                    let duration: TimeInterval = 1.5
                    let startTime = Date()
                    coordinator.flyTimer?.invalidate()
                    coordinator.flyTimer = nil
                    coordinator.autoZoomTimer?.invalidate()
                    coordinator.autoZoomTimer = nil
                    coordinator.smoothPanTimer?.invalidate()
                    coordinator.smoothPanTimer = nil
                    coordinator.pendingAutoZoom = false
                    coordinator.isFlying = true
                    mapView.allowCameraChange = true
                    context.coordinator.routeZoomTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak mapView, weak coordinator] timer in
                        guard let mapView = mapView, let coordinator = coordinator,
                              coordinator.cameraAnimationGeneration == generation else { timer.invalidate(); return }
                        let elapsed = Date().timeIntervalSince(startTime)
                        let t = min(elapsed / duration, 1.0)
                        let ease = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
                        let lat = startCenter.latitude + (targetCenter.latitude - startCenter.latitude) * ease
                        let lon = startCenter.longitude + (targetCenter.longitude - startCenter.longitude) * ease
                        let dist = startDistance + (targetDistance - startDistance) * ease
                        mapView.allowCameraChange = true
                        let camera = mapView.camera
                        camera.centerCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                        camera.centerCoordinateDistance = dist
                        mapView.camera = camera
                        if t >= 1.0 {
                            timer.invalidate()
                            if coordinator.isDriving,
                               coordinator.parent.routePriorityToken != nil,
                               let anchor = mapView.userLocation.location?.coordinate ?? coordinator.parent.routePriorityAnchor {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                    guard coordinator.mapView === mapView,
                                          coordinator.cameraAnimationGeneration == generation else { return }
                                    let distance = coordinator.trackingDistance(
                                        for: CLLocation(latitude: anchor.latitude, longitude: anchor.longitude)
                                    )
                                    coordinator.flyToCoordinate(
                                        mapView: mapView,
                                        coordinate: anchor,
                                        distance: distance,
                                        duration: 1.2
                                    )
                                }
                            } else {
                                coordinator.isFlying = false
                                mapView.allowCameraChange = false
                                DispatchQueue.main.async {
                                    guard coordinator.cameraAnimationGeneration == generation else { return }
                                    coordinator.pendingAutoZoom = true
                                    coordinator.scheduleAutoZoom()
                                }
                            }
                        }
                    }
                }
            }
            if context.coordinator.currentRouteAnimationOverlay != nil, routeAnimationOverlay == nil {
                context.coordinator.prepareRouteDrawAnimation(shouldAnimate: false)
                if let cur = context.coordinator.currentRouteAnimationOverlay {
                    mapView.removeOverlay(cur)
                }
                context.coordinator.currentRouteAnimationOverlay = nil
            }
        } else if context.coordinator.currentRouteOverlay != nil {
            if let cur = context.coordinator.currentRouteOverlay {
                mapView.removeOverlay(cur)
            }
            if let cur = context.coordinator.currentRouteAnimationOverlay {
                mapView.removeOverlay(cur)
            }
            context.coordinator.currentRouteOverlay = nil
            context.coordinator.currentRouteAnimationOverlay = nil
            context.coordinator.currentRouteToken = nil
            context.coordinator.routeZoomTimer?.invalidate()
            context.coordinator.routeZoomTimer = nil
            context.coordinator.routeReturnTimer?.invalidate()
            context.coordinator.routeReturnTimer = nil
            context.coordinator.isFlying = false
            context.coordinator.pendingAutoZoom = true
            context.coordinator.prepareRouteDrawAnimation(shouldAnimate: false)
        }
        
        context.coordinator.syncParkingAnnotations(parkingPoints: parkingPoints, titlePrefixesByID: parkingPointTitlePrefixesByID)
        var displayedMeters = meterManager.visibleMeters
        if let overviewMeter = context.coordinator.meterOverviewMeter,
           !displayedMeters.contains(where: { $0.id == overviewMeter.id }) {
            displayedMeters.append(overviewMeter)
        }
        context.coordinator.meterLayer.sync(map: mapView, meters: displayedMeters, manager: meterManager)
        context.coordinator.updateMeterNavigationTarget(
            id: meterNavigationTargetID,
            coordinate: meterNavigationTargetCoordinate
        )
        context.coordinator.applyParkingSelection(selectedParkingPointID: selectedParkingPointID)
        context.coordinator.updateParkingPopupCameraFreeze(selectedParkingPointID)

        // 持續跟隨模式：啟動/停止 heading 追蹤 timer
        if continuousFollow && !hkDetailMode {
            context.coordinator.startContinuousHeading()
        } else {
            context.coordinator.stopContinuousHeading()
        }

        // 香港地圖細覽模式：飛到香港、停用自動追蹤
        if hkDetailMode != context.coordinator.lastHkDetailMode {
            context.coordinator.lastHkDetailMode = hkDetailMode
            if hkDetailMode {
                context.coordinator.enterHkDetailMode(mapView: mapView)
            } else {
                context.coordinator.exitHkDetailMode()
            }
        }
        if context.coordinator.meterDetailTracking.isWaiting && context.coordinator.autoZoomTimer == nil {
            context.coordinator.scheduleAutoZoom()
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.stopUpdates()
        coordinator.mapView?.onTouchBegan = nil
        coordinator.mapView?.onTouchEnded = nil
        coordinator.mapView?.stopObservingTouches()
        coordinator.mapView?.delegate = nil
        coordinator.mapView = nil
        coordinator.container = nil
    }

    class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        let meterLayer = MeterMapLayer()
        var parent: MapView
        weak var mapView: NonAdjustingMapView?
        weak var container: UIView?
#if DEBUG
        let cameraChecksEnabled = ProcessInfo.processInfo.arguments.contains("--map-camera-checks")

        private func updateCameraCheckValue() {
            guard cameraChecksEnabled, let mapView else { return }
            let camera = mapView.camera
            container?.accessibilityValue = "latitude=\(camera.centerCoordinate.latitude) longitude=\(camera.centerCoordinate.longitude) zoom=\(camera.centerCoordinateDistance) manual=\(manualCameraControl ? 1 : 0) held=\(isUserInteracting ? 1 : 0) flying=\(isFlying ? 1 : 0)"
        }
#endif
        var lastFlyTrigger = 0
        var isLandscape = false
        var showSatellite = false
        var mapStyleIndex = 0
        /// 繪製停車場範圍模式嘅疊圖層（頂點／橡皮筋／中心指針）。
        var boundaryCanvas: BoundaryDrawCanvas?
        var isBoundaryDrawing: Bool { parent.boundaryDrawVertices != nil }
        private var cameraSnapshotTimer: Timer?
        var autoZoomTimer: Timer?
        var flyTimer: Timer?
        var isFlying = false {
            didSet {
#if DEBUG
                updateCameraCheckValue()
#endif
            }
        }
        var hasShownHighAltitude = false
        var hasInitialized = false
        var lastNorthOverrideTrackingToken: Int = 0
        var northOverrideArmed = false
        weak var compassButton: MKCompassButton?
        var compassTopConstraint: NSLayoutConstraint?
        var centerOffsetX: CGFloat = 0
        var centerOffsetY: CGFloat = 0
        var lastHkDetailMode = false
        private var hkAnnotations: [MKPointAnnotation] = []

        // Custom route color from settings
        private var routeColor: UIColor {
            let hex = UserDefaults.standard.string(forKey: "bestRouteColorHex") ?? "BCBA1E"
            return UIColor(hex: hex)
        }

        // 运动检测相关
        private var speedObserver: AnyCancellable?
        private var locationObserver: AnyCancellable?
        private var lastSpeed: Double = 0
        var isDriving: Bool = false
        private var realTimeUpdateTimer: Timer?
        private var lastCameraUpdateTime: TimeInterval = 0
        private var isUserInteracting = false
        var pendingAutoZoom = false
        var manualCameraControl = false
        var cameraAnimationGeneration = 0
        private var meterOverviewID: UUID?
        private(set) var meterOverviewMeter: ParkingMeter?
        private var handledMeterNoticeID: UUID?
        private var selectedMeterOverviewID: String?
        private var lastOverviewFit: Date = .distantPast
        private var drivingDisplayLink: CADisplayLink?
        private var drivingMotion = MapCameraMotion()
        private var lastTrackingFrame: CFTimeInterval = 0
        private var lastTrackingDistanceUpdate: CFTimeInterval = 0
        private var cachedDrivingDistance = MapCameraMotion.drivingDistance
        private var cachedSoftTracking = true
        private var lastTrackingFlightTarget: CLLocationCoordinate2D?
        var meterDetailTracking = MeterDetailTrackingGate()

        private var automaticCameraPaused: Bool {
            isUserInteracting || manualCameraControl || meterOverviewID != nil ||
                meterDetailTracking.isPaused || parent.hkDetailMode || isBoundaryDrawing ||
                parent.selectedParkingPointID != nil
        }

        func freezeAutomaticCamera() {
            cameraAnimationGeneration &+= 1
            lastTrackingFlightTarget = nil
            stopDrivingTracking()
            stopContinuousHeading()
            flyTimer?.invalidate()
            flyTimer = nil
            smoothPanTimer?.invalidate()
            smoothPanTimer = nil
            routeZoomTimer?.invalidate()
            routeZoomTimer = nil
            routeReturnTimer?.invalidate()
            routeReturnTimer = nil
            autoZoomTimer?.invalidate()
            autoZoomTimer = nil
            realTimeUpdateTimer?.invalidate()
            realTimeUpdateTimer = nil
            isFlying = false
            pendingAutoZoom = false
            if let mapView, let camera = mapView.camera.copy() as? MKMapCamera {
                mapView.allowCameraChange = true
                mapView.setCamera(camera, animated: false)
                mapView.allowCameraChange = false
            }
        }

        func endMeterOverview() {
            guard meterOverviewID != nil else { return }
            meterOverviewID = nil
            meterOverviewMeter = nil
            freezeAutomaticCamera()
        }

        func updateMeterNoticeOverview(_ notice: MeterNotice?) {
            if meterOverviewID != nil && meterOverviewID != notice?.id {
                endMeterOverview()
                if !automaticCameraPaused, let mapView,
                   let location = validTrackingLocation {
                    flyToCoordinate(mapView: mapView, coordinate: location.coordinate,
                                    distance: trackingDistance(for: location), duration: 1.1)
                }
            }
            guard let notice, handledMeterNoticeID != notice.id,
                  notice.kind == .nearby || notice.kind == .destination else { return }
            // A touch always wins; do not replay this same prompt's camera move after the touch.
            guard let mapView, let container, container.bounds.width > 0, container.bounds.height > 0,
                  mapView.bounds.width > 0, mapView.bounds.height > 0 else { return }
            handledMeterNoticeID = notice.id
            guard !manualCameraControl, !isUserInteracting, !meterDetailTracking.isPaused,
                  !parent.hkDetailMode, parent.locationManager.speed >= 5,
                  let location = validTrackingLocation else { return }
            freezeAutomaticCamera()
            meterOverviewID = notice.id
            meterOverviewMeter = notice.meter
            fitMeterOverview(user: location.coordinate, mapView: mapView, container: container)
        }

        private func overviewVisibleRect(mapView: MKMapView, container: UIView) -> CGRect {
            let viewport = mapView.convert(container.bounds, from: container)
            let horizontal = min(max(container.safeAreaInsets.left, container.safeAreaInsets.right) + 24, viewport.width * 0.25)
            let vertical = max(container.safeAreaInsets.top + 70, container.safeAreaInsets.bottom + 150)
            return viewport.insetBy(dx: horizontal, dy: min(vertical, viewport.height * 0.28))
        }

        private func fitMeterOverview(user: CLLocationCoordinate2D, meter: ParkingMeter? = nil,
                                      mapView: NonAdjustingMapView, container: UIView) {
            guard let meter = meter ?? meterOverviewMeter else { return }
            let viewport = overviewVisibleRect(mapView: mapView, container: container)
            let padding = UIEdgeInsets(
                top: max(0, viewport.minY), left: max(0, viewport.minX),
                bottom: max(0, mapView.bounds.maxY - viewport.maxY),
                right: max(0, mapView.bounds.maxX - viewport.maxX)
            )
            freezeAutomaticCamera()
            let generation = cameraAnimationGeneration
            let start = mapView.camera.copy() as! MKMapCamera
            let target = mapView.cameraFitting(
                MapCameraMotion.overviewRect(user: user, meter: meter.coordinate.wgs84ToGCJ02),
                edgePadding: padding
            )
            lastOverviewFit = Date()
            isFlying = true
            let startTime = CACurrentMediaTime()
            let update: @MainActor @Sendable () -> Void = { [weak self, weak mapView] in
                guard let self, let mapView, self.cameraAnimationGeneration == generation else { return }
                let progress = min(1, (CACurrentMediaTime() - startTime) / MapCameraMotion.meterOverviewDuration)
                let ease = MapCameraMotion.flightProgress(progress)
                let camera = start.copy() as! MKMapCamera
                camera.centerCoordinate = CLLocationCoordinate2D(
                    latitude: start.centerCoordinate.latitude + (target.centerCoordinate.latitude - start.centerCoordinate.latitude) * ease,
                    longitude: start.centerCoordinate.longitude + (target.centerCoordinate.longitude - start.centerCoordinate.longitude) * ease
                )
                camera.centerCoordinateDistance = start.centerCoordinateDistance + (target.centerCoordinateDistance - start.centerCoordinateDistance) * ease
                camera.pitch = start.pitch + (target.pitch - start.pitch) * ease
                camera.heading = start.heading + MapCameraMotion.headingDelta(from: start.heading, to: target.heading) * ease
                mapView.allowCameraChange = true
                mapView.setCamera(progress >= 1 ? target : camera, animated: false)
                mapView.allowCameraChange = false
                if progress >= 1 {
                    self.flyTimer?.invalidate()
                    self.flyTimer = nil
                    self.isFlying = false
                    self.lastOverviewFit = Date()
                }
            }
            let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { _ in
                MainActor.assumeIsolated { update() }
            }
            flyTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }

        func resumeAutomaticCamera() {
            guard !meterDetailTracking.isPresented, !isBoundaryDrawing,
                  parent.selectedParkingPointID == nil else { return }
            manualCameraControl = false
            mapView?.allowsUserCameraChanges = false
            meterDetailTracking.resume()
            endMeterOverview()
            startTracking()
            if parent.continuousFollow && !parent.hkDetailMode { startContinuousHeading() }
        }

        @MainActor
        private final class TrackingDisplayLinkTarget: NSObject {
            weak var coordinator: Coordinator?
            init(_ coordinator: Coordinator) { self.coordinator = coordinator }
            @objc func tick(_ link: CADisplayLink) {
                coordinator?.drivingTrackingFrame(link)
            }
        }

        func stopDrivingTracking() {
            drivingDisplayLink?.invalidate()
            drivingDisplayLink = nil
            lastTrackingFrame = 0
        }

        private func startDrivingTracking() {
            guard isDriving, !isFlying, !automaticCameraPaused, drivingDisplayLink == nil,
                  let location = validTrackingLocation ?? mapView?.userLocation.location else { return }
            guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 100,
                  Date().timeIntervalSince(location.timestamp) < 3 else { return }
            drivingMotion.update(location)
            drivingMotion.resetCameraVelocity()
            stopContinuousHeading()
            smoothPanTimer?.invalidate()
            smoothPanTimer = nil
            lastTrackingDistanceUpdate = 0
            let link = CADisplayLink(target: TrackingDisplayLinkTarget(self), selector: #selector(TrackingDisplayLinkTarget.tick(_:)))
            link.preferredFramesPerSecond = 60
            drivingDisplayLink = link
            link.add(to: .main, forMode: .common)
        }

        private func drivingTrackingFrame(_ link: CADisplayLink) {
            guard let mapView, isDriving, !isFlying, !automaticCameraPaused else {
                stopDrivingTracking()
                return
            }
            let now = Date()
            guard let sample = drivingMotion.sample else { return }
            let dt = lastTrackingFrame == 0 ? link.duration : link.timestamp - lastTrackingFrame
            lastTrackingFrame = link.timestamp
            if link.timestamp - lastTrackingDistanceUpdate >= 0.25 {
                cachedDrivingDistance = trackingDistance(for: sample)
                cachedSoftTracking = UserDefaults.standard.integer(forKey: "mapTrackingAnimation") == 1
                lastTrackingDistanceUpdate = link.timestamp
            }
            let alpha = MapCameraMotion.response(frameDuration: dt, soft: cachedSoftTracking)
            let camera = mapView.camera
            guard let center = drivingMotion.cameraCoordinate(from: camera.centerCoordinate, at: now,
                                                               frameDuration: dt, soft: cachedSoftTracking) else { return }
            camera.centerCoordinate = center
            camera.centerCoordinateDistance += (cachedDrivingDistance - camera.centerCoordinateDistance) * alpha
            camera.pitch += (drivingPitch - camera.pitch) * alpha
            let heading = parent.followHeading ? correctedHeading : 0
            camera.heading += MapCameraMotion.headingDelta(from: camera.heading, to: heading) * alpha
            mapView.allowCameraChange = true
            mapView.setCamera(camera, animated: false)
            mapView.allowCameraChange = false
            if now.timeIntervalSince(sample.timestamp) > MapCameraMotion.predictionHorizon,
               let target = drivingMotion.coordinate(at: now),
               CLLocation(latitude: target.latitude, longitude: target.longitude)
                .distance(from: CLLocation(latitude: camera.centerCoordinate.latitude, longitude: camera.centerCoordinate.longitude)) < 0.1 {
                stopDrivingTracking()
            }
        }

        func updateMeterDetailPresentation(_ presented: Bool) {
            guard meterDetailTracking.setPresented(presented) else { return }
            autoZoomTimer?.invalidate()
            autoZoomTimer = nil
            pendingAutoZoom = false
            if presented {
                endMeterOverview()
                freezeAutomaticCamera()
            } else {
                // Closing during the longer overview flight starts the usual
                // five-second return countdown immediately, not after the flight.
                freezeAutomaticCamera()
                scheduleAutoZoom()
            }
        }

        private var lastParkingPopupCameraID: UUID?

        /// 停車點／逗留點彈窗：開咗就凍結自動鏡頭（連進行緊嘅五秒回航都取消，
        /// 唔畀鏡頭追返用戶位置），直向將個點移到螢幕中線靠上、留低下半方畀彈窗，
        /// 橫屏就對齊屏幕正中（唔做 35% 上移），彈窗自己喺右手邊。
        /// 閂咗先跟咪錶詳情一樣開始五秒回航倒數。
        func updateParkingPopupCameraFreeze(_ selectedID: UUID?) {
            guard lastParkingPopupCameraID != selectedID else { return }
            lastParkingPopupCameraID = selectedID
            freezeAutomaticCamera()
            if let selectedID {
                if let mapView, let container {
                    focusParkingPopupPoint(pointID: selectedID, mapView: mapView, container: container)
                }
            } else {
                scheduleAutoZoom()
            }
        }

        /// 彈窗開咗對位停車點：直向對齊屏幕水平正中、垂直約 35% 高度
        /// （指標視覺中心約 28%，同截圖一致），下半方留畀彈窗詳情；
        /// 橫屏對齊屏幕正中（上下左右圍住中心），唔做 35% 上移。
        private func focusParkingPopupPoint(pointID: UUID, mapView: NonAdjustingMapView, container: UIView) {
            let representative = parkingRepresentativeByPointID[pointID] ?? pointID
            guard let anno = parkingAnnotationsByID[representative] else { return }
            let bounds = container.bounds
            guard bounds.width > 0, bounds.height > 0 else { return }
            // 橫屏：正中；直向：中線靠上 35%。
            let landscape = bounds.width >= bounds.height
            let target = CGPoint(
                x: bounds.midX,
                y: landscape ? bounds.midY : bounds.height * 0.35
            )
            let current = mapView.convert(anno.coordinate, toPointTo: container)
            let delta = CGPoint(x: target.x - current.x, y: target.y - current.y)
            guard abs(delta.x) > 2 || abs(delta.y) > 2 else { return }
            // 內容要搬移 delta；相機中心（地圖視覺中心）向反方向移，個點就會落到 target。
            let visualCenter = mapView.convert(
                CGPoint(x: mapView.bounds.midX, y: mapView.bounds.midY), to: container
            )
            let newCenterPoint = CGPoint(x: visualCenter.x - delta.x, y: visualCenter.y - delta.y)
            let newCenter = mapView.convert(newCenterPoint, toCoordinateFrom: container)
            flyParkingPopupFocus(to: newCenter, mapView: mapView)
        }

        /// 純中心位移飛行：唔郁縮放／俯仰／指北，淨係將相機中心移到目標（計好嘅「點對齊」中心）。
        private func flyParkingPopupFocus(to targetCenter: CLLocationCoordinate2D, mapView: NonAdjustingMapView) {
            let startCenter = mapView.camera.centerCoordinate
            let distance = mapView.camera.centerCoordinateDistance
            let duration: TimeInterval = 0.7
            let startTime = Date()
            flyTimer?.invalidate()
            isFlying = true
            mapView.allowCameraChange = true
            flyTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak mapView, weak self] timer in
                guard let mapView, let self else { timer.invalidate(); return }
                let elapsed = Date().timeIntervalSince(startTime)
                let t = min(elapsed / duration, 1.0)
                let ease = MapCameraMotion.flightProgress(t)
                let camera = mapView.camera
                camera.centerCoordinate = CLLocationCoordinate2D(
                    latitude: startCenter.latitude + (targetCenter.latitude - startCenter.latitude) * ease,
                    longitude: startCenter.longitude + (targetCenter.longitude - startCenter.longitude) * ease
                )
                camera.centerCoordinateDistance = distance
                mapView.camera = camera
                if t >= 1.0 {
                    timer.invalidate()
                    self.flyTimer = nil
                    self.isFlying = false
                    mapView.allowCameraChange = false
                }
            }
        }

        func updateMeterDetailSelection(_ meter: ParkingMeter?, forceOverview: Bool = false) {
            updateMeterDetailPresentation(meter != nil)
            guard let meter else {
                selectedMeterOverviewID = nil
                return
            }
            guard forceOverview || selectedMeterOverviewID != meter.id,
                  let mapView, let container,
                  container.bounds.width > 0, container.bounds.height > 0 else { return }
            selectedMeterOverviewID = meter.id
            guard let location = validTrackingLocation ?? parent.locationManager.mapReferenceLocation else { return }
            // An explicit selection may frame both points, but must not restart follow mode.
            freezeAutomaticCamera()
            fitMeterOverview(user: location.coordinate, meter: meter, mapView: mapView, container: container)
        }
        
        // 驾驶速度阈值（km/h）
        private let drivingSpeedThreshold: Double = 15
        fileprivate let drivingTrackingDistance = MapCameraMotion.drivingDistance
        fileprivate let idleTrackingDistance: CLLocationDistance = 800
        fileprivate let drivingPitch: CGFloat = 42
        fileprivate let idlePitch: CGFloat = 0      // 靜止追蹤平面視角
        
        // 柔软追踪相关
        private var softLatVelocity: Double = 0   // 纬度速度（度/帧）
        private var softLonVelocity: Double = 0   // 经度速度（度/帧）
        private var softLastGPSTime: TimeInterval = 0
        private var softTargetCenter: CLLocationCoordinate2D?
        private var softIsDecelerating = false
        private var softDecelerationProgress: Double = 0
        private var softTargetDistance: CLLocationDistance = 800
        var currentRouteOverlay: MKPolyline?
        var currentRouteAnimationOverlay: MKPolyline?
        var currentRouteToken: UUID?
        var routeZoomTimer: Timer?
        var routeReturnTimer: Timer?
        private var routeDrawTimer: Timer?
        private weak var routeDrawRenderer: AnimatedPolylineRenderer?
        private var pendingRouteDrawAnimation = false
        private weak var routeFullRenderer: MKPolylineRenderer?
        private var fullRouteAlpha: Double = 1
        private var animRouteAlpha: Double = 0
        private var routeFadeTimer: Timer?
        private var parkingAnnotationHash: Int = 0
        private var parkingAnnotationsByID: [UUID: ParkingPointAnnotation] = [:]
        private var parkingRepresentativeByPointID: [UUID: UUID] = [:]
        private var parkingRangeOverlay: MKOverlay?
        private var parkingRangeHash: Int?
        private weak var parkingRangeRenderer: MKOverlayPathRenderer?
        /// 進行中嘅綠色範圍彈出彈入（同一時間一個；舊收埋緊就即刻完成）
        private struct ParkingRangePopJob {
            let renderer: MKOverlayPathRenderer
            let appear: Bool
            let removing: MKOverlay?
            let start: Date
            let duration: TimeInterval
        }
        private var parkingRangePopJob: ParkingRangePopJob?
        private var parkingRangePopTimer: Timer?
        /// addOverlay 之後 renderer 可能遲啲先到——到咗就即刻播彈出
        private var parkingRangeAppearQueued = false
        private var meterNavigationTargetID: String?
        private var meterNavigationTargetCoordinate: CLLocationCoordinate2D?
        private var meterNavigationTrackingDistance: CLLocationDistance?
        private var forceMeterAnnotationsApart = false
        private var isApplyingParkingSelection = false
        private var lastAppliedSelectedParkingPointID: UUID?
        private var hasAppliedParkingSelection = false
        private var isParkingPointDragging = false
        private var parkingDragGrabOffset = CGPoint.zero
        private var draggingParkingPointID: UUID?
        private weak var draggingParkingAnnotation: ParkingPointAnnotation?
        private var dragTargetCoordinate: CLLocationCoordinate2D?
        private var parkingDragTimer: Timer?
        private var isHKDragging = false
        private weak var draggingHKAnnotation: MKPointAnnotation?
        private var hkDragTitle: String?
        private var hkDragTimer: Timer?

        init(_ parent: MapView) {
            self.parent = parent
            super.init()
            isDriving = parent.locationManager.speed >= drivingSpeedThreshold
            setupLocationObserver()
        }
        
        deinit {
            drivingDisplayLink?.invalidate()
            speedObserver?.cancel()
            locationObserver?.cancel()
            cameraSnapshotTimer?.invalidate()
            autoZoomTimer?.invalidate()
            flyTimer?.invalidate()
            smoothPanTimer?.invalidate()
            hkDragTimer?.invalidate()
            realTimeUpdateTimer?.invalidate()
            routeZoomTimer?.invalidate()
            routeReturnTimer?.invalidate()
            routeDrawTimer?.invalidate()
            routeFadeTimer?.invalidate()
            parkingDragTimer?.invalidate()
            continuousHeadingTimer?.invalidate()
        }

        func stopUpdates() {
            stopDrivingTracking()
            speedObserver?.cancel()
            locationObserver?.cancel()
            cameraSnapshotTimer?.invalidate()
            cameraSnapshotTimer = nil
            autoZoomTimer?.invalidate()
            flyTimer?.invalidate()
            smoothPanTimer?.invalidate()
            hkDragTimer?.invalidate()
            realTimeUpdateTimer?.invalidate()
            routeZoomTimer?.invalidate()
            routeReturnTimer?.invalidate()
            routeDrawTimer?.invalidate()
            routeFadeTimer?.invalidate()
            parkingDragTimer?.invalidate()
            continuousHeadingTimer?.invalidate()
        }

        func prepareRouteDrawAnimation(shouldAnimate: Bool) {
            routeDrawTimer?.invalidate()
            routeDrawTimer = nil
            routeFadeTimer?.invalidate()
            routeFadeTimer = nil
            routeDrawRenderer?.progress = 1
            routeDrawRenderer?.setNeedsDisplay()
            routeDrawRenderer = nil
            if shouldAnimate {
                fullRouteAlpha = 0
                animRouteAlpha = 1
            } else {
                fullRouteAlpha = 1
                animRouteAlpha = 0
            }
            if let renderer = routeFullRenderer {
                renderer.strokeColor = routeColor.withAlphaComponent(fullRouteAlpha)
                renderer.setNeedsDisplay()
            }
            pendingRouteDrawAnimation = shouldAnimate
        }

        func attachRouteDrawRenderer(_ renderer: AnimatedPolylineRenderer) {
            guard pendingRouteDrawAnimation else { return }
            pendingRouteDrawAnimation = false
            routeDrawTimer?.invalidate()
            routeDrawTimer = nil
            routeDrawRenderer = renderer
            renderer.progress = 0
            renderer.strokeColor = routeColor.withAlphaComponent(animRouteAlpha)
            renderer.setNeedsDisplay()
            if let renderer = routeFullRenderer {
                renderer.strokeColor = routeColor.withAlphaComponent(fullRouteAlpha)
                renderer.setNeedsDisplay()
            }
            let duration: TimeInterval = 1.6
            let start = Date()
            routeDrawTimer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                guard let self = self, let renderer = self.routeDrawRenderer else { return }
                let t = min(Date().timeIntervalSince(start) / duration, 1.0)
                let u: Double
                if t < 0.5 {
                    u = 4 * t * t * t
                } else {
                    u = 1 - pow(-2 * t + 2, 3) / 2
                }
                renderer.progress = u
                renderer.setNeedsDisplay()
                if t >= 1.0 {
                    self.routeDrawTimer?.invalidate()
                    self.routeDrawTimer = nil
                    self.startRouteFade()
                }
            }
            if let timer = routeDrawTimer {
                RunLoop.main.add(timer, forMode: .common)
            }
        }

        private func startRouteFade() {
            routeFadeTimer?.invalidate()
            routeFadeTimer = nil
            let duration: TimeInterval = 0.22
            let start = Date()
            routeFadeTimer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                let t = min(Date().timeIntervalSince(start) / duration, 1.0)
                let ease = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
                self.fullRouteAlpha = ease
                self.animRouteAlpha = 1 - ease
                if let renderer = self.routeFullRenderer {
                    renderer.strokeColor = self.routeColor.withAlphaComponent(self.fullRouteAlpha)
                    renderer.setNeedsDisplay()
                }
                if let renderer = self.routeDrawRenderer {
                    renderer.strokeColor = self.routeColor.withAlphaComponent(self.animRouteAlpha)
                    renderer.setNeedsDisplay()
                }
                if t >= 1 {
                    self.routeFadeTimer?.invalidate()
                    self.routeFadeTimer = nil
                    self.fullRouteAlpha = 1
                    self.animRouteAlpha = 0
                    self.routeDrawRenderer?.progress = 1
                    self.routeDrawRenderer?.setNeedsDisplay()
                }
            }
            if let timer = routeFadeTimer {
                RunLoop.main.add(timer, forMode: .common)
            }
        }
        
        /// LocationManager 已設 headingOrientation 跟隨裝置方向，
        /// 所以 heading 直接就係螢幕座標系嘅方向，唔使再手動修正。
        private var correctedHeading: CLLocationDirection {
            parent.locationManager.heading
        }

        func startContinuousHeading() {
            guard continuousHeadingTimer == nil, !automaticCameraPaused,
                  !isFlying, drivingDisplayLink == nil else { return }
            let frameInterval = 1.0 / 60.0
            continuousHeadingTimer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { [weak self] _ in
                guard let self, let mapView = self.mapView,
                      !self.automaticCameraPaused, !self.isFlying else { return }
                let targetHeading = self.correctedHeading
                let currentHeading = mapView.camera.heading
                let headingDiff = targetHeading - currentHeading
                let normalizedDiff = atan2(sin(headingDiff * .pi / 180), cos(headingDiff * .pi / 180)) * 180 / .pi
                guard abs(normalizedDiff) > 0.3 else { return }
                mapView.allowCameraChange = true
                let camera = mapView.camera
                camera.heading = currentHeading + normalizedDiff * 0.12
                mapView.setCamera(camera, animated: false)
                mapView.allowCameraChange = false
            }
            RunLoop.main.add(continuousHeadingTimer!, forMode: .common)
        }

        func stopContinuousHeading() {
            continuousHeadingTimer?.invalidate()
            continuousHeadingTimer = nil
        }

        // MARK: - 香港地圖細覽模式

        func enterHkDetailMode(mapView: MKMapView) {
            // 停止所有追蹤
            endMeterOverview()
            freezeAutomaticCamera()
            isDriving = false
            pendingAutoZoom = false
            isUserInteracting = false

            // 飛到香港
            let hkCenter = CLLocationCoordinate2D(latitude: 22.3200, longitude: 114.1700)
            if let nm = mapView as? NonAdjustingMapView { nm.allowCameraChange = true }
            let camera = MKMapCamera()
            camera.centerCoordinate = hkCenter
            camera.centerCoordinateDistance = 80000
            camera.heading = 0
            camera.pitch = 0
            mapView.setCamera(camera, animated: true)
            if let nm = mapView as? NonAdjustingMapView { nm.allowCameraChange = false }

            // 加入香港地點標注
            addHkAnnotations(mapView: mapView)
        }

        func exitHkDetailMode() {
            guard let mapView else { return }
            removeHkAnnotations(mapView: mapView)
            pendingAutoZoom = true
        }

        private static let hkOverridesKey = "HKLocationOverrides"

        private static func loadHKOverrides() -> [String: CLLocationCoordinate2D] {
            guard let data = UserDefaults.standard.dictionary(forKey: hkOverridesKey) as? [String: [String: Double]] else { return [:] }
            var result: [String: CLLocationCoordinate2D] = [:]
            for (name, dict) in data {
                if let lat = dict["lat"], let lon = dict["lon"] {
                    result[name] = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                }
            }
            return result
        }

        private static func saveHKOverride(name: String, coordinate: CLLocationCoordinate2D) {
            var data = UserDefaults.standard.dictionary(forKey: hkOverridesKey) as? [String: [String: Double]] ?? [:]
            data[name] = ["lat": coordinate.latitude, "lon": coordinate.longitude]
            UserDefaults.standard.set(data, forKey: hkOverridesKey)
        }

        private func addHkAnnotations(mapView: MKMapView) {
            removeHkAnnotations(mapView: mapView)
            let locations = HKTaxiExamLocations.all
            let overrides = Self.loadHKOverrides()
            for loc in locations {
                let anno = MKPointAnnotation()
                if let saved = overrides[loc.name] {
                    anno.coordinate = saved.wgs84ToGCJ02
                } else {
                    anno.coordinate = loc.coordinate.wgs84ToGCJ02
                }
                anno.title = loc.name
                anno.subtitle = loc.category.rawValue
                mapView.addAnnotation(anno)
                hkAnnotations.append(anno)
            }
        }

        private func removeHkAnnotations(mapView: MKMapView) {
            mapView.removeAnnotations(hkAnnotations)
            hkAnnotations.removeAll()
        }

        private func setupLocationObserver() {
            speedObserver = parent.locationManager.$speed
                .dropFirst()
                .sink { [weak self] newSpeed in
                    self?.handleSpeedChange(newSpeed)
                }
            locationObserver = parent.locationManager.$lastLocation
                .dropFirst()
                .compactMap { $0 }
                .sink { [weak self] location in
                    guard let self = self, self.isDriving, !self.isFlying,
                          !self.automaticCameraPaused else { return }
                    let now = Date().timeIntervalSince1970
                    let interval: TimeInterval = UserDefaults.standard.bool(forKey: "highFrequencyTracking") ? 0.12 : 0.5
                    guard now - self.lastCameraUpdateTime >= interval else { return }
                    self.lastCameraUpdateTime = now
                    guard location.horizontalAccuracy >= 0,
                          CLLocationCoordinate2DIsValid(location.coordinate) else { return }
                    self.drivingMotion.update(location)
                    self.startDrivingTracking()
                }
        }
        
        private func handleSpeedChange(_ speed: Double) {
            let wasDriving = isDriving
            isDriving = speed >= drivingSpeedThreshold
            guard !automaticCameraPaused else { return }
            
            if isDriving && !wasDriving {
                // 开始驾驶：不取消飞行，让飞行完成到第一个GPS点
                // 飞行完成后 locationObserver 会自动接管追蹤
                autoZoomTimer?.invalidate()
                autoZoomTimer = nil
                pendingAutoZoom = false
                // 停止smoothPanTimer，让locationObserver接管
                smoothPanTimer?.invalidate()
                smoothPanTimer = nil
                startDrivingTracking()
            } else if !isDriving && wasDriving {
                // 停止驾驶，停止实时更新，回到正常模式
                stopRealTimeUpdates()
                pendingAutoZoom = true
            }
        }
        
        private func startRealTimeUpdates() {
            realTimeUpdateTimer?.invalidate()
            autoZoomTimer?.invalidate()
            startDrivingTracking()
        }
        
        private func stopRealTimeUpdates() {
            stopDrivingTracking()
            realTimeUpdateTimer?.invalidate()
            realTimeUpdateTimer = nil
        }

        func updateMeterNavigationTarget(id: String?, coordinate: CLLocationCoordinate2D?) {
            meterNavigationTargetCoordinate = coordinate
            guard id != meterNavigationTargetID else { return }

            meterNavigationTargetID = id
            meterNavigationTrackingDistance = nil
            forceMeterAnnotationsApart = false
            if let mapView {
                meterLayer.setClusteringEnabled(true, map: mapView)
            }
        }

        fileprivate func trackingDistance(for location: CLLocation) -> CLLocationDistance {
            let normalDistance = isDriving ? drivingTrackingDistance : idleTrackingDistance
            guard let mapView,
                  let targetID = meterNavigationTargetID,
                  let targetCoordinate = meterNavigationTargetCoordinate else {
                return normalDistance
            }
            let navigationDistance = drivingTrackingDistance

            let remaining = location.distance(from: CLLocation(
                latitude: targetCoordinate.latitude,
                longitude: targetCoordinate.longitude
            ))
            guard remaining <= 700 else {
                meterNavigationTrackingDistance = nil
                if forceMeterAnnotationsApart {
                    forceMeterAnnotationsApart = false
                    meterLayer.setClusteringEnabled(true, map: mapView)
                }
                return navigationDistance
            }

            // Proximity supplies a gentle baseline. Cluster membership then drives
            // additional steps, so dense meter rows are not tied to one guessed altitude.
            let proximityDistance = max(220, min(navigationDistance, remaining * 1.7 + 180))
            var targetDistance = min(meterNavigationTrackingDistance ?? navigationDistance, proximityDistance)
            let targetIsClustered = meterLayer.containsTargetInCluster(map: mapView, targetID: targetID)

            if targetIsClustered && !forceMeterAnnotationsApart {
                targetDistance = max(120, min(targetDistance, mapView.camera.centerCoordinateDistance * 0.72))
                if targetDistance <= 120.5 {
                    forceMeterAnnotationsApart = true
                    meterLayer.setClusteringEnabled(false, map: mapView)
                }
            }

            meterNavigationTrackingDistance = targetDistance
            return targetDistance
        }
        
        private func updateMapPosition() {
            guard let mapView = mapView,
                  let location = mapView.userLocation.location,
                  !isFlying else { return }
            
            let targetCenter = CLLocationCoordinate2D(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
            let targetDistance = trackingDistance(for: location)
            let targetPitch: CGFloat = isDriving ? drivingPitch : idlePitch

            mapView.allowCameraChange = true

            let camera = mapView.camera
            camera.centerCoordinate = targetCenter
            camera.centerCoordinateDistance = targetDistance
            camera.pitch = targetPitch
            mapView.setCamera(camera, animated: true)

            mapView.allowCameraChange = false
        }

        var smoothPanTimer: Timer?
        private var continuousHeadingTimer: Timer?
        private var smoothFromCenter = CLLocationCoordinate2D()
        private var smoothToCenter = CLLocationCoordinate2D()
        private var smoothFromDistance: CLLocationDistance = 800
        private var smoothToDistance: CLLocationDistance = 800
        private var smoothFromHeading: CLLocationDirection = 0
        private var smoothToHeading: CLLocationDirection = 0
        private var smoothFromPitch: CGFloat = 0
        private var smoothToPitch: CGFloat = 0
        private var smoothProgress: TimeInterval = 0
        private let smoothDuration: TimeInterval = 0.6

        private func smoothUpdateMapPosition(location: CLLocation) {
            guard let mapView = mapView, !isFlying, !meterDetailTracking.isPaused else { return }

            let useSoft = UserDefaults.standard.integer(forKey: "mapTrackingAnimation") == 1

            if useSoft {
                softUpdateMapPosition(location: location)
            } else {
                standardUpdateMapPosition(location: location)
            }
        }


        /// 根據當前 heading 將螢幕像素偏移轉換為地理 (lat, lon) 偏移
        /// pixels > 0 = 螢幕往右偏移（camera 往右，藍點往左）
        func pixelOffsetToCoordinate(_ pixels: CGFloat, lat: Double, dist: Double, heading: Double) -> (lat: Double, lon: Double) {
            guard let mapView = mapView, pixels != 0 else { return (0, 0) }
            let frameW = Double(max(mapView.frame.width, 1))
            let frameH = Double(max(mapView.frame.height, 1))
            let pitchRad = Double(mapView.camera.pitch) * .pi / 180
            let cosFactor = max(cos(pitchRad), 0.1)
            // 每像素對應的度數（緯度/經度）
            let latPerPixel = dist / (6371000.0 * frameH * cosFactor) * (180.0 / .pi)
            let lonPerPixel = dist / (6371000.0 * cos(lat * .pi / 180) * frameW * cosFactor) * (180.0 / .pi)
            // heading 旋轉：螢幕左 → 地理方向
            let headingRad = -heading * .pi / 180
            let p = Double(pixels)
            let dLat = p * (sin(headingRad) * latPerPixel)
            let dLon = p * (cos(headingRad) * lonPerPixel)
            return (dLat, dLon)
        }

        private func standardUpdateMapPosition(location: CLLocation) {
            guard let mapView = mapView, !isFlying else { return }

            smoothPanTimer?.invalidate()

            smoothFromCenter = mapView.camera.centerCoordinate
            smoothFromDistance = mapView.camera.centerCoordinateDistance
            smoothFromHeading = mapView.camera.heading
            smoothFromPitch = mapView.camera.pitch
            smoothToCenter = CLLocationCoordinate2D(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
            smoothToDistance = trackingDistance(for: location)
            smoothToHeading = parent.followHeading ? correctedHeading : 0
            smoothToPitch = isDriving ? drivingPitch : idlePitch
            smoothProgress = 0
            
            let startTime = Date()
            smoothPanTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] timer in
                guard let self = self, !self.isUserInteracting else { return }
                let elapsed = Date().timeIntervalSince(startTime)
                let t = min(elapsed / self.smoothDuration, 1.0)
                let ease = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
                
                let lat = self.smoothFromCenter.latitude + (self.smoothToCenter.latitude - self.smoothFromCenter.latitude) * ease
                let lon = self.smoothFromCenter.longitude + (self.smoothToCenter.longitude - self.smoothFromCenter.longitude) * ease
                let dist = self.smoothFromDistance + (self.smoothToDistance - self.smoothFromDistance) * ease
                let hdg = self.smoothFromHeading + (self.smoothToHeading - self.smoothFromHeading) * ease
                let pitch = self.smoothFromPitch + (self.smoothToPitch - self.smoothFromPitch) * ease

                mapView.allowCameraChange = true
                let camera = mapView.camera
                camera.centerCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                camera.centerCoordinateDistance = dist
                camera.heading = hdg
                camera.pitch = pitch
                mapView.setCamera(camera, animated: false)
                mapView.allowCameraChange = false
                
                if t >= 1.0 {
                    timer.invalidate()
                    self.smoothPanTimer = nil
                }
            }
        }
        
        private func softUpdateMapPosition(location: CLLocation) {
            guard let mapView = mapView, !isFlying else { return }

            let now = Date().timeIntervalSince1970
            softLastGPSTime = now
            softTargetDistance = trackingDistance(for: location)
            softTargetCenter = CLLocationCoordinate2D(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
            softIsDecelerating = false
            softDecelerationProgress = 0
            
            // 如果没有在运行，启动定时器
            if smoothPanTimer == nil {
                softStartAnimation()
            }
        }
        
        private func softStartAnimation() {
            guard let mapView = mapView else { return }
            
            smoothPanTimer?.invalidate()
            
            let frameInterval = 1.0 / 60.0
            smoothPanTimer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { [weak self] timer in
                guard let self = self else { timer.invalidate(); return }
                self.softTick(frameInterval: frameInterval)
            }
        }
        
        private func softTick(frameInterval: TimeInterval) {
            guard let mapView = mapView, let target = softTargetCenter, !isUserInteracting else { return }
            
            let currentCenter = mapView.camera.centerCoordinate
            let now = Date().timeIntervalSince1970
            let timeSinceLastGPS = now - softLastGPSTime
            
            // GPS更新频率为0.12s/0.5s，阈值需大于更新间隔
            if timeSinceLastGPS > 0.5 && !softIsDecelerating {
                softIsDecelerating = true
                softDecelerationProgress = 0
            }
            
            if softIsDecelerating {
                // 减速阶段: 2秒内直线减速到目标
                softDecelerationProgress += frameInterval / 2.0
                let t = min(softDecelerationProgress, 1.0)
                let ease = 1 - (1 - t) * (1 - t)  // ease-out: 1-(1-t)^2

                // 当前速度 = 剩余距离 * ease
                let remainingLat = target.latitude - currentCenter.latitude
                let remainingLon = target.longitude - currentCenter.longitude

                let lat = currentCenter.latitude + remainingLat * ease
                let lon = currentCenter.longitude + remainingLon * ease

                mapView.allowCameraChange = true
                let camera = mapView.camera
                camera.centerCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                camera.centerCoordinateDistance += (softTargetDistance - camera.centerCoordinateDistance) * ease
                let targetPitchSmooth: CGFloat = isDriving ? drivingPitch : idlePitch
                let currentPitchSmooth = camera.pitch
                camera.pitch = currentPitchSmooth + (targetPitchSmooth - currentPitchSmooth) * ease
                let targetHeadingSmooth: CLLocationDirection = parent.followHeading ? correctedHeading : 0
                let currentHeadingSmooth = camera.heading
                let headingDiffSmooth = targetHeadingSmooth - currentHeadingSmooth
                let normalizedDiffSmooth = atan2(sin(headingDiffSmooth * .pi / 180), cos(headingDiffSmooth * .pi / 180)) * 180 / .pi
                camera.heading = currentHeadingSmooth + normalizedDiffSmooth * ease
                mapView.setCamera(camera, animated: false)
                mapView.allowCameraChange = false

                if t >= 1.0 {
                    smoothPanTimer?.invalidate()
                    smoothPanTimer = nil
                    softIsDecelerating = false
                    softDecelerationProgress = 0
                }
            } else if parent.followHeading {
                mapView.allowCameraChange = true
                let camera = mapView.camera
                camera.centerCoordinateDistance += (softTargetDistance - camera.centerCoordinateDistance) * 0.15
                let targetHeading = correctedHeading
                let currentHeading = camera.heading
                let headingDiff = targetHeading - currentHeading
                let normalizedDiff = atan2(sin(headingDiff * .pi / 180), cos(headingDiff * .pi / 180)) * 180 / .pi
                camera.heading = currentHeading + normalizedDiff * 0.15
                mapView.setCamera(camera, animated: false)
                mapView.allowCameraChange = false
            } else {
                // 正常阶段：保持当前速度移动
                let deltaLat = target.latitude - currentCenter.latitude
                let deltaLon = target.longitude - currentCenter.longitude
                let distance = sqrt(deltaLat * deltaLat + deltaLon * deltaLon)
                
                // 计算目标速度（基于GPS更新频率和距离）
                let targetSpeed = distance * 4.0  // 约0.25秒到达目标
                
                // 平滑调整速度（保持当前速度，渐变到目标速度）
                let blendFactor = 0.15  // 越小越平滑
                let newSpeed = softLatVelocity * (1 - blendFactor) + targetSpeed * blendFactor
                
                // 计算方向
                if distance > 0.000001 {
                    let dirLat = deltaLat / distance
                    let dirLon = deltaLon / distance
                    
                    // 更新速度（保持速度，调整方向）
                    softLatVelocity = dirLat * newSpeed
                    softLonVelocity = dirLon * newSpeed
                }
                
                // 应用速度
                let newLat = currentCenter.latitude + softLatVelocity * frameInterval
                let newLon = currentCenter.longitude + softLonVelocity * frameInterval
                
                mapView.allowCameraChange = true
                let camera = mapView.camera
                camera.centerCoordinate = CLLocationCoordinate2D(latitude: newLat, longitude: newLon)
                camera.centerCoordinateDistance += (softTargetDistance - camera.centerCoordinateDistance) * 0.15
                let targetPitchSoft: CGFloat = isDriving ? drivingPitch : idlePitch
                let currentPitchSoft = camera.pitch
                camera.pitch = currentPitchSoft + (targetPitchSoft - currentPitchSoft) * 0.15
                let targetHeadingSoft: CLLocationDirection = parent.followHeading ? correctedHeading : 0
                let currentHeadingSoft = camera.heading
                let headingDiffSoft = targetHeadingSoft - currentHeadingSoft
                let normalizedDiffSoft = atan2(sin(headingDiffSoft * .pi / 180), cos(headingDiffSoft * .pi / 180)) * 180 / .pi
                camera.heading = currentHeadingSoft + normalizedDiffSoft * 0.15
                mapView.setCamera(camera, animated: false)
                mapView.allowCameraChange = false
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }

        func beginManualCameraControl() {
            guard !isUserInteracting else { return }
            manualCameraControl = true
            isUserInteracting = true
            mapView?.allowsUserCameraChanges = true
            endMeterOverview()
            freezeAutomaticCamera()
#if DEBUG
            updateCameraCheckValue()
#endif
        }

        func endManualCameraControl() {
            hasInitialized = true
            isUserInteracting = false
            manualCameraControl = true
            pendingAutoZoom = true
            if !meterDetailTracking.isPresented {
                pendingAutoZoom = false
                scheduleAutoZoom()
            }
#if DEBUG
            updateCameraCheckValue()
#endif
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if gestureRecognizer.name == "parkingPointTap" {
                // 畫範圍模式：唔好搶 touch（parkingTap 認到會 cancel 個 touch，
                // 會影響畫布／地圖操作），等 handleParkingTap 個 guard 之外多重保障
                guard !isBoundaryDrawing, let mapView else { return false }
                return parkingAnnotation(at: touch.location(in: mapView)) != nil
            }
            guard gestureRecognizer.name == "parkingPointDrag", let mapView else { return true }
            return hasDraggableAnnotation(at: touch.location(in: mapView), on: mapView)
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer.name == "parkingPointDrag", let mapView else { return true }
            guard gestureRecognizer.numberOfTouches == 1 else { return false }
            return hasDraggableAnnotation(at: gestureRecognizer.location(in: mapView), on: mapView)
        }

        private func hasDraggableAnnotation(at point: CGPoint, on mapView: MKMapView) -> Bool {
            return mapView.annotations.contains { annotation in
                let draggable = annotation is ParkingPointAnnotation ||
                    hkAnnotations.contains(where: { $0 === annotation })
                guard draggable, let view = mapView.view(for: annotation) else { return false }
                return hypot(view.center.x - point.x, view.center.y - point.y) <= 44
            }
        }

        private func parkingAnnotation(at point: CGPoint) -> ParkingPointAnnotation? {
            guard let mapView else { return nil }
            return mapView.annotations.compactMap { $0 as? ParkingPointAnnotation }.filter {
                guard let view = mapView.view(for: $0) else { return false }
                return view.bounds.contains(mapView.convert(point, to: view))
            }.min {
                guard let a = mapView.view(for: $0), let b = mapView.view(for: $1) else { return false }
                let first = hypot(a.center.x - point.x, a.center.y - point.y)
                let second = hypot(b.center.x - point.x, b.center.y - point.y)
                if abs(first - second) < 1, $0.isLatest != $1.isLatest { return $0.isLatest }
                return first < second
            }
        }

        // MARK: - 繪製停車場範圍模式

        /// 進入繪製模式：加疊圖層、放平鏡頭（跟影片：北向上、無傾斜）、凍結自動鏡頭。
        func beginBoundaryDraw(on mapView: NonAdjustingMapView) {
            if boundaryCanvas == nil {
                let canvas = BoundaryDrawCanvas(frame: mapView.bounds)
                canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                canvas.mapView = mapView
                mapView.addSubview(canvas)
                boundaryCanvas = canvas
            }
            mapView.isPitchEnabled = false
            mapView.isRotateEnabled = false
            endMeterOverview()
            freezeAutomaticCamera()
            // 「加點」透過呢個 provider 攞指針（mapView.center）嘅座標——唔設就一個點都加唔到。
            parent.boundaryDrawBridge?.centerCoordinateProvider = { [weak mapView] in
                mapView?.centerCoordinate.gcj02ToWGS84
            }
            let focus = parent.boundaryDrawBridge?.initialFocus
            parent.boundaryDrawBridge?.initialFocus = nil
            mapView.allowCameraChange = true
            let camera: MKMapCamera
            if let focus {
                camera = MKMapCamera()
                camera.centerCoordinate = focus.coordinate
                camera.centerCoordinateDistance = focus.distance
            } else {
                camera = mapView.camera
            }
            camera.pitch = 0
            camera.heading = 0
            mapView.setCamera(camera, animated: true)
            mapView.allowCameraChange = false
            refreshBoundaryCanvas()
        }

        /// 退出繪製模式：移除疊圖層並還原地圖手勢。唔會自動飛返用戶位置。
        func endBoundaryDraw(on mapView: NonAdjustingMapView) {
            parent.boundaryDrawBridge?.centerCoordinateProvider = nil
            boundaryCanvas?.removeFromSuperview()
            boundaryCanvas = nil
            mapView.isPitchEnabled = true
            mapView.isRotateEnabled = true
        }

        /// 同步頂點到疊圖層並重畫（SwiftUI 狀態更新時呼叫）。
        func refreshBoundaryCanvas() {
            guard let canvas = boundaryCanvas else { return }
            canvas.frame = canvas.superview?.bounds ?? canvas.frame
            canvas.superview?.bringSubviewToFront(canvas)
            let vertices = parent.boundaryDrawVertices ?? []
            canvas.vertices = vertices.map { $0.coordinate.wgs84ToGCJ02 }
            canvas.shapeIsValid = ParkingBoundaryGeometry.isValid(vertices)
            canvas.setNeedsDisplay()
        }

        @objc func handleParkingTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, !isParkingPointDragging, !isBoundaryDrawing, let mapView,
                  let annotation = parkingAnnotation(at: gesture.location(in: mapView)) else { return }
            ParkingMeterManager.shared.selectedMeter = nil
            parent.onSelectParkingPoint(annotation.pointID)
        }

        /// 點擊地圖空白處收縮膠囊，不影響 MapKit 的 pan/pinch/rotate。
        @objc func handleBlankTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let mapView else { return }
            // 撳中泊車點等 annotation 時唔觸發，保留 annotation 選擇行為
            for annotation in mapView.annotations where !(annotation is MKUserLocation) {
                guard let view = mapView.view(for: annotation) else { continue }
                let p = gesture.location(in: view)
                if view.bounds.contains(p) { return }
            }
            // 真係撳空白位：閂停車彈窗（唔靠 MapKit 嘅 deselect，免得同誤判搶 selection 糾纏）
            parent.onSelectParkingPoint(nil)
            parent.onMapBlankTap?()
        }

        @objc func handleParkingDrag(_ gesture: UILongPressGestureRecognizer) {
            guard let mapView, !isBoundaryDrawing else { return }
            let pt = gesture.location(in: mapView)
            
            func beginUserInteractionIfNeeded() {
                if !isUserInteracting {
                    isFlying = false
                    flyTimer?.invalidate()
                    flyTimer = nil
                    autoZoomTimer?.invalidate()
                    autoZoomTimer = nil
                    realTimeUpdateTimer?.invalidate()
                    realTimeUpdateTimer = nil
                    smoothPanTimer?.invalidate()
                    smoothPanTimer = nil
                    mapView.allowCameraChange = false
                    pendingAutoZoom = false
                }
                isUserInteracting = true
            }
            
            func nearestParkingAnnotation(at point: CGPoint) -> ParkingPointAnnotation? {
                let candidates = mapView.annotations.compactMap { $0 as? ParkingPointAnnotation }
                var best: (anno: ParkingPointAnnotation, dist: CGFloat)?
                for a in candidates {
                    guard let view = mapView.view(for: a) else { continue }
                    let d = hypot(view.center.x - point.x, view.center.y - point.y)
                    if d <= 44 {
                        if let cur = best {
                            if d < cur.dist { best = (a, d) }
                        } else {
                            best = (a, d)
                        }
                    }
                }
                return best?.anno
            }

            func nearestHKAnnotation(at point: CGPoint) -> MKPointAnnotation? {
                let candidates = mapView.annotations.compactMap { a -> MKPointAnnotation? in a as? MKPointAnnotation }.filter { a in hkAnnotations.contains(where: { hk in hk === a }) }
                var best: (anno: MKPointAnnotation, dist: CGFloat)?
                for a in candidates {
                    guard let view = mapView.view(for: a) else { continue }
                    let d = hypot(view.center.x - point.x, view.center.y - point.y)
                    if d <= 44 {
                        if let cur = best {
                            if d < cur.dist { best = (a, d) }
                        } else {
                            best = (a, d)
                        }
                    }
                }
                return best?.anno
            }
            
            switch gesture.state {
            case .began:
                if let anno = nearestParkingAnnotation(at: pt) {
                    beginUserInteractionIfNeeded()
                    isParkingPointDragging = true
                    parent.onSelectParkingPoint(nil)
                    isApplyingParkingSelection = true
                    mapView.deselectAnnotation(anno, animated: false)
                    isApplyingParkingSelection = false
                    draggingParkingPointID = anno.pointID
                    draggingParkingAnnotation = anno
                    let anchor = mapView.convert(anno.coordinate, toPointTo: mapView)
                    parkingDragGrabOffset = CGPoint(x: pt.x - anchor.x, y: pt.y - anchor.y)
                    dragTargetCoordinate = anno.coordinate
                    mapView.isScrollEnabled = false
                    mapView.isRotateEnabled = false
                    mapView.isZoomEnabled = false
                    mapView.isPitchEnabled = false

                    parkingDragTimer?.invalidate()
                    parkingDragTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                        guard let self else { return }
                        guard self.isParkingPointDragging, let anno = self.draggingParkingAnnotation, let target = self.dragTargetCoordinate else { return }
                        let cur = anno.coordinate
                        let a = 0.18
                        let lat = cur.latitude + (target.latitude - cur.latitude) * a
                        let lon = cur.longitude + (target.longitude - cur.longitude) * a
                        anno.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    }
                    RunLoop.current.add(parkingDragTimer!, forMode: .common)
                } else if let anno = nearestHKAnnotation(at: pt) {
                    beginUserInteractionIfNeeded()
                    parent.onSelectHKLocation(nil)
                    isHKDragging = true
                    draggingHKAnnotation = anno
                    hkDragTitle = anno.title
                    dragTargetCoordinate = mapView.convert(pt, toCoordinateFrom: mapView)
                    mapView.isScrollEnabled = false
                    mapView.isRotateEnabled = false
                    mapView.isZoomEnabled = false
                    mapView.isPitchEnabled = false

                    hkDragTimer?.invalidate()
                    hkDragTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                        guard let self else { return }
                        guard self.isHKDragging, let anno = self.draggingHKAnnotation, let target = self.dragTargetCoordinate else { return }
                        let cur = anno.coordinate
                        let a = 0.18
                        let lat = cur.latitude + (target.latitude - cur.latitude) * a
                        let lon = cur.longitude + (target.longitude - cur.longitude) * a
                        anno.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    }
                    RunLoop.current.add(hkDragTimer!, forMode: .common)
                } else {
                    return
                }
                
            case .changed:
                if isParkingPointDragging || isHKDragging {
                    let offset = isParkingPointDragging ? parkingDragGrabOffset : .zero
                    dragTargetCoordinate = mapView.convert(CGPoint(x: pt.x - offset.x, y: pt.y - offset.y), toCoordinateFrom: mapView)
                }

            case .ended, .cancelled, .failed:
                if isParkingPointDragging {
                    isParkingPointDragging = false
                    hasInitialized = true
                    isUserInteracting = false
                    pendingAutoZoom = true
                    mapView.isScrollEnabled = true
                    mapView.isRotateEnabled = true
                    mapView.isZoomEnabled = true
                    mapView.isPitchEnabled = true

                    parkingDragTimer?.invalidate()
                    parkingDragTimer = nil

                    if let id = draggingParkingPointID, let anno = draggingParkingAnnotation {
                        if gesture.state == .ended, let target = dragTargetCoordinate { anno.coordinate = target }
                        parent.onMoveParkingPoint(id, anno.coordinate)
                    }
                    draggingParkingPointID = nil
                    draggingParkingAnnotation = nil
                    dragTargetCoordinate = nil
                } else if isHKDragging {
                    isHKDragging = false
                    hasInitialized = true
                    isUserInteracting = false
                    pendingAutoZoom = true
                    mapView.isScrollEnabled = true
                    mapView.isRotateEnabled = true
                    mapView.isZoomEnabled = true
                    mapView.isPitchEnabled = true

                    hkDragTimer?.invalidate()
                    hkDragTimer = nil

                    if let anno = draggingHKAnnotation, let title = hkDragTitle {
                        Self.saveHKOverride(name: title, coordinate: anno.coordinate.gcj02ToWGS84)
                    }
                    draggingHKAnnotation = nil
                    hkDragTitle = nil
                    dragTargetCoordinate = nil
                } else {
                    return
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    guard let self else { return }
                    self.scheduleAutoZoom()
                }
                
            default:
                break
            }
        }

        private var validTrackingLocation: CLLocation? {
            guard !parent.locationManager.isGPSLost,
                  let location = parent.locationManager.lastLocation,
                  location.horizontalAccuracy >= 0,
                  CLLocationCoordinate2DIsValid(location.coordinate) else {
                return nil
            }
            return location
        }

        private func fallbackTrackingDistance(for location: CLLocation) -> CLLocationDistance {
            guard location.horizontalAccuracy >= 0 else { return 8000 }
            return max(3000, min(12000, location.horizontalAccuracy * 4))
        }

        func startTracking(useHongKongFallback: Bool = false) {
            guard let mapView = mapView, !automaticCameraPaused else { return }

            let preciseLocation = validTrackingLocation
            let referenceLocation = preciseLocation ?? parent.locationManager.mapReferenceLocation
            if !hasShownHighAltitude {
                let location = referenceLocation ?? hongKongMapFallback
                showHighAltitudeView(mapView: mapView, location: location)
                let minimumDistance = preciseLocation == nil
                    ? fallbackTrackingDistance(for: location) : nil
                flyToLocation(mapView: mapView, location: location, minimumDistance: minimumDistance)
                return
            }

            // 正常的飞行动画
            flyTimer?.invalidate()
            flyTimer = nil
            isFlying = false
            if let location = preciseLocation {
                flyToLocation(mapView: mapView, location: location)
            } else if let location = referenceLocation {
                flyToLocation(mapView: mapView, location: location,
                              minimumDistance: fallbackTrackingDistance(for: location))
            } else if useHongKongFallback {
                flyToLocation(mapView: mapView, location: hongKongMapFallback,
                              minimumDistance: 8000)
            } else {
                pendingAutoZoom = true
            }
        }

        private func showHighAltitudeView(mapView: NonAdjustingMapView, location: CLLocation) {
            hasShownHighAltitude = true
            
            mapView.allowCameraChange = true
            
            let camera = MKMapCamera()
            camera.centerCoordinate = location.coordinate
            camera.centerCoordinateDistance = 50000
            mapView.setCamera(camera, animated: false)
            
            mapView.allowCameraChange = false
            
            hasInitialized = true
            parent.savedRegion = mapView.region
            
            pendingAutoZoom = false
        }

        func scheduleAutoZoom() {
            guard mapView != nil, !meterDetailTracking.isPresented, !isBoundaryDrawing,
                  parent.selectedParkingPointID == nil,
                  meterOverviewID == nil, !isFlying,
                  (!isDriving || meterDetailTracking.isWaiting || manualCameraControl), !isUserInteracting else { return }
            autoZoomTimer?.invalidate()
            let generation = cameraAnimationGeneration
            autoZoomTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
                guard let self = self, !self.meterDetailTracking.isPresented,
                      self.meterOverviewID == nil, !self.isFlying,
                      self.parent.selectedParkingPointID == nil,
                      (!self.isDriving || self.meterDetailTracking.isWaiting || self.manualCameraControl),
                      !self.isUserInteracting else { return }
                DispatchQueue.main.async {
                    guard self.cameraAnimationGeneration == generation,
                          !self.meterDetailTracking.isPresented, self.meterOverviewID == nil,
                          self.parent.selectedParkingPointID == nil,
                          !self.isUserInteracting else { return }
                    self.resumeAutomaticCamera()
                }
            }
        }

        private func trackingFlightTarget(fallback: CLLocationCoordinate2D, at date: Date) -> CLLocationCoordinate2D {
            guard isDriving, let location = validTrackingLocation,
                  location.horizontalAccuracy <= 100 else { return lastTrackingFlightTarget ?? fallback }
            drivingMotion.update(location)
            let target = drivingMotion.coordinate(at: date) ?? lastTrackingFlightTarget ?? fallback
            lastTrackingFlightTarget = target
            return target
        }

        private func flyToLocation(mapView: NonAdjustingMapView, location: CLLocation,
                                   minimumDistance: CLLocationDistance? = nil) {
            guard !automaticCameraPaused else { return }
            freezeAutomaticCamera()
            autoZoomTimer?.invalidate()
            autoZoomTimer = nil
            isFlying = true
            let targetCenter = CLLocationCoordinate2D(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
            let targetDistance = max(trackingDistance(for: location), minimumDistance ?? 0)
            let targetPitchVal: CGFloat = isDriving ? drivingPitch : idlePitch
            let startCenter = mapView.centerCoordinate
            let startHeading = mapView.camera.heading
            let startPitch = mapView.camera.pitch
            let targetHeading: CLLocationDirection = northOverrideArmed ? 0 : (parent.followHeading ? correctedHeading : 0)
            // 首次从高空飞下来（加载瓦片），后续用当前高度
            let startDistance: CLLocationDistance = hasShownHighAltitude
                ? mapView.camera.centerCoordinateDistance
                : max(mapView.camera.centerCoordinateDistance, 50000)
            mapView.allowCameraChange = true

            let duration: TimeInterval = 4.5
            let startTime = Date()
            flyTimer?.invalidate()

            flyTimer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak mapView, weak self] timer in
                guard let mapView = mapView, let self = self else { timer.invalidate(); return }
                let now = Date()
                let elapsed = now.timeIntervalSince(startTime)
                let t = min(elapsed / duration, 1.0)
                let posEase = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
                let distT = max(0, min(1, (t - 0.3) / 0.7))
                let distEase = distT < 0.5 ? 16 * distT * distT * distT * distT * distT : 1 - pow(-2 * distT + 2, 5) / 2

                let liveTarget = self.trackingFlightTarget(fallback: targetCenter, at: now)
                let lat = startCenter.latitude + (liveTarget.latitude - startCenter.latitude) * posEase
                let lon = startCenter.longitude + (liveTarget.longitude - startCenter.longitude) * posEase
                let dist = startDistance + (targetDistance - startDistance) * distEase
                let pitch = startPitch + (targetPitchVal - startPitch) * posEase

                let camera = mapView.camera
                camera.centerCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                camera.centerCoordinateDistance = dist
                camera.pitch = pitch
                camera.heading = startHeading + MapCameraMotion.headingDelta(from: startHeading, to: targetHeading) * posEase
                mapView.camera = camera

                if t >= 1.0 {
                    timer.invalidate()
                    self.flyTimer = nil
                    self.isFlying = false
                    self.northOverrideArmed = false
                    mapView.allowCameraChange = false
                    DispatchQueue.main.async {
                        if self.isDriving {
                            self.startRealTimeUpdates()
                        } else {
                            self.pendingAutoZoom = true
                        }
                    }
                }
            }
            RunLoop.main.add(flyTimer!, forMode: .common)
        }

        func flyToCoordinate(mapView: NonAdjustingMapView, coordinate: CLLocationCoordinate2D, distance: CLLocationDistance, duration: TimeInterval) {
            guard !automaticCameraPaused else { return }
            freezeAutomaticCamera()
            autoZoomTimer?.invalidate()
            autoZoomTimer = nil
            routeReturnTimer?.invalidate()
            routeReturnTimer = nil
            isFlying = true
            let startCenter = mapView.camera.centerCoordinate
            let startDistance = mapView.camera.centerCoordinateDistance
            let startHeading = mapView.camera.heading
            let startPitch = mapView.camera.pitch
            let targetPitchVal: CGFloat = isDriving ? drivingPitch : idlePitch
            let targetHeading: CLLocationDirection = parent.followHeading ? correctedHeading : 0
            mapView.allowCameraChange = true
            let startTime = Date()
            routeReturnTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak mapView, weak self] timer in
                guard let mapView = mapView, let self = self else { timer.invalidate(); return }
                let now = Date()
                let elapsed = now.timeIntervalSince(startTime)
                let t = min(elapsed / duration, 1.0)
                let ease = MapCameraMotion.flightProgress(t)
                let liveTarget = self.trackingFlightTarget(fallback: coordinate, at: now)
                let lat = startCenter.latitude + (liveTarget.latitude - startCenter.latitude) * ease
                let lon = startCenter.longitude + (liveTarget.longitude - startCenter.longitude) * ease
                let dist = startDistance + (distance - startDistance) * ease
                let pitch = startPitch + (targetPitchVal - startPitch) * ease

                let camera = mapView.camera
                camera.centerCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                camera.centerCoordinateDistance = dist
                camera.pitch = pitch
                camera.heading = startHeading + MapCameraMotion.headingDelta(from: startHeading, to: targetHeading) * ease
                mapView.camera = camera
                if t >= 1.0 {
                    timer.invalidate()
                    self.routeReturnTimer = nil
                    self.isFlying = false
                    mapView.allowCameraChange = false
                    DispatchQueue.main.async {
                        if self.isDriving {
                            self.startRealTimeUpdates()
                        } else {
                            self.pendingAutoZoom = self.currentRouteOverlay == nil
                        }
                    }
                }
            }
        }

        /// 繪製模式：地圖一郁就重畫橡皮筋／指針，令即時預覽跟手。
        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            boundaryCanvas?.setNeedsDisplay()
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
#if DEBUG
            updateCameraCheckValue()
#endif
            // Save a trailing snapshot without rebuilding the SwiftUI page on every tracking frame.
            if hasInitialized && cameraSnapshotTimer == nil {
                let timer = Timer(timeInterval: 0.25, repeats: false) { [weak self, weak mapView] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.cameraSnapshotTimer = nil
                        guard let mapView else { return }
                        let camera = mapView.camera
                        let saved = self.parent.savedCamera
                        if saved?.centerCoordinate.latitude != camera.centerCoordinate.latitude ||
                            saved?.centerCoordinate.longitude != camera.centerCoordinate.longitude ||
                            saved?.centerCoordinateDistance != camera.centerCoordinateDistance ||
                            saved?.heading != camera.heading || saved?.pitch != camera.pitch {
                            self.parent.savedRegion = mapView.region
                            self.parent.savedCamera = camera.copy() as? MKMapCamera
                        }
                    }
                }
                cameraSnapshotTimer = timer
                RunLoop.main.add(timer, forMode: .common)
            }
            // 飞行结束或用户操作结束，地图静止后启动5秒倒数
            if pendingAutoZoom && !meterDetailTracking.isPresented && meterOverviewID == nil && !isFlying &&
                parent.selectedParkingPointID == nil &&
                (!isDriving || meterDetailTracking.isWaiting || manualCameraControl) && !isUserInteracting {
                pendingAutoZoom = false
                scheduleAutoZoom()
            }
        }

        func syncParkingAnnotations(parkingPoints: [ParkingPointRecord], titlePrefixesByID: [UUID: String]) {
            guard !isParkingPointDragging else { return }
            guard let mapView else { return }
            let latestPointID = parkingPoints.max(by: { $0.createdAt < $1.createdAt })?.id
            var hasher = Hasher()
            hasher.combine(ParkingFloorStore.shared.floorMode.rawValue)
            hasher.combine(ParkingFloorStore.shared.mapRevision)
            hasher.combine(parent.selectedParkingPointID)
            for p in parkingPoints {
                hasher.combine(p.id)
                hasher.combine(p.latitude)
                hasher.combine(p.longitude)
                hasher.combine(p.createdAt.timeIntervalSince1970)
                hasher.combine(p.predictedFloorIndex)
                hasher.combine(p.manualFloorIndex)
                hasher.combine(p.effectiveFloorIndex)
                hasher.combine(p.isAutomotive)
                hasher.combine(titlePrefixesByID[p.id] ?? "")
                hasher.combine(p.meterTag ?? "")
                if let c = p.confidence {
                    hasher.combine(c)
                }
            }
            let h = hasher.finalize()
            guard h != parkingAnnotationHash else { return }
            parkingAnnotationHash = h
            let visibleIDs = Set(parkingPoints.map(\.id))
            let groups = ParkingFloorStore.shared.recordGroups.filter { visibleIDs.contains($0.latest.id) }
            parkingRepresentativeByPointID = [:]
            // 標示「未套用過」，等 applyParkingSelection 重新套用一次。
            // 唔可以直接將 lastAppliedSelectedParkingPointID 整成 nil——
            // 咁樣 selectedParkingPointID == nil 時會撞正 nil == nil 短路，
            // deselect 唔會執行，個點就會一直保持變大。
            hasAppliedParkingSelection = false
            isApplyingParkingSelection = true
            defer { isApplyingParkingSelection = false }
            var next: [UUID: ParkingPointAnnotation] = [:]
            next.reserveCapacity(groups.count)
            for group in groups {
                let p = group.records.first { $0.id == parent.selectedParkingPointID } ?? group.latest
                for record in group.records { parkingRepresentativeByPointID[record.id] = p.id }
                // Convert WGS-84 to GCJ-02 for correct display on China maps
                let gcj02 = p.coordinate.wgs84ToGCJ02
                let anno: ParkingPointAnnotation
                if let existing = parkingAnnotationsByID[p.id] {
                    anno = existing
                } else {
                    anno = ParkingPointAnnotation(
                        pointID: p.id,
                        coordinate: gcj02,
                        title: nil,
                        subtitle: nil,
                        isAutomotive: p.isAutomotive
                    )
                    mapView.addAnnotation(anno)
                }
                anno.coordinate = gcj02
                anno.isAutomotive = p.isAutomotive
                anno.recordCount = group.records.count
                anno.isLatest = group.records.contains { $0.id == latestPointID }
                // Separate coincident floor groups in screen space, never by changing GPS coordinates.
                let neighbours = groups.filter {
                    $0.id.lotID == group.id.lotID &&
                    CLLocation(latitude: $0.latest.latitude, longitude: $0.latest.longitude).distance(
                        from: CLLocation(latitude: p.latitude, longitude: p.longitude)) < 12
                }.sorted { ($0.id.floor ?? Int.min) < ($1.id.floor ?? Int.min) }
                if neighbours.count > 1, let rank = neighbours.firstIndex(where: { $0.id == group.id }) {
                    anno.displayOffset = CGPoint(x: (CGFloat(rank) - CGFloat(neighbours.count - 1) / 2) * 48, y: -10)
                } else {
                    anno.displayOffset = CGPoint(x: 0, y: -10)
                }
                let baseLabel = p.isAutomotive ? String(localized: "停車點") : String(localized: "逗留點")
                if p.isAutomotive {
                    let floor = p.displayFloor ?? String(localized: "未知")
                    let suffix = (floor == String(localized: "未知")) ? String(localized: "未知") : (floor.contains("/") ? floor : "\(floor)/F")
                    let prefix = (titlePrefixesByID[p.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if let meterTag = p.meterTag {
                        // 咪錶標注延伸：「HKMU - 牧愛街 7802A咪錶 停車點 3/F」
                        let named = prefix.isEmpty ? meterTag : "\(prefix) - \(meterTag)"
                        anno.title = "\(named) \(baseLabel) \(suffix)"
                    } else {
                        let levelName = p.effectiveFloorIndex.flatMap {
                            ParkingFloorStore.shared.lot(containing: p.id)?.floorNames?[String($0)]
                        }
                        let namedLevel = ParkingFloorStore.shared.floorMode == .perVisit && levelName?.isEmpty == false
                        let baseTitle = prefix.isEmpty ? baseLabel : (namedLevel ? prefix : "\(prefix) \(baseLabel)")
                        anno.title = "\(baseTitle) \(suffix)"
                    }
                } else {
                    let prefix = (titlePrefixesByID[p.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    anno.title = prefix.isEmpty ? baseLabel : "\(prefix) \(baseLabel)"
                }
                anno.subtitle = group.records.count > 1
                    ? String(format: String(localized: "%d 次記錄"), group.records.count) : (p.address.isEmpty ? nil : p.address)
                if let view = mapView.view(for: anno) as? ScaledMarkerAnnotationView {
                    configureParkingMarker(view, annotation: anno)
                }
                next[p.id] = anno
            }
            for (id, anno) in parkingAnnotationsByID where next[id] == nil {
                mapView.removeAnnotation(anno)
            }
            parkingAnnotationsByID = next
        }

        private func configureParkingMarker(
            _ view: ScaledMarkerAnnotationView,
            annotation: ParkingPointAnnotation
        ) {
            view.canShowCallout = false
            if annotation.isAutomotive {
                view.markerTintColor = UIColor.systemOrange
                view.glyphText = annotation.recordCount > 1 ? "\(annotation.recordCount)" : "P"
            } else {
                view.markerTintColor = UIColor.systemTeal
                view.glyphText = annotation.recordCount > 1 ? "\(annotation.recordCount)" : "S"
            }
            view.titleVisibility = .visible
            view.subtitleVisibility = .visible
            view.isDraggable = false
            view.centerOffset = annotation.displayOffset
            view.displayPriority = annotation.isLatest ? .required : .defaultHigh
            // 最新停車點比其他點大 30%（用 sizeScale，唔用 transform——見 ScaledMarkerAnnotationView）
            view.sizeScale = annotation.isLatest ? 1.30 : 1.0
            view.refreshAppearanceSnapshot()
        }

        func applyParkingSelection(selectedParkingPointID: UUID?) {
            guard let mapView else { return }
            updateParkingRange(pointID: selectedParkingPointID)
            guard !isParkingPointDragging else { return }
            if hasAppliedParkingSelection, selectedParkingPointID == lastAppliedSelectedParkingPointID { return }
            hasAppliedParkingSelection = true
            lastAppliedSelectedParkingPointID = selectedParkingPointID

            isApplyingParkingSelection = true
            defer { isApplyingParkingSelection = false }

            let selectedParkingAnnos = mapView.selectedAnnotations.compactMap { $0 as? ParkingPointAnnotation }

            guard let id = selectedParkingPointID else {
                for anno in selectedParkingAnnos {
                    mapView.view(for: anno)?.setSelected(false, animated: true)
                    mapView.deselectAnnotation(anno, animated: true)
                }
                return
            }

            let representative = parkingRepresentativeByPointID[id] ?? id
            if selectedParkingAnnos.contains(where: { $0.pointID == representative }) {
                return
            }

            for anno in selectedParkingAnnos {
                mapView.view(for: anno)?.setSelected(false, animated: true)
                mapView.deselectAnnotation(anno, animated: true)
            }
            if let target = parkingAnnotationsByID[representative] {
                mapView.selectAnnotation(target, animated: true)
            }
        }

        /// 綠色範圍出現／消失要彈出彈入：加新範圍就彈出，換／閂就收埋後先移除。
        private func updateParkingRange(pointID: UUID?) {
            guard let mapView else { return }
            let lot = pointID.flatMap { ParkingFloorStore.shared.lot(containing: $0) }
            var hasher = Hasher()
            hasher.combine(lot?.id)
            hasher.combine(lot?.centerLatitude)
            hasher.combine(lot?.centerLongitude)
            hasher.combine(lot?.radiusMeters)
            hasher.combine(lot?.boundaryVertices)
            let hash = hasher.finalize()
            guard parkingRangeHash != hash else { return }
            parkingRangeHash = hash
            if let old = parkingRangeOverlay {
                let oldRenderer = parkingRangeRenderer
                parkingRangeOverlay = nil
                parkingRangeRenderer = nil
                if let oldRenderer {
                    // 彈入收細，收到尾先真正移除
                    beginParkingRangePop(renderer: oldRenderer, appear: false, removing: old)
                } else {
                    mapView.removeOverlay(old)
                }
            }
            parkingRangeAppearQueued = false
            guard let lot else { return }
            let shape: MKOverlay
            if let vertices = lot.boundaryVertices, ParkingBoundaryGeometry.isValid(vertices) {
                let coordinates = vertices.map { $0.coordinate.wgs84ToGCJ02 }
                shape = MKPolygon(coordinates: coordinates, count: coordinates.count)
            } else {
                shape = MKCircle(center: lot.centerCoordinate.wgs84ToGCJ02, radius: lot.radiusMeters)
            }
            parkingRangeOverlay = shape
            parkingRangeAppearQueued = true
            mapView.addOverlay(shape, level: .aboveRoads)
            // MapKit 多數同步要 renderer；到咗就喺 adoptParkingRangeRenderer 開始彈出
            if let renderer = parkingRangeRenderer {
                parkingRangeAppearQueued = false
                beginParkingRangePop(renderer: renderer, appear: true, removing: nil)
            }
        }

        /// rendererFor 建好綠色範圍 renderer 就記低，順便接上彈出動畫。
        private func adoptParkingRangeRenderer(_ renderer: MKOverlayPathRenderer) {
            parkingRangeRenderer = renderer
            guard parkingRangeAppearQueued else { return }
            parkingRangeAppearQueued = false
            beginParkingRangePop(renderer: renderer, appear: true, removing: nil)
        }

        private func beginParkingRangePop(renderer: MKOverlayPathRenderer, appear: Bool, removing: MKOverlay?) {
            // 上一個「收埋」未完就即刻完成，免得舊範圍殘留喺圖上
            if let job = parkingRangePopJob, !job.appear {
                job.renderer.strokeColor = .clear
                job.renderer.fillColor = .clear
                job.renderer.setNeedsDisplay()
                if let removing = job.removing { mapView?.removeOverlay(removing) }
            }
            parkingRangePopTimer?.invalidate()
            parkingRangePopTimer = nil
            applyParkingRangePop(t: 0, renderer: renderer, appear: appear)
            parkingRangePopJob = ParkingRangePopJob(
                renderer: renderer, appear: appear, removing: removing,
                start: Date(), duration: appear ? 0.38 : 0.26)
            let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tickParkingRangePop() }
            }
            parkingRangePopTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }

        private func tickParkingRangePop() {
            guard let job = parkingRangePopJob else {
                parkingRangePopTimer?.invalidate()
                parkingRangePopTimer = nil
                return
            }
            let t = CGFloat(min(1, Date().timeIntervalSince(job.start) / job.duration))
            applyParkingRangePop(t: t, renderer: job.renderer, appear: job.appear)
            guard t >= 1 else { return }
            parkingRangePopTimer?.invalidate()
            parkingRangePopTimer = nil
            parkingRangePopJob = nil
            if !job.appear, let removing = job.removing {
                mapView?.removeOverlay(removing)
            }
        }

        private func applyParkingRangePop(t: CGFloat, renderer: MKOverlayPathRenderer, appear: Bool) {
            let scale = appear ? ParkingRangePop.appearScale(t) : ParkingRangePop.dismissScale(t)
            let alpha = appear ? ParkingRangePop.appearAlpha(t) : ParkingRangePop.dismissAlpha(t)
            if let circle = renderer as? ParkingRangeRenderer {
                circle.popScale = scale
            } else if let polygon = renderer as? RoundedParkingBoundaryRenderer {
                polygon.popScale = scale
            }
            renderer.strokeColor = parkingBoundaryGreen.withAlphaComponent(0.8 * alpha)
            renderer.fillColor = parkingBoundaryGreen.withAlphaComponent(0.035 * alpha)
            renderer.setNeedsDisplay()
        }

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard let location = userLocation.location, location.horizontalAccuracy >= 0,
                  Date().timeIntervalSince(location.timestamp) < 3 else { return }
            if meterOverviewID != nil, !isFlying, let meter = meterOverviewMeter,
               let mapView = self.mapView, let container,
               Date().timeIntervalSince(lastOverviewFit) >= 0.75 {
                let visible = overviewVisibleRect(mapView: mapView, container: container)
                let userPoint = mapView.convert(location.coordinate, toPointTo: mapView)
                let meterPoint = mapView.convert(meter.coordinate.wgs84ToGCJ02, toPointTo: mapView)
                if !visible.contains(userPoint) || !visible.contains(meterPoint) {
                    fitMeterOverview(user: location.coordinate, mapView: mapView, container: container)
                }
                return
            }
            guard isDriving, !isFlying, !automaticCameraPaused else { return }
            // Keep one GPS source. MapKit's display fixes must not replace the app's speed/course sample.
            drivingMotion.update(parent.locationManager.lastLocation ?? location)
            startDrivingTracking()
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if view.annotation is MKUserLocation {
                // 藍點唔應該俾選中：萬一 MapKit 幾何 hit test 揀中咗，即刻退選，
                // 有開緊停車彈窗就搶返停車點嘅 selection
                if let annotation = view.annotation { mapView.deselectAnnotation(annotation, animated: false) }
                restoreParkingSelectionAfterSteal(mapView)
                return
            }
            let meterMembers = MeterMapLayer.members(view.annotation)
            if let meter = ParkingMeterManager.shared.representative(meterMembers) {
                updateMeterDetailSelection(meter, forceOverview: true)
                parent.onSelectParkingPoint(nil)
                parent.onSelectHKLocation(nil)
                withAnimation(.easeOut(duration: 0.28)) {
                    ParkingMeterManager.shared.select(meter)
                }
                if let annotation = view.annotation { mapView.deselectAnnotation(annotation, animated: false) }
                return
            }
            if isApplyingParkingSelection { return }
            if view.annotation is ParkingPointAnnotation {
                // Only the dedicated tap recognizer opens the capsule; a hold starts dragging.
                return
            } else if let pointAnno = view.annotation as? MKPointAnnotation,
                      hkAnnotations.contains(where: { $0 === pointAnno }),
                      let title = pointAnno.title {
                ParkingMeterManager.shared.selectedMeter = nil
                parent.onSelectHKLocation((title, pointAnno.coordinate))
            }
        }

        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            if isApplyingParkingSelection { return }
            if let parking = view.annotation as? ParkingPointAnnotation {
                // 彈窗開緊呢個點嗰陣 MapKit 無端抽走 selection（例如藍點光環大、同停車點
                // 疊埋／太近，內建 tap-to-select 判斷做藍點）→ 只係視覺俾人搶走。
                // 彈窗開關淨係跟 SwiftUI 狀態（全屏關閉層／handleBlankTap 負責閂），
                // 呢度唔好閂彈窗，下一拍靜靜雞搶返 selection 就算。
                let expected = parent.selectedParkingPointID.map { parkingRepresentativeByPointID[$0] ?? $0 }
                guard expected == parking.pointID else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self, let mapView = self.mapView else { return }
                    let current = self.parent.selectedParkingPointID.map { self.parkingRepresentativeByPointID[$0] ?? $0 }
                    guard current == parking.pointID else { return }
                    self.restoreParkingSelectionAfterSteal(mapView)
                }
            } else if let pointAnno = view.annotation as? MKPointAnnotation,
                      hkAnnotations.contains(where: { $0 === pointAnno }) {
                parent.onSelectHKLocation(nil)
            }
        }

        /// 停車點嘅 selection 俾誤判搶走後搶返（純視覺；彈窗開關跟 SwiftUI 狀態）
        private func restoreParkingSelectionAfterSteal(_ mapView: MKMapView) {
            guard let id = parent.selectedParkingPointID else { return }
            let representative = parkingRepresentativeByPointID[id] ?? id
            guard let target = parkingAnnotationsByID[representative] else { return }
            guard !mapView.selectedAnnotations.contains(where: { ($0 as? ParkingPointAnnotation) === target }) else { return }
            isApplyingParkingSelection = true
            mapView.selectAnnotation(target, animated: false)
            isApplyingParkingSelection = false
            // MapKit 嘅退選動畫可能仲播緊（標示縮細／淡出），即刻清走 in-flight 動畫，
            // 個標一次過定返喺選中狀態，唔會「漸顯消失」之後又「漸顯出來」。
            if let view = mapView.view(for: target) {
                func stripAnimations(_ layer: CALayer) {
                    layer.removeAllAnimations()
                    for sublayer in layer.sublayers ?? [] { stripAnimations(sublayer) }
                }
                stripAnimations(view.layer)
            }
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState) {
            if let anno = view.annotation as? ParkingPointAnnotation {
                if newState == .ending || newState == .canceling {
                    parent.onMoveParkingPoint(anno.pointID, anno.coordinate)
                    view.dragState = .none
                }
            } else if let pointAnno = view.annotation as? MKPointAnnotation,
                      hkAnnotations.contains(where: { $0 === pointAnno }),
                      let title = pointAnno.title,
                      newState == .ending {
                Self.saveHKOverride(name: title, coordinate: pointAnno.coordinate.gcj02ToWGS84)
                view.dragState = .none
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let view = MeterMapLayer.view(
                map: mapView,
                annotation: annotation,
                manager: .shared,
                clusteringEnabled: meterLayer.clusteringEnabled
            ) { return view }
            if annotation is MKUserLocation {
                // 藍點用不可選中嘅 view：唔好同停車點搶 hit test（見 NonSelectableUserLocationView）
                let reuseID = "NonSelectableUserLocationView"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: reuseID) as? NonSelectableUserLocationView)
                    ?? NonSelectableUserLocationView(annotation: annotation, reuseIdentifier: reuseID)
                view.annotation = annotation
                view.canShowCallout = false
                return view
            }
            if let parking = annotation as? ParkingPointAnnotation {
                let reuseID = "ParkingPointAnnotationView"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: reuseID) as? ScaledMarkerAnnotationView) ?? ScaledMarkerAnnotationView(annotation: parking, reuseIdentifier: reuseID)
                view.annotation = parking
                configureParkingMarker(view, annotation: parking)
                return view
            }
            // 香港地圖細覽模式：自定義標注
            if let pointAnno = annotation as? MKPointAnnotation, hkAnnotations.contains(where: { $0 === pointAnno }) {
                let reuseID = "HKAnnotationView"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: reuseID) as? FadingMarkerAnnotationView) ?? FadingMarkerAnnotationView(annotation: annotation, reuseIdentifier: reuseID)
                view.annotation = annotation
                view.canShowCallout = true
                view.titleVisibility = .visible
                view.subtitleVisibility = .adaptive
                let category = pointAnno.subtitle ?? ""
                switch category {
                case "醫院":
                    view.markerTintColor = UIColor.systemRed
                    view.glyphText = "🏥"
                case "政府機構":
                    view.markerTintColor = UIColor.systemBlue
                    view.glyphText = "🏛"
                case "酒店":
                    view.markerTintColor = UIColor.systemPurple
                    view.glyphText = "🏨"
                case "地標":
                    view.markerTintColor = UIColor.systemYellow
                    view.glyphText = "⭐"
                case "交通設施":
                    view.markerTintColor = UIColor.systemTeal
                    view.glyphText = "🚇"
                case "教育":
                    view.markerTintColor = UIColor.systemGreen
                    view.glyphText = "🎓"
                case "宗教":
                    view.markerTintColor = UIColor.systemIndigo
                    view.glyphText = "🛕"
                case "公園":
                    view.markerTintColor = UIColor.systemGreen
                    view.glyphText = "🌳"
                case "道路":
                    view.markerTintColor = UIColor.systemGray
                    view.glyphText = "🛣"
                case "購物":
                    view.markerTintColor = UIColor.systemPink
                    view.glyphText = "🛍"
                default:
                    view.markerTintColor = UIColor.systemOrange
                    view.glyphText = "📍"
                }
                return view
            }
            return nil
        }

        func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
            (mapView as? NonAdjustingMapView)?.annotationsDidAppear(views)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polygon = overlay as? MKPolygon, polygon === (parkingRangeOverlay as? MKPolygon) {
                let renderer = RoundedParkingBoundaryRenderer(polygon: polygon)
                renderer.strokeColor = parkingBoundaryGreen.withAlphaComponent(0.8)
                renderer.fillColor = parkingBoundaryGreen.withAlphaComponent(0.035)
                renderer.lineWidth = 1.5
                adoptParkingRangeRenderer(renderer)
                return renderer
            }
            if let circle = overlay as? MKCircle, circle === (parkingRangeOverlay as? MKCircle) {
                let renderer = ParkingRangeRenderer(circle: circle)
                renderer.strokeColor = parkingBoundaryGreen.withAlphaComponent(0.8)
                renderer.fillColor = parkingBoundaryGreen.withAlphaComponent(0.035)
                renderer.lineWidth = 1.5
                adoptParkingRangeRenderer(renderer)
                return renderer
            }
            if let polyline = overlay as? MKPolyline {
                if polyline === currentRouteOverlay {
                    let renderer = MKPolylineRenderer(polyline: polyline)
                    renderer.strokeColor = routeColor.withAlphaComponent(fullRouteAlpha)
                    renderer.lineWidth = 5
                    renderer.lineCap = .round
                    renderer.lineJoin = .round
                    routeFullRenderer = renderer
                    return renderer
                }
                if polyline === currentRouteAnimationOverlay {
                    let renderer = AnimatedPolylineRenderer(polyline: polyline)
                    renderer.strokeColor = routeColor.withAlphaComponent(animRouteAlpha)
                    renderer.lineWidth = 5
                    renderer.lineCap = .round
                    renderer.lineJoin = .round
                    attachRouteDrawRenderer(renderer)
                    return renderer
                }
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = routeColor
                renderer.lineWidth = 5
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

    }
}

final class AnimatedPolylineRenderer: MKPolylineRenderer {
    var progress: Double = 1
    private let mapPoints: [MKMapPoint]
    private let cumulative: [Double]
    private let total: Double

    override init(overlay: MKOverlay) {
        let polyline = overlay as? MKPolyline
        let count = polyline?.pointCount ?? 0
        if let polyline = polyline, count > 0 {
            let pts = polyline.points()
            var mp: [MKMapPoint] = []
            mp.reserveCapacity(count)
            for i in 0..<count {
                mp.append(pts[i])
            }
            mapPoints = mp
            var c: [Double] = Array(repeating: 0, count: count)
            if count > 1 {
                for i in 1..<count {
                    c[i] = c[i - 1] + mp[i - 1].distance(to: mp[i])
                }
            }
            cumulative = c
            total = c.last ?? 0
        } else {
            mapPoints = []
            cumulative = []
            total = 0
        }
        super.init(overlay: overlay)
    }

    override init(polyline: MKPolyline) {
        let count = polyline.pointCount
        if count > 0 {
            let pts = polyline.points()
            var mp: [MKMapPoint] = []
            mp.reserveCapacity(count)
            for i in 0..<count {
                mp.append(pts[i])
            }
            mapPoints = mp
            var c: [Double] = Array(repeating: 0, count: count)
            if count > 1 {
                for i in 1..<count {
                    c[i] = c[i - 1] + mp[i - 1].distance(to: mp[i])
                }
            }
            cumulative = c
            total = c.last ?? 0
        } else {
            mapPoints = []
            cumulative = []
            total = 0
        }
        super.init(polyline: polyline)
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard !mapPoints.isEmpty else { return }
        let t = max(0, min(progress, 1))
        if t <= 0 { return }
        if total <= 0 { return }
        let target = total * t

        var hi = cumulative.count - 1
        var lo = 0
        while lo < hi {
            let mid = (lo + hi) / 2
            if cumulative[mid] < target {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        let idx = lo

        let path = CGMutablePath()
        path.move(to: point(for: mapPoints[0]))
        if idx >= mapPoints.count - 1 {
            for i in 1..<mapPoints.count {
                path.addLine(to: point(for: mapPoints[i]))
            }
        } else {
            if idx >= 1 {
                for i in 1...idx {
                    path.addLine(to: point(for: mapPoints[i]))
                }
            }
            let prevIndex = max(0, idx - 1)
            let prevLen = cumulative[prevIndex]
            let segLen = max(0.000001, cumulative[idx] - prevLen)
            let segT = max(0, min(1, (target - prevLen) / segLen))
            let a = mapPoints[prevIndex]
            let b = mapPoints[idx]
            let x = a.x + (b.x - a.x) * segT
            let y = a.y + (b.y - a.y) * segT
            path.addLine(to: point(for: MKMapPoint(x: x, y: y)))
        }

        context.addPath(path)
        if let color = strokeColor?.cgColor {
            context.setStrokeColor(color)
        }
        let scale = UIScreen.main.scale
        let w = lineWidth
        let aligned = (w * scale).rounded(.toNearestOrAwayFromZero) / scale
        context.setLineWidth(aligned)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.strokePath()
    }
}

struct VignetteMapView: View {
    @Binding var savedRegion: MKCoordinateRegion?
    @Binding var savedCamera: MKMapCamera?
    @Binding var firstFlyTrigger: Int
    var stationaryTrackingTrigger: Int
    var northOverrideTrackingToken: Int
    var routeOverlay: MKPolyline?
    var routeAnimationOverlay: MKPolyline?
    var followHeading: Bool
    var continuousFollow: Bool = false
    var hkDetailMode: Bool = false
    var parkingPoints: [ParkingPointRecord]
    var parkingPointTitlePrefixesByID: [UUID: String]
    var selectedParkingPointID: UUID?
    var onSelectParkingPoint: (UUID?) -> Void
    var onMoveParkingPoint: (UUID, CLLocationCoordinate2D) -> Void
    var routePriorityToken: UUID?
    var routePriorityAnchor: CLLocationCoordinate2D?
    var meterNavigationTargetID: String? = nil
    var meterNavigationTargetCoordinate: CLLocationCoordinate2D? = nil
    var routeOverlayToken: UUID?
    var routeOverlayAnimationToken: UUID?
    var mapStyleIndex: Int = 0
    var showSatellite: Bool = false
    var centerOffsetX: CGFloat = 0
    var centerOffsetY: CGFloat = 0
    var hideCompass: Bool = false
    var compassBridge: MapCompassBridge? = nil
    var radialVignetteOuterOpacity: Double = 0.75
    var onMapBlankTap: (() -> Void)? = nil
    var onSelectHKLocation: ((String, CLLocationCoordinate2D)?) -> Void = { _ in }
    var boundaryDrawVertices: [ParkingBoundaryVertex]? = nil
    var boundaryDrawBridge: BoundaryDrawMapBridge? = nil
    @EnvironmentObject private var locationManager: LocationManager
    @State private var flyTrigger = 0
    @State private var isLandscape = false
    @State private var hasTriggeredFirstTime = false

    var body: some View {
        ZStack {
            MapView(savedRegion: $savedRegion, savedCamera: $savedCamera, flyTrigger: $flyTrigger, isLandscape: isLandscape, routeOverlay: routeOverlay, routeAnimationOverlay: routeAnimationOverlay, followHeading: followHeading, continuousFollow: continuousFollow, hkDetailMode: hkDetailMode, northOverrideTrackingToken: northOverrideTrackingToken, parkingPoints: parkingPoints, parkingPointTitlePrefixesByID: parkingPointTitlePrefixesByID, selectedParkingPointID: selectedParkingPointID, onSelectParkingPoint: onSelectParkingPoint, onMoveParkingPoint: onMoveParkingPoint, routePriorityToken: routePriorityToken, routePriorityAnchor: routePriorityAnchor, meterNavigationTargetID: meterNavigationTargetID, meterNavigationTargetCoordinate: meterNavigationTargetCoordinate, routeOverlayToken: routeOverlayToken, routeOverlayAnimationToken: routeOverlayAnimationToken, mapStyleIndex: mapStyleIndex, showSatellite: showSatellite, centerOffsetX: centerOffsetX, centerOffsetY: centerOffsetY, hideCompass: hideCompass, compassBridge: compassBridge, onMapBlankTap: onMapBlankTap, onSelectHKLocation: onSelectHKLocation, boundaryDrawVertices: boundaryDrawVertices, boundaryDrawBridge: boundaryDrawBridge)
                .ignoresSafeArea()

            // Minecraft green tint overlay
            if mapStyleIndex == 1 {
                Color(red: 0.29, green: 0.48, blue: 0.18)
                    .opacity(0.3)
                    .blendMode(.multiply)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: 0.45),
                        .init(color: .black.opacity(0.45), location: 0.7),
                        .init(color: .black.opacity(radialVignetteOuterOpacity), location: 1)
                    ]),
                    center: .center,
                    startRadius: min(w, h) * 0.25,
                    endRadius: max(w, h) * 0.65
                )
                .ignoresSafeArea()
                .onAppear {
                    // 開 app 已經係橫屏都要初始化，唔係會一直留喺 false。
                    let landscape = w > h
                    if landscape != isLandscape {
                        isLandscape = landscape
                    }
                }
                .onChange(of: geo.size) { _, size in
                    // 用 onChange 入面個 size 參數判斷——capture 外面嘅 w/h 會食到舊值。
                    let landscape = size.width > size.height
                    if landscape != isLandscape {
                        isLandscape = landscape
                        if routePriorityToken == nil {
                            flyTrigger += 1
                        }
                    }
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

        }
        .onChange(of: firstFlyTrigger) { _, _ in
            if routePriorityToken == nil {
                flyTrigger += 1
            }
        }
        .onChange(of: stationaryTrackingTrigger) { _, _ in
            if routePriorityToken == nil {
                flyTrigger += 1
            }
        }
    }
}

struct ReadOnlyMapView: UIViewRepresentable {
    let camera: MKMapCamera?
    var mapStyleIndex: Int = 0
    @Environment(\.colorScheme) private var colorScheme

    func makeUIView(context: Context) -> NonAdjustingMapView {
        let mapView = NonAdjustingMapView()
        mapView.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .none
        mapView.delegate = nil
        mapView.mapType = .standard
        if #available(iOS 16.0, *), mapStyleIndex == 1 {
            let config = MKStandardMapConfiguration()
            config.emphasisStyle = .muted
            config.elevationStyle = .realistic
            mapView.preferredConfiguration = config
        }
        if let camera = camera {
            mapView.allowCameraChange = true
            mapView.setCamera(camera, animated: false)
            mapView.allowCameraChange = false
        }
        return mapView
    }

    func updateUIView(_ mapView: NonAdjustingMapView, context: Context) {
        let targetStyle: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        if mapView.overrideUserInterfaceStyle != targetStyle {
            mapView.overrideUserInterfaceStyle = targetStyle
        }
        if #available(iOS 16.0, *) {
            let shouldMute = mapStyleIndex == 1
            let isMuted = (mapView.preferredConfiguration as? MKStandardMapConfiguration)?.emphasisStyle == .muted
            if shouldMute != isMuted {
                let config = MKStandardMapConfiguration()
                config.emphasisStyle = shouldMute ? .muted : .default
                mapView.preferredConfiguration = config
            }
        }
        guard let camera = camera else { return }
        let current = mapView.camera
        let needsUpdate =
            abs(current.centerCoordinate.latitude - camera.centerCoordinate.latitude) > 0.0001 ||
            abs(current.centerCoordinate.longitude - camera.centerCoordinate.longitude) > 0.0001 ||
            abs(current.heading - camera.heading) > 1 ||
            abs(current.pitch - camera.pitch) > 1 ||
            abs(current.centerCoordinateDistance - camera.centerCoordinateDistance) > 10
        if needsUpdate {
            mapView.allowCameraChange = true
            mapView.setCamera(camera, animated: false)
            mapView.allowCameraChange = false
        }
    }
}
