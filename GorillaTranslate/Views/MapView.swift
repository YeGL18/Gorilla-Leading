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

class NonAdjustingMapView: MKMapView {
    var allowCameraChange = false
    private var savedCameraBeforeLayout: MKMapCamera?

    override func setCamera(_ newCamera: MKMapCamera, animated: Bool) {
        guard allowCameraChange else { return }
        super.setCamera(newCamera, animated: animated)
    }

    override func setRegion(_ newRegion: MKCoordinateRegion, animated: Bool) {
        guard allowCameraChange else { return }
        super.setRegion(newRegion, animated: animated)
    }

    override func layoutSubviews() {
        if !allowCameraChange {
            savedCameraBeforeLayout = camera
        }
        super.layoutSubviews()
        if !allowCameraChange, let saved = savedCameraBeforeLayout {
            camera = saved
            savedCameraBeforeLayout = nil
        }
    }
}

/// 帶放大比例嘅停車點 marker。
/// MapKit 會自己寫 annotation view 嘅 `transform`（地圖跟 heading 旋轉時做反旋轉、
/// 飛行／縮放動畫時做移位），所以「最新點大 30%」唔可以直接擺落 `transform`，
/// 一被 MapKit 覆寫就返返去原大（要等到下次 configure 先再變大）。
/// 呢個 subclass 將「MapKit 嘅 transform」同「我哋嘅放大」分開：
/// 每次 MapKit 寫入都自動重新疊加放大比例。
final class ScaledMarkerAnnotationView: MKMarkerAnnotationView {
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

final class ParkingPointAnnotation: NSObject, MKAnnotation {
    let pointID: UUID
    dynamic var coordinate: CLLocationCoordinate2D
    dynamic var title: String?
    dynamic var subtitle: String?
    let isAutomotive: Bool
    var isLatest = false

