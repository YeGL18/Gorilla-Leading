import SwiftUI
import MapKit
import Combine

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

struct MapView: UIViewRepresentable {
    @Binding var savedRegion: MKCoordinateRegion?
    @Binding var savedCamera: MKMapCamera?
    @Binding var flyTrigger: Int
    var isLandscape: Bool
    var routeOverlay: MKPolyline?
    var routeAnimationOverlay: MKPolyline?
    var followHeading: Bool
    var routePriorityToken: UUID?
    var routePriorityAnchor: CLLocationCoordinate2D?
    var routeOverlayToken: UUID?
    var routeOverlayAnimationToken: UUID?
    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> NonAdjustingMapView {
        let mapView = NonAdjustingMapView()
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .none
        mapView.pointOfInterestFilter = .excludingAll
        mapView.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        mapView.delegate = context.coordinator
        context.coordinator.mapView = mapView

        // 默认定位到香港，避免首次打开闪 San Jose
        let hongKong = CLLocationCoordinate2D(latitude: 22.3193, longitude: 114.1694)
        mapView.allowCameraChange = true
        let camera = MKMapCamera()
        camera.centerCoordinate = hongKong
        camera.centerCoordinateDistance = 50000
        mapView.setCamera(camera, animated: false)
        mapView.allowCameraChange = false

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.userTouched(_:)))
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.userTouched(_:)))
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.userTouched(_:)))
        let rotate = UIRotationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.userTouched(_:)))
        mapView.addGestureRecognizer(tap)
        mapView.addGestureRecognizer(pan)
        mapView.addGestureRecognizer(pinch)
        mapView.addGestureRecognizer(rotate)

        // 调整指南针位置：下移一个指南针高度 + 12pt
        // 指南针的标准高度大约是 30pt
        let compassHeight: CGFloat = 30
        let additionalOffset: CGFloat = 24
        
        // 查找指南针视图并调整其位置
        DispatchQueue.main.async {
            for subview in mapView.subviews {
                if NSStringFromClass(type(of: subview)).contains("Compass") {
                    var frame = subview.frame
                    frame.origin.y += compassHeight + additionalOffset
                    subview.frame = frame
                    break
                }
            }
        }

        return mapView
    }

    func updateUIView(_ mapView: NonAdjustingMapView, context: Context) {
        context.coordinator.parent = self
        let landscapeChanged = context.coordinator.isLandscape != isLandscape
        context.coordinator.isLandscape = isLandscape
        
        let targetStyle: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        if mapView.overrideUserInterfaceStyle != targetStyle {
            mapView.overrideUserInterfaceStyle = targetStyle
        }
        
        if landscapeChanged {
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
                        coordinator.startTracking()
                    }
                } else {
                    context.coordinator.startTracking()
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
                                coordinator.flyToCoordinate(mapView: mapView, coordinate: anchor, distance: 800, duration: 1.2)
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
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapView
        weak var mapView: NonAdjustingMapView?
        var lastFlyTrigger = 0
        var isLandscape = false
        var autoZoomTimer: Timer?
        var flyTimer: Timer?
        var isFlying = false
        var hasShownHighAltitude = false
        var hasInitialized = false
        
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
        
        // 柔软追踪相关
        private var softLatVelocity: Double = 0   // 纬度速度（度/帧）
        private var softLonVelocity: Double = 0   // 经度速度（度/帧）
        private var softLastGPSTime: TimeInterval = 0
        private var softTargetCenter: CLLocationCoordinate2D?
        private var softIsDecelerating = false
        private var softDecelerationProgress: Double = 0
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
                renderer.strokeColor = UIColor(hex: "007AFF").withAlphaComponent(fullRouteAlpha)
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
            renderer.strokeColor = UIColor(hex: "007AFF").withAlphaComponent(animRouteAlpha)
            renderer.setNeedsDisplay()
            if let renderer = routeFullRenderer {
                renderer.strokeColor = UIColor(hex: "007AFF").withAlphaComponent(fullRouteAlpha)
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
                    renderer.strokeColor = UIColor(hex: "007AFF").withAlphaComponent(self.fullRouteAlpha)
                    renderer.setNeedsDisplay()
                }
                if let renderer = self.routeDrawRenderer {
                    renderer.strokeColor = UIColor(hex: "007AFF").withAlphaComponent(self.animRouteAlpha)
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
                    let effectiveLocation = self.mapView?.userLocation.location ?? location
                    self.smoothUpdateMapPosition(location: effectiveLocation)
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
        
        private func updateMapPosition() {
            guard let mapView = mapView,
                  let location = mapView.userLocation.location,
                  !isFlying else { return }
            
            let targetCenter = CLLocationCoordinate2D(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
            let targetDistance: CLLocationDistance = 800
            
            mapView.allowCameraChange = true
            
            let camera = mapView.camera
            camera.centerCoordinate = targetCenter
            camera.centerCoordinateDistance = targetDistance
            mapView.setCamera(camera, animated: true)
            
            mapView.allowCameraChange = false
        }

        var smoothPanTimer: Timer?
        private var smoothFromCenter = CLLocationCoordinate2D()
        private var smoothToCenter = CLLocationCoordinate2D()
        private var smoothFromDistance: CLLocationDistance = 800
        private var smoothToDistance: CLLocationDistance = 800
        private var smoothFromHeading: CLLocationDirection = 0
        private var smoothToHeading: CLLocationDirection = 0
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
        
        private func standardUpdateMapPosition(location: CLLocation) {
            guard let mapView = mapView, !isFlying else { return }
            
            smoothPanTimer?.invalidate()
            
            smoothFromCenter = mapView.camera.centerCoordinate
            smoothFromDistance = mapView.camera.centerCoordinateDistance
            smoothFromHeading = mapView.camera.heading
            smoothToCenter = location.coordinate
            smoothToDistance = 800
            smoothToHeading = parent.followHeading ? parent.locationManager.heading : mapView.camera.heading
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
                
                mapView.allowCameraChange = true
                let camera = mapView.camera
                camera.centerCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                camera.centerCoordinateDistance = dist
                camera.heading = hdg
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
            softTargetCenter = location.coordinate
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
                // 减速阶段：2秒内直线减速到目标
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
                camera.centerCoordinateDistance = 800
                if parent.followHeading {
                    let targetHeading = parent.locationManager.heading
                    let currentHeading = camera.heading
                    let headingDiff = targetHeading - currentHeading
                    let normalizedDiff = atan2(sin(headingDiff * .pi / 180), cos(headingDiff * .pi / 180)) * 180 / .pi
                    camera.heading = currentHeading + normalizedDiff * ease
                }
                mapView.setCamera(camera, animated: false)
                mapView.allowCameraChange = false
                
                if t >= 1.0 {
                    smoothPanTimer?.invalidate()
                    smoothPanTimer = nil
                    softIsDecelerating = false
                    softDecelerationProgress = 0
                }
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
                camera.centerCoordinateDistance = 800
                if parent.followHeading {
                    let targetHeading = parent.locationManager.heading
                    let currentHeading = camera.heading
                    let headingDiff = targetHeading - currentHeading
                    let normalizedDiff = atan2(sin(headingDiff * .pi / 180), cos(headingDiff * .pi / 180)) * 180 / .pi
                    camera.heading = currentHeading + normalizedDiff * 0.15
                }
                mapView.setCamera(camera, animated: false)
                mapView.allowCameraChange = false
            }
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

        func startTracking() {
            guard let mapView = mapView, !isUserInteracting else { return }
            
            if !hasShownHighAltitude {
                if let location = mapView.userLocation.location {
                    hasShownHighAltitude = true
                    hasInitialized = true
                    parent.savedRegion = mapView.region
                    // 首次直接飞到用户位置，不显示高空视角
                    flyToLocation(mapView: mapView, location: location)
                    return
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.startTracking()
                    }
                    return
                }
            }
            
            // 正常的飞行动画
            flyTimer?.invalidate()
            flyTimer = nil
            isFlying = false
            if let location = mapView.userLocation.location {
                flyToLocation(mapView: mapView, location: location)
            } else {
                pendingAutoZoom = true
            }
        }

        private func showHighAltitudeView(mapView: NonAdjustingMapView, location: CLLocation) {
            hasShownHighAltitude = true
            
            mapView.allowCameraChange = true
            
            let camera = mapView.camera
            camera.centerCoordinate = location.coordinate
            camera.centerCoordinateDistance = 50000
            mapView.camera = camera
            
            mapView.allowCameraChange = false
            
            hasInitialized = true
            parent.savedRegion = mapView.region
            
            pendingAutoZoom = true
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

        private func flyToLocation(mapView: NonAdjustingMapView, location: CLLocation) {
            autoZoomTimer?.invalidate()
            autoZoomTimer = nil
            isFlying = true
            let targetCenter = CLLocationCoordinate2D(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
            let targetDistance: CLLocationDistance = 800
            let startCenter = mapView.centerCoordinate
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

                let camera = mapView.camera
                camera.centerCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                camera.centerCoordinateDistance = dist
                mapView.camera = camera

                if t >= 1.0 {
                    timer.invalidate()
                    self.flyTimer = nil
                    self.isFlying = false
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
            let startCenter = mapView.camera.centerCoordinate
            let startDistance = mapView.camera.centerCoordinateDistance
            let startHeading = mapView.camera.heading
            let targetHeading: CLLocationDirection = parent.followHeading ? parent.locationManager.heading : startHeading
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
                let hdg = startHeading + (targetHeading - startHeading) * ease
                let camera = mapView.camera
                camera.centerCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                camera.centerCoordinateDistance = dist
                camera.heading = hdg
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

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            nil
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                if polyline === currentRouteOverlay {
                    let renderer = MKPolylineRenderer(polyline: polyline)
                    renderer.strokeColor = UIColor(hex: "007AFF").withAlphaComponent(fullRouteAlpha)
                    renderer.lineWidth = 5
                    renderer.lineCap = .round
                    renderer.lineJoin = .round
                    routeFullRenderer = renderer
                    return renderer
                }
                if polyline === currentRouteAnimationOverlay {
                    let renderer = AnimatedPolylineRenderer(polyline: polyline)
                    renderer.strokeColor = UIColor(hex: "007AFF").withAlphaComponent(animRouteAlpha)
                    renderer.lineWidth = 5
                    renderer.lineCap = .round
                    renderer.lineJoin = .round
                    attachRouteDrawRenderer(renderer)
                    return renderer
                }
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor(hex: "007AFF")
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
    var routeOverlay: MKPolyline?
    var routeAnimationOverlay: MKPolyline?
    var followHeading: Bool
    var routePriorityToken: UUID?
    var routePriorityAnchor: CLLocationCoordinate2D?
    var routeOverlayToken: UUID?
    var routeOverlayAnimationToken: UUID?
    @State private var flyTrigger = 0
    @State private var isLandscape = false
    @State private var hasTriggeredFirstTime = false

    var body: some View {
        ZStack {
            MapView(savedRegion: $savedRegion, savedCamera: $savedCamera, flyTrigger: $flyTrigger, isLandscape: isLandscape, routeOverlay: routeOverlay, routeAnimationOverlay: routeAnimationOverlay, followHeading: followHeading, routePriorityToken: routePriorityToken, routePriorityAnchor: routePriorityAnchor, routeOverlayToken: routeOverlayToken, routeOverlayAnimationToken: routeOverlayAnimationToken)
                .ignoresSafeArea()

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: 0.45),
                        .init(color: .black.opacity(0.45), location: 0.7),
                        .init(color: .black.opacity(0.75), location: 1)
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
    }
}

struct ReadOnlyMapView: UIViewRepresentable {
    let camera: MKMapCamera?
    @Environment(\.colorScheme) private var colorScheme

    func makeUIView(context: Context) -> NonAdjustingMapView {
        let mapView = NonAdjustingMapView()
        mapView.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .none
        mapView.delegate = nil
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