    init(pointID: UUID, coordinate: CLLocationCoordinate2D, title: String?, subtitle: String?, isAutomotive: Bool = true) {
        self.pointID = pointID
        self.coordinate = coordinate
        self.title = title
        self.subtitle = subtitle
        self.isAutomotive = isAutomotive
        super.init()
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

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.userTouched(_:)))
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.userTouched(_:)))
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.userTouched(_:)))
        let rotate = UIRotationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.userTouched(_:)))
        tap.delegate = context.coordinator
        pan.delegate = context.coordinator
        pinch.delegate = context.coordinator
        rotate.delegate = context.coordinator
        mapView.addGestureRecognizer(tap)
        mapView.addGestureRecognizer(pan)
        mapView.addGestureRecognizer(pinch)
        mapView.addGestureRecognizer(rotate)

        let blankTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleBlankTap(_:)))
        mapView.addGestureRecognizer(blankTap)

        let parkingDrag = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleParkingDrag(_:)))
        parkingDrag.minimumPressDuration = 0.12
        parkingDrag.allowableMovement = 1000
        parkingDrag.cancelsTouchesInView = false
        mapView.addGestureRecognizer(parkingDrag)

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
        if showSatellite != context.coordinator.showSatellite {
            context.coordinator.showSatellite = showSatellite
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
        let targetFrame = CGRect(
            x: min(0, -centerOffsetX),
            y: min(0, -centerOffsetY),
            width: container.bounds.width + abs(centerOffsetX),
            height: container.bounds.height + abs(centerOffsetY)
        )
        if centerOffsetX != context.coordinator.centerOffsetX || centerOffsetY != context.coordinator.centerOffsetY {
            context.coordinator.centerOffsetX = centerOffsetX
            context.coordinator.centerOffsetY = centerOffsetY
            UIView.animate(withDuration: 0.40, delay: 0, options: .curveEaseInOut) {
                mapView.frame = targetFrame
            }
        } else {
            mapView.frame = targetFrame
        }

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

        if landscapeChanged {
            // Update headingOrientation so heading tracks screen top in new orientation
            context.coordinator.parent.locationManager.manager.headingOrientation = LocationManager.currentDeviceOrientation()
            mapView.allowCameraChange = false
            context.coordinator.autoZoomTimer?.invalidate()
            context.coordinator.autoZoomTimer = nil
        }
        
        if flyTrigger > 0 && flyTrigger != context.coordinator.lastFlyTrigger {
            context.coordinator.lastFlyTrigger = flyTrigger
            if routePriorityToken == nil {
                if landscapeChanged {
                    let coordinator = context.coordinator
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
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
                let shouldAnimateRouteZoom = routeOverlayToken != nil && routeOverlayToken == routeOverlayAnimationToken
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

                context.coordinator.routeZoomTimer?.invalidate()
                context.coordinator.routeZoomTimer = nil

                if !shouldAnimateRouteZoom {
                    mapView.allowCameraChange = false
                    coordinator.isFlying = false
                    coordinator.pendingAutoZoom = false
                    return
                }
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
                    guard let mapView = mapView, let coordinator = coordinator else { timer.invalidate(); return }
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
                                coordinator.pendingAutoZoom = true
                                coordinator.scheduleAutoZoom()
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
        context.coordinator.meterLayer.sync(map: mapView, meters: meterManager.visibleMeters, manager: meterManager)
        context.coordinator.updateMeterNavigationTarget(
            id: meterNavigationTargetID,
            coordinate: meterNavigationTargetCoordinate
        )
        context.coordinator.applyParkingSelection(selectedParkingPointID: selectedParkingPointID)

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
    }

    class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        let meterLayer = MeterMapLayer()
        var parent: MapView
        weak var mapView: NonAdjustingMapView?
        weak var container: UIView?
        var lastFlyTrigger = 0
        var isLandscape = false
        var showSatellite = false
        var autoZoomTimer: Timer?
        var flyTimer: Timer?
        var isFlying = false
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
        
        // 驾驶速度阈值（km/h）
        private let drivingSpeedThreshold: Double = 15
        fileprivate let drivingTrackingDistance: CLLocationDistance = 1800
        fileprivate let idleTrackingDistance: CLLocationDistance = 800
        fileprivate let drivingPitch: CGFloat = 20  // 駕駛時輕微 3D 傾斜
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
        private var meterNavigationTargetID: String?
        private var meterNavigationTargetCoordinate: CLLocationCoordinate2D?
        private var meterNavigationTrackingDistance: CLLocationDistance?
        private var forceMeterAnnotationsApart = false
        private var isApplyingParkingSelection = false
        private var lastAppliedSelectedParkingPointID: UUID?
        private var isParkingPointDragging = false
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
            setupLocationObserver()
        }
        
        deinit {
            speedObserver?.cancel()
            locationObserver?.cancel()
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
            guard continuousHeadingTimer == nil else { return }
            let frameInterval = 1.0 / 60.0
            continuousHeadingTimer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { [weak self] _ in
                guard let self, let mapView = self.mapView, !self.isUserInteracting else { return }
                // 持續跟隨：即使 isFlying 也繼續更新 heading，飛行動畫只管位置/縮放
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
            autoZoomTimer?.invalidate()
            autoZoomTimer = nil
            flyTimer?.invalidate()
            flyTimer = nil
            smoothPanTimer?.invalidate()
            smoothPanTimer = nil
            stopContinuousHeading()
            isFlying = false
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
                    guard let self = self, self.isDriving, !self.isFlying, !self.isUserInteracting else { return }
                    let now = Date().timeIntervalSince1970
                    let interval: TimeInterval = UserDefaults.standard.bool(forKey: "highFrequencyTracking") ? 0.12 : 0.5
                    guard now - self.lastCameraUpdateTime >= interval else { return }
                    self.lastCameraUpdateTime = now
                    guard location.horizontalAccuracy >= 0,
                          CLLocationCoordinate2DIsValid(location.coordinate) else { return }
                    self.smoothUpdateMapPosition(location: location)
                }
        }
        
        private func handleSpeedChange(_ speed: Double) {
            let wasDriving = isDriving
            isDriving = speed >= drivingSpeedThreshold
            
            if isDriving && !wasDriving {
                // 开始驾驶：不取消飞行，让飞行完成到第一个GPS点
                // 飞行完成后 locationObserver 会自动接管追蹤
                autoZoomTimer?.invalidate()
                autoZoomTimer = nil
                pendingAutoZoom = false
                mapView?.allowCameraChange = false
                // 停止smoothPanTimer，让locationObserver接管
                smoothPanTimer?.invalidate()
                smoothPanTimer = nil
            } else if !isDriving && wasDriving {
                // 停止驾驶，停止实时更新，回到正常模式
                stopRealTimeUpdates()
                pendingAutoZoom = true
            }
        }
        
        private func startRealTimeUpdates() {
            realTimeUpdateTimer?.invalidate()
            autoZoomTimer?.invalidate()
        }
        
        private func stopRealTimeUpdates() {
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
            guard let mapView = mapView, !isFlying else { return }

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

        @objc func userTouched(_ gesture: UIGestureRecognizer) {
            // 正在触摸中：停止所有追蹤
            if gesture.state == .began || gesture.state == .changed {
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
                    continuousHeadingTimer?.invalidate()
                    continuousHeadingTimer = nil
                    mapView?.allowCameraChange = false
                    pendingAutoZoom = false
                }
                isUserInteracting = true
                return
            }

            // 手指抬起：清除互動狀態，等地图静止后由 regionDidChangeAnimated 启动倒数
            if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
                hasInitialized = true
                isUserInteracting = false
                pendingAutoZoom = true
            }
        }

        /// 點擊地圖空白處（冇撳中任何 annotation）— 用嚟收縮展開咗嘅膠囊。
        /// 因為係 MKMapView 自己嘅 gesture，pan/pinch/rotate 完全唔受影響。
        @objc func handleBlankTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let mapView else { return }
            // 撳中泊車點等 annotation 時唔觸發，保留 annotation 選擇行為
            for annotation in mapView.annotations where !(annotation is MKUserLocation) {
                guard let view = mapView.view(for: annotation) else { continue }
                let p = gesture.location(in: view)
                if view.bounds.contains(p) { return }
            }
            parent.onMapBlankTap?()
        }

        @objc func handleParkingDrag(_ gesture: UILongPressGestureRecognizer) {
            guard let mapView else { return }
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
                    parent.onSelectParkingPoint(nil)
                    isParkingPointDragging = true
                    draggingParkingPointID = anno.pointID
                    draggingParkingAnnotation = anno
                    dragTargetCoordinate = mapView.convert(pt, toCoordinateFrom: mapView)
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
                    dragTargetCoordinate = mapView.convert(pt, toCoordinateFrom: mapView)
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
            guard let mapView = mapView, !isUserInteracting else { return }

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
            guard !isFlying && !isDriving && !isUserInteracting else { return }
            autoZoomTimer?.invalidate()
            autoZoomTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
                guard let self = self, !self.isFlying, !self.isDriving, !self.isUserInteracting else { return }
                DispatchQueue.main.async {
                    self.startTracking()
                }
            }
        }

        private func flyToLocation(mapView: NonAdjustingMapView, location: CLLocation,
                                   minimumDistance: CLLocationDistance? = nil) {
            autoZoomTimer?.invalidate()
            autoZoomTimer = nil
            isFlying = true
            let continuousFollow = parent.continuousFollow
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
                let elapsed = Date().timeIntervalSince(startTime)
                let t = min(elapsed / duration, 1.0)
                let posEase = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
                let distT = max(0, min(1, (t - 0.3) / 0.7))
                let distEase = distT < 0.5 ? 16 * distT * distT * distT * distT * distT : 1 - pow(-2 * distT + 2, 5) / 2

                let lat = startCenter.latitude + (targetCenter.latitude - startCenter.latitude) * posEase
                let lon = startCenter.longitude + (targetCenter.longitude - startCenter.longitude) * posEase
                let dist = startDistance + (targetDistance - startDistance) * distEase
                let pitch = startPitch + (targetPitchVal - startPitch) * posEase

                let camera = mapView.camera
                camera.centerCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                camera.centerCoordinateDistance = dist
                camera.pitch = pitch
                // 持續跟隨模式：heading 由 continuousHeadingTimer 控制，飛行動畫不管
                if !continuousFollow {
                    let headingDiff = targetHeading - startHeading
                    let normalizedDiff = atan2(sin(headingDiff * .pi / 180), cos(headingDiff * .pi / 180)) * 180 / .pi
                    camera.heading = startHeading + normalizedDiff * posEase
                }
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
            autoZoomTimer?.invalidate()
            autoZoomTimer = nil
            routeReturnTimer?.invalidate()
            routeReturnTimer = nil
            isFlying = true
            let continuousFollow = parent.continuousFollow
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
                let elapsed = Date().timeIntervalSince(startTime)
                let t = min(elapsed / duration, 1.0)
                let ease = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
                let lat = startCenter.latitude + (coordinate.latitude - startCenter.latitude) * ease
                let lon = startCenter.longitude + (coordinate.longitude - startCenter.longitude) * ease
                let dist = startDistance + (distance - startDistance) * ease
                let pitch = startPitch + (targetPitchVal - startPitch) * ease

                let camera = mapView.camera
                camera.centerCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                camera.centerCoordinateDistance = dist
                camera.pitch = pitch
                // 持續跟隨模式：heading 由 continuousHeadingTimer 控制
                if !continuousFollow {
                    camera.heading = startHeading + (targetHeading - startHeading) * ease
                }
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

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            if hasInitialized {
                parent.savedRegion = mapView.region
                parent.savedCamera = mapView.camera
            }
            // 飞行结束或用户操作结束，地图静止后启动5秒倒数
            if pendingAutoZoom && !isFlying && !isDriving && !isUserInteracting {
                pendingAutoZoom = false
                scheduleAutoZoom()
            }
        }

        func syncParkingAnnotations(parkingPoints: [ParkingPointRecord], titlePrefixesByID: [UUID: String]) {
            guard let mapView else { return }
            let latestPointID = parkingPoints.max(by: { $0.createdAt < $1.createdAt })?.id
            var hasher = Hasher()
            for p in parkingPoints {
                hasher.combine(p.id)
                hasher.combine(p.latitude)
                hasher.combine(p.longitude)
                hasher.combine(p.createdAt.timeIntervalSince1970)
                hasher.combine(p.predictedFloorIndex)
                hasher.combine(p.manualFloorIndex)
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

            var next: [UUID: ParkingPointAnnotation] = [:]
            next.reserveCapacity(parkingPoints.count)
            for p in parkingPoints {
                // Convert WGS-84 to GCJ-02 for correct display on China maps
                let gcj02 = CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude).wgs84ToGCJ02
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
                anno.isLatest = p.id == latestPointID
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
                        let baseTitle = prefix.isEmpty ? baseLabel : "\(prefix)" + baseLabel
                        anno.title = "\(baseTitle) \(suffix)"
                    }
                } else {
                    let prefix = (titlePrefixesByID[p.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    anno.title = prefix.isEmpty ? baseLabel : "\(prefix)" + baseLabel
                }
                anno.subtitle = p.address.isEmpty ? nil : p.address
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
                view.glyphText = "P"
            } else {
                view.markerTintColor = UIColor.systemTeal
                view.glyphText = "S"
            }
            view.titleVisibility = .visible
            view.subtitleVisibility = .visible
            view.isDraggable = false
            view.centerOffset = CGPoint(x: 0, y: -10)
            view.displayPriority = annotation.isLatest ? .required : .defaultHigh
            // 最新停車點比其他點大 30%（用 sizeScale，唔用 transform——見 ScaledMarkerAnnotationView）
            view.sizeScale = annotation.isLatest ? 1.30 : 1.0
        }

        func applyParkingSelection(selectedParkingPointID: UUID?) {
            guard let mapView else { return }
            guard !isParkingPointDragging else { return }
            if selectedParkingPointID == lastAppliedSelectedParkingPointID { return }
            lastAppliedSelectedParkingPointID = selectedParkingPointID

            isApplyingParkingSelection = true
            defer { isApplyingParkingSelection = false }

            let selectedParkingAnno = mapView.selectedAnnotations.first(where: { $0 is ParkingPointAnnotation })

            guard let id = selectedParkingPointID else {
                if let a = selectedParkingAnno {
                    mapView.deselectAnnotation(a, animated: true)
                }
                return
            }

            if let current = selectedParkingAnno as? ParkingPointAnnotation, current.pointID == id {
                return
            }

            if let a = selectedParkingAnno {
                mapView.deselectAnnotation(a, animated: true)
            }
            if let target = parkingAnnotationsByID[id] {
                mapView.selectAnnotation(target, animated: true)
            }
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            let meterMembers = MeterMapLayer.members(view.annotation)
            if let meter = ParkingMeterManager.shared.representative(meterMembers) {
                parent.onSelectParkingPoint(nil)
                parent.onSelectHKLocation(nil)
                withAnimation(.easeOut(duration: 0.28)) {
                    ParkingMeterManager.shared.select(meter)
                }
                if let annotation = view.annotation { mapView.deselectAnnotation(annotation, animated: false) }
                return
            }
            if isApplyingParkingSelection { return }
            if let anno = view.annotation as? ParkingPointAnnotation {
                ParkingMeterManager.shared.selectedMeter = nil
                parent.onSelectParkingPoint(anno.pointID)
            } else if let pointAnno = view.annotation as? MKPointAnnotation,
                      hkAnnotations.contains(where: { $0 === pointAnno }),
                      let title = pointAnno.title {
                ParkingMeterManager.shared.selectedMeter = nil
                parent.onSelectHKLocation((title, pointAnno.coordinate))
            }
        }

        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            if isApplyingParkingSelection { return }
            if view.annotation is ParkingPointAnnotation {
                parent.onSelectParkingPoint(nil)
            } else if let pointAnno = view.annotation as? MKPointAnnotation,
                      hkAnnotations.contains(where: { $0 === pointAnno }) {
                parent.onSelectHKLocation(nil)
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
                return nil
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
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: reuseID) as? MKMarkerAnnotationView) ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: reuseID)
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

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
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
    @EnvironmentObject private var locationManager: LocationManager
    @State private var flyTrigger = 0
    @State private var isLandscape = false
    @State private var hasTriggeredFirstTime = false

    var body: some View {
        ZStack {
            MapView(savedRegion: $savedRegion, savedCamera: $savedCamera, flyTrigger: $flyTrigger, isLandscape: isLandscape, routeOverlay: routeOverlay, routeAnimationOverlay: routeAnimationOverlay, followHeading: followHeading, continuousFollow: continuousFollow, hkDetailMode: hkDetailMode, northOverrideTrackingToken: northOverrideTrackingToken, parkingPoints: parkingPoints, parkingPointTitlePrefixesByID: parkingPointTitlePrefixesByID, selectedParkingPointID: selectedParkingPointID, onSelectParkingPoint: onSelectParkingPoint, onMoveParkingPoint: onMoveParkingPoint, routePriorityToken: routePriorityToken, routePriorityAnchor: routePriorityAnchor, meterNavigationTargetID: meterNavigationTargetID, meterNavigationTargetCoordinate: meterNavigationTargetCoordinate, routeOverlayToken: routeOverlayToken, routeOverlayAnimationToken: routeOverlayAnimationToken, mapStyleIndex: mapStyleIndex, showSatellite: showSatellite, centerOffsetX: centerOffsetX, centerOffsetY: centerOffsetY, hideCompass: hideCompass, compassBridge: compassBridge, onMapBlankTap: onMapBlankTap, onSelectHKLocation: onSelectHKLocation)
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
                .onChange(of: geo.size.width) { _, _ in
                    let landscape = w > h
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
