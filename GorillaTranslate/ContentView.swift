import SwiftUI
import UIKit
import UserNotifications
import Accelerate
import MapKit
import AVFoundation
import WidgetKit
import Vision

// MARK: - 專注模式

/// 時速頁專注模式 —— 閂走時速顯示以外嘅功能，減少耗電同發熱。
enum FocusModeLevel: String, CaseIterable, Identifiable {
    case balanced   // 平衡：保留泊車偵測＋靈動島，切地圖／資訊彈出／ETA 網絡請求
    case light      // 輕度：只切地圖渲染，其餘全部照行
    case extreme    // 極致：再停用泊車狀態偵測同靈動島更新

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced: return String(localized: "平衡")
        case .extreme:  return String(localized: "極致")
        case .light:    return String(localized: "輕度")
        }
    }

    var icon: String {
        switch self {
        case .balanced: return "leaf.fill"
        case .extreme:  return "bolt.slash.fill"
        case .light:    return "circle.lefthalf.filled"
        }
    }

    var summary: String {
        switch self {
        case .balanced:
            return String(localized: "保留泊車偵測同靈動島狀態；切走地圖渲染、資訊彈出、ETA／路線網絡請求")
        case .extreme:
            return String(localized: "最慳電：額外暫停泊車／停留／開車狀態偵測同靈動島更新，退出專注模式後會自動補返")
        case .light:
            return String(localized: "只切走地圖渲染，靈動島同所有功能照常運作")
        }
    }

    /// 每種模式嘅代表色：平衡＝綠、輕度＝黃、極致＝紫
    var color: Color {
        switch self {
        case .balanced: return .green
        case .light:    return Color(red: 0.95, green: 0.78, blue: 0.05)
        case .extreme:  return .purple
        }
    }
}

/// 專注模式下 orb 背景動畫幀率
enum FocusFrameRate: Int, CaseIterable, Identifiable {
    case fps60 = 60
    case fps90 = 90
    case fps120 = 120
    var id: Int { rawValue }
}

struct ContentView: View {
    private struct CapsuleDragState: Equatable {
        var mode: Int = 0
        var offset: CGFloat = 0
        var active: Bool = false
    }
    
    private struct BlurSlideModifier: ViewModifier {
        var blur: CGFloat
        var y: CGFloat
        var scale: CGFloat
        
        func body(content: Content) -> some View {
            content
                .blur(radius: blur)
                .offset(y: y)
                .scaleEffect(scale)
        }
    }

    @StateObject private var animationClock = AnimationClock()
    @StateObject private var timePhaseManager = TimePhaseManager()
    @StateObject private var photoStorage = PhotoStorage()
    @StateObject private var sfxPlayer = SFXPlayer()
    @ObservedObject private var tripPredictor = TripPredictor.shared
    @StateObject private var naviManager = AmapNaviManager.shared
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var destinationManager: DestinationManager
    @EnvironmentObject private var parkingFloorStore: ParkingFloorStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var meterManager = ParkingMeterManager.shared
    @State private var meterRouteTarget: ParkingMeter?
    @State private var meterDirections: MKDirections?
    @State private var meterRouteError: String?
    private let meterTick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var isInForeground = true
    @AppStorage("floorCurveTriggerMode") private var floorCurveTriggerMode: Int = 0  // 0=純速度, 1=速度+海拔
    
    @State private var selectedTab: Int = 1
    @State private var showVehiclePicker: Bool = false
    @State private var selectedVehicleBrand: String = "BMW"
    @State private var selectedVehicleModel: String = "X5"
    @State private var selectedVehicleColor: Color = .blue
    @State private var hasPlayedEntrance = false
    @State private var revealedCount = 0
    @State private var sparklePhase = false
    @State private var showMap = false
    @State private var showSatellite = false  // 三態：光球→地圖→衛星3D→光球
    @State private var mapRegion: MKCoordinateRegion?
    @State private var mapCamera: MKMapCamera?
    @State private var hasShownMapFirstTime = false
    @State private var firstMapFlyTrigger = 0
    @State private var routePriorityToken: UUID?
    @State private var routePriorityAnchor: CLLocationCoordinate2D?
    @State private var routeOverlayToken: UUID?
    @State private var routeOverlayAnimationToken: UUID?
    @State private var isRerouting = false
    @State private var lastRerouteRequestAt: Date?
    @State private var offRouteStrikeCount: Int = 0
    @State private var isCapsuleExpanded = false
    @AppStorage("capsuleAnimationStyle") private var capsuleAnimationStyle: Int = 0  // 0 = default, 1 = lift-scale
    @State private var capsuleDragOffsetY: CGFloat = 0  // for lift-scale animation
    @State private var capsuleDragScale: CGFloat = 1.0  // for lift-scale animation
    @State private var isParkingMemoryExpanded = false
    @State private var etaText: String?
    @State private var isLandscape = false
    @State private var drivingDistanceText: String?
    @State private var capsuleScale: CGFloat = 1.0
    @State private var capsuleOnRight: Bool = false
    @State private var orbOpacity: Double = 1.0
    @GestureState private var capsuleDragState: CapsuleDragState = CapsuleDragState()
    @State private var lastDragOffset: CGFloat = 0  // 當前拖動位置（跟手增減）
    @State private var peakDragOffset: CGFloat = 0  // 拖動到的最高點（只增不減）
    @State private var lastGestureMode: Int = 0  // 0=無, -1=上滑, 1=下滑
    @State private var smoothDragHeight: CGFloat = 44  // 彈簧追蹤的高度值（無極調節）
    @State private var capsuleSettleHeight: CGFloat? = nil
    @State private var capsuleSettleWorkItem: DispatchWorkItem?
    @State private var capsuleAppeared = false
    @State private var roseLoopSpeed: Double = 1.0
    @State private var roseOpacity: Double = 1.0
    @State private var roseBlurRadius: Double = 0.0
    @State private var addressRevealProgress: Double = 0.0
    // 地址輪播（POI名稱 ↔ 街道名）
    @State private var showPOIName: Bool = true
    @State private var addressAlternatingTimer: Timer?
    @State private var parkingEntryTime: Date = Date()
    @State private var parkingTimer: Timer?
    @State private var parkingElapsed: TimeInterval = 0
    @State private var parkingCountdown: Int?
    @State private var departureTimer: Timer?
    @State private var departureElapsedTimer: Timer?
    @State private var capsuleUpdateTimer: Timer?
    @State private var stationaryTimer: Timer?
    @State private var stationaryStartTime: Date?
    @State private var walkingStartTime: Date?
    @State private var cyclingStartTime: Date?
    @State private var stationaryElapsed: TimeInterval = 0
    @State private var showCheckmarkAnimation = false
    @State private var departureTimerID: UUID?
    @State private var departureElapsed: TimeInterval = 0
    @State private var manualDeparted = false
    @State private var parkingDeparted = false
    @State private var hasDeparted = false
    @State private var parkingStartTime: Date = Date()
    @State private var activitySyncTimer: Timer?
    @State private var capsuleDuration: TimeInterval = 0
    @State private var lastKnownArrivalDate: Date?
    @State private var timerRunning = false
    @State private var parkingReminderTimer: Timer?
    @State private var lastReminderMinute: Int = -1  // 追蹤上次通知的分鐘數
    @State private var frozenParkingElapsed: TimeInterval? = nil  // 拖動時凍結的計時值
    @State private var frozenCompactStatus: String? = nil  // 拖動時凍結的緊湊態文字
    @State private var animatingPhotoID: UUID?
    @State private var animatingPhotoImage: UIImage?
    @State private var animatingPhotoPhase: Int = 0  // 0 = full size, 1 = shrunk to thumbnail
    @State private var animatingPhotoOffsetX: CGFloat = 0
    @State private var animatingPhotoOffsetY: CGFloat = 0
    @State private var animatingPhotoRotation: Double = 0
    @State private var isCapturing = false
    @State private var isCameraActive = true
    @State private var cameraInactivityTimer: Timer?
    @State private var cameraFadeOpacity: Double = 0  // 0 = camera visible, 1 = black
    @State private var cameraButtonBlurIn: Bool = false  // 拍照按鈕模糊入場動畫
    @State private var viewfinderBreathe: Bool = false   // viewfinder 呼吸動畫
    @State private var showingExpandedPhotos = false
    @State private var selectedPhotoIndex: Int?
    @State private var showDeleteButton = false
    @State private var isCapturePressed = false
    // Photo swipe gesture state
    @State private var photoSwipeOffset: CGFloat = 0
    @State private var photoSwipeIndex: Int? = nil
    @State private var isPhotoSwiping = false
    @State private var isPhotoAnimatingOut = false  // True when animating to bottom after release
    @State private var photoAnimatingOutIndex: Int? = nil  // Tracks which photo should stay at bottom z-index
    @State private var isSwipingPhoto = false        // true during slide-out + return
    @State private var swipePhotoScale: CGFloat = 1  // animated scale during swipe
    // TILT center-lift animation state (per photo index)
    @State private var tiltAngleX: [Int: Double] = [:]
    @State private var tiltAngleY: [Int: Double] = [:]
    // Smoky Dissolve delete animation state
    @State private var deletingPhotoID: UUID? = nil
    @State private var deletingIndex: Int? = nil       // tilt lookup only
    @State private var deletingImage: UIImage? = nil    // snapshot — survives disk/cache eviction
    @State private var deleteBlur: CGFloat = 0
    @State private var deleteOpacity: Double = 1.0
    @State private var deleteOffsetY: CGFloat = 0
    @State private var showingAddDestination = false
    @State private var showingRoute = false
    @State private var routePolyline: MKPolyline?
    @State private var routeAnimationPolyline: MKPolyline?
    @State private var departureTime: Date?
    @State private var showDepartedLabel = false
    enum MapHeadingMode: Int {
        case north = 0           // 朝北：地圖永遠 north-up
        case follow = 1          // 跟隨：開車時跟隨朝向
        case continuousFollow = 2 // 持續跟隨：任何時候都跟隨手機朝向

        var iconName: String {
            switch self {
            case .north: return "location.north"
            case .follow: return "location.north.fill"
            case .continuousFollow: return "location.fill"
            }
        }

        var label: String {
            switch self {
            case .north: return String(localized: "朝北")
            case .follow: return String(localized: "跟隨")
            case .continuousFollow: return String(localized: "持續跟隨")
            }
        }

        var isActive: Bool {
            self != .north
        }

        var isContinuous: Bool {
            self == .continuousFollow
        }
    }

    @State private var mapHeadingMode: MapHeadingMode = .continuousFollow
    @State private var headingToastText: String?
    @State private var headingToastTimer: Timer?
    @State private var hkDetailMode = false        // 香港地圖細覽模式
    @State private var gpsTapCount = 0             // GPS 膠囊點擊計數
    @State private var gpsTapResetTimer: Timer?    // 重置計數的 timer
    @State private var stationaryTrackingTrigger = 0
    @State private var northOverrideTrackingToken = 0
    @State private var showSpeedInfo = false
    @State private var speedInfoTimer: Timer?
    @State private var randomInfoTimer: Timer?
    @State private var lastGPSLocation: CLLocation?
    @State private var lastMovementTime: Date?
    @State private var preDepartureDriving = false
    @State private var preDepartureLastMoveAt: Date?
    @State private var timeAdjustText: String?
    @State private var timeAdjustAccumulated: Int = 0
    // OCR Recognition state
    @State private var recognizedFloorToConfirm: Int? = nil
    @State private var recognizedFloorText: String? = nil
    @State private var showFloorConfirm = false
    @State private var parkingRecognizedDisplayText: String? = nil
    @State private var hasConfirmedFloorThisSession = false
    /// Barometer-preserved floor index before LLM overwrites — used to revert on "No"
    @State private var pendingOriginalFloorIndex: Int? = nil
    /// The LLM-detected floor text that is awaiting user confirmation
    @State private var pendingFloorText: String? = nil
    /// The LLM-detected floor index awaiting confirmation
    @State private var pendingFloorIndex: Int? = nil
    @State private var isRecognizing = false
    // LLM Parking Recognition state
    @State private var llmSpotNumber: String? = nil
    @State private var llmAreaCode: String? = nil
    @State private var llmFloorText: String? = nil
    @State private var hasParkingSpotData: Bool = true  // 默認「泊車記憶」，非純開車時變為「逗留記憶」
    @State private var llmFloorIndex: Int? = nil
    @State private var llmRawResult: String? = nil
    @State private var llmError: String? = nil
    @State private var llmPollTimer: Timer? = nil
    @State private var llmSoundStopTimer: Timer? = nil
    @State private var showLLMActionPrompt = false
    @State private var showNoDestinationAlert = false
    @State private var llmShortcutName: String = UserDefaults.standard.string(forKey: "llm_shortcut_name") ?? String(localized: "泊車辨識")
    @State private var parkingInfoDisplayMode: Bool = true
    @State private var parkingInfoSwitchTimer: Timer? = nil
    @State private var showRecognitionLogicAlert = false
    @State private var showSpotEditor = false
    @State private var editSpotNumber: String = ""
    @State private var editAreaCode: String = ""
    @State private var editFloorText: String = ""
    @State private var parkingPhotoContributions: [UUID: [String: String]] = [:]
    @State private var currentRecognizingPhotoID: UUID? = nil
    @State private var parkingOrbBoost: Double = 1.0
    @State private var orbBoostElapsedOffset: Double = 0
    // Floor curve popup (auto-detect garage descent)
    @State private var showFloorCurvePopup = false
    @State private var floorCurveHistory: [CGFloat] = []
    @State private var floorCurveBaseAltitude: Double = 0
    @State private var floorCurveLocked = false
    @State private var floorCurveLockedFloor: Int = 0
    @State private var floorCurveSampleTimer: Timer?
    @State private var floorCurveDismissTimer: Timer?
    @State private var floorCurveDescendingCount: Int = 0
    @State private var floorCurveAppearTime: Date? = nil
    @State private var floorCurveLockAnimating: Bool = false
    @State private var isFloorCurveInCapsule: Bool = false
    // 光效動畫
    @State private var lightEffectProgress: CGFloat = 0        // 0.0→1.0 光帶位置
    @State private var lightEffectIsFadingOut: Bool = false     // 是否正在自動消失
    @State private var lightEffectFadeProgress: CGFloat = 0    // 消失進度
    @State private var lightEffectDismissWorkItem: DispatchWorkItem?

    /// 光效高斯模糊強度（0→12pt）
    private var lightEffectBlur: CGFloat {
        let p = lightEffectIsFadingOut ? max(0, 1 - lightEffectFadeProgress) : lightEffectProgress
        let eased = p * p * p * (p * (p * 6 - 15) + 10)
        return eased * 12
    }

    /// 光效光學扭曲強度（0→1，純視覺效果，唔影響佈局）
    private var lightEffectDistortionStrength: CGFloat {
        let p = lightEffectIsFadingOut ? max(0, 1 - lightEffectFadeProgress) : lightEffectProgress
        let eased = p * p * p * (p * (p * 6 - 15) + 10)
        return eased
    }
    @State private var isOrbRecognizingBoost: Bool = false
    @State private var orbGradualStopTimer: Timer?
    @State private var drivingETASeconds: TimeInterval?
    @State private var visitStatus: String = "已停留"
    @State private var visitSecondaryStatus: String?
    /// 非開車到達時為 true（步行/跑步/騎行到達），控制 UI 標籤和靈動島狀態
    @State private var isNonAutomotiveArrival: Bool = false
    @State private var selectedParkingPointID: UUID?
    @State private var selectedHKLocation: (title: String, coordinate: CLLocationCoordinate2D)?
    /// 專注模式（nil = 關閉）—— 時速頁左下角按鈕控制
    @State private var focusMode: FocusModeLevel? = nil
    @State private var focusFrameRate: FocusFrameRate = .fps60
    @AppStorage("colorSchemeIndex") private var colorSchemeIndex: Int = 0
    @AppStorage("appearanceMode") private var appearanceMode: Int = 0
    @AppStorage("outputAnimationStyle") private var outputAnimationStyle: Int = 0
    @AppStorage("orbMasterEnabled") private var orbMasterEnabled: Bool = true
    @AppStorage("useTimeBasedOrb") private var useTimeBasedOrb: Bool = false
    @AppStorage("orbCapsule") private var orbCapsule: Bool = true
    @AppStorage("orbExpanded") private var orbExpanded: Bool = true
    @AppStorage("orbParkingMemory") private var orbParkingMemory: Bool = true
    @AppStorage("orbBackgroundHome") private var orbBackgroundHome: Bool = true
    @AppStorage("orbBackgroundSpeed") private var orbBackgroundSpeed: Bool = true
    @AppStorage("orbColorPreset") private var orbColorPreset: Int = 0  // 0=金黃, 1=動態橙, 2=#9BF783, 3=#99E695, 4=#97D5AB
    @AppStorage("darkKnightMode") private var darkKnightMode: Bool = false
    @State private var darkKnightActivatedByFocus = false  // 是否由極致專注模式自動開啟
    /// 黑武士模式地圖圓角（橫屏更大）
    private var darkKnightMapCornerRadius: CGFloat { isLandscape ? 50 : 44 }
    @AppStorage("mapStyleIndex") private var mapStyleIndex: Int = 0
    @AppStorage("vlmRecognitionEnabled") private var vlmRecognitionEnabled: Bool = true
    @AppStorage("parkingTimerColorHex") private var parkingTimerColorHex: String = "46ADB8"
    @AppStorage("bestRouteColorHex") private var bestRouteColorHex: String = "BCBA1E"

    // Trip Predictor UI state
    @State private var showDemoAnimation = false
    @State private var showingTripConfirm = false
    @State private var tripConfirmPrediction: PendingTripPrediction? = nil
    @State private var tripToastPrediction: PendingTripPrediction? = nil
    @State private var tripToastAutoDismiss: DispatchWorkItem? = nil

    init() {
        let appearance = UITabBarAppearance()
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.gray]
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor.white
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor.gray
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance

        let defaults = UserDefaults(suiteName: "group.com.gorilla.translate") ?? .standard
        if let savedTime = defaults.object(forKey: "parkingStartTime") as? Date {
            let departed = defaults.bool(forKey: "hasDeparted")
            let savedManualDeparted = defaults.bool(forKey: "manualDeparted")
            if departed && savedManualDeparted {
                // Restore manually-departed state — parked then left
                _hasDeparted = State(initialValue: true)
                _manualDeparted = State(initialValue: true)
                _timerRunning = State(initialValue: false)
                _parkingStartTime = State(initialValue: savedTime)
                if let savedDepTime = defaults.object(forKey: "parkingDepartureTime") as? Date {
                    _departureTime = State(initialValue: savedDepTime)
                    _departureElapsed = State(initialValue: Date().timeIntervalSince(savedDepTime))
                }
            } else if !departed {
                _parkingStartTime = State(initialValue: savedTime)
                _parkingEntryTime = State(initialValue: savedTime)
                _hasDeparted = State(initialValue: false)
                _capsuleDuration = State(initialValue: Date().timeIntervalSince(savedTime))
                _parkingElapsed = State(initialValue: Date().timeIntervalSince(savedTime))
                _timerRunning = State(initialValue: false)
                _lastKnownArrivalDate = State(initialValue: defaults.object(forKey: "lastKnownArrivalDate") as? Date)
                let savedNonAuto = defaults.bool(forKey: "isNonAutomotiveArrival")
                // 糾錯：正在泊車時不應該是逗留（之前誤判的記錄）
                let isParking = !defaults.bool(forKey: "hasDeparted")
                let correctedNonAuto = isParking ? false : savedNonAuto
                _isNonAutomotiveArrival = State(initialValue: correctedNonAuto)
                _visitStatus = State(initialValue: "已泊車")
                if correctedNonAuto != savedNonAuto {
                    defaults.set(false, forKey: "isNonAutomotiveArrival")
                }
                // Load persisted parking photo contributions
                var loadedContributions: [UUID: [String: String]] = [:]
                if let data = defaults.data(forKey: "parkingPhotoContributions"),
                   let decoded = try? JSONDecoder().decode([UUID: [String: String]].self, from: data) {
                    loadedContributions = decoded
                }
                _parkingPhotoContributions = State(initialValue: loadedContributions)
                // Merge contributions into display fields
                var mSpot: String? = nil; var mArea: String? = nil; var mFloor: String? = nil; var mFloorIdx: Int? = nil
                for (_, c) in loadedContributions {
                    if let s = c["spot"], mSpot == nil { mSpot = s }
                    if let a = c["area"], mArea == nil { mArea = a }
                    if let f = c["floor"], mFloor == nil { mFloor = f; mFloorIdx = Self.parseFloorIndex(f) }
                }
                _llmSpotNumber = State(initialValue: mSpot)
                _llmAreaCode = State(initialValue: mArea)
                _llmFloorText = State(initialValue: mFloor)
                _llmFloorIndex = State(initialValue: mFloorIdx)
                _llmRawResult = State(initialValue: loadedContributions.isEmpty ? nil : "multi-photo")
            }
        }
    }

    private var resolvedColorScheme: ColorScheme? {
        switch appearanceMode {
        case 1: return .dark
        case 2: return .light
        default: return nil
        }
    }

    private var effectiveColorScheme: ColorScheme {
        switch appearanceMode {
        case 1: return .dark
        case 2: return .light
        default:
            let phase = UITraitCollection.current.userInterfaceStyle
            return phase == .dark ? .dark : .light
        }
    }

    var body: some View {
        ZStack {
        TabView(selection: $selectedTab) {
            SpeedView(showMap: (showMap || showSatellite) && !focusActive, animationClock: animationClock, mapCamera: $mapCamera, focusMode: $focusMode, focusFrameRate: $focusFrameRate, onEnterFocus: enterFocusMode, onExitFocus: exitFocusMode)
                .environment(\.colorScheme, effectiveColorScheme)
                .tabItem {
                    Label(String(localized: "Speed"), systemImage: "speedometer")
                }
                .tag(0)
                .onAppear {
                    updateTabBarAppearance()
                }
                .onChange(of: darkKnightMode) { _, newValue in
                    updateTabBarAppearance()
                    // 手動關閉黑武士模式時，清除自動開啟標記
                    if !newValue {
                        darkKnightActivatedByFocus = false
                    }
                }

            NavigationStack {
                homeContent
            }
            .tabItem {
                Label(String(localized: "Home"), systemImage: "house.fill")
            }
            .tag(1)
            .onAppear {
                animationClock.start()
                guard !hasPlayedEntrance else { return }
                hasPlayedEntrance = true
                let launchAnimEnabled = UserDefaults.standard.object(forKey: "launchAnimationEnabled") as? Bool ?? true
                if launchAnimEnabled {
                    triggerEntranceEffect()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.easeOut(duration: 1.2)) {
                            capsuleAppeared = true
                        }
                    }
                } else {
                    capsuleAppeared = true
                }
            }

            SettingsView()
                .environment(\.colorScheme, effectiveColorScheme)
                .tabItem {
                    Label(String(localized: "Settings"), systemImage: "gearshape")
                }
                .tag(2)
        }
        .preferredColorScheme(resolvedColorScheme)
        .onReceive(meterTick) { _ in
            meterManager.tick(location: locationManager.lastLocation, speed: locationManager.speed,
                              destination: destinationManager.selectedDestination,
                              canPresentNotices: selectedTab == 1 && selectedParkingPointID == nil
                                && selectedHKLocation == nil && !showingTripConfirm
                                && !meterManager.needsVehicleSelection && !meterManager.paymentHelpPresented)
        }
        .sheet(isPresented: $meterManager.needsVehicleSelection) { MeterVehiclePicker() }
        .modifier(MeterPaymentHelp(manager: meterManager))
        .alert("未能取得路線", isPresented: Binding(get: { meterRouteError != nil }, set: { if !$0 { meterRouteError = nil } })) {
            Button("確定", role: .cancel) { meterRouteError = nil }
        } message: { Text(meterRouteError ?? "") }
        .onAppear {
            meterManager.prepare()
            meterManager.setActive(true)
            if meterManager.isEnabled && meterManager.vehicle == .unset { meterManager.needsVehicleSelection = true }
            animationClock.start()
            if orbMasterEnabled && orbBackgroundHome && useTimeBasedOrb {
                // 立即啟動入場動畫（同 blur 淡入同步進行）
                timePhaseManager.startWithEntranceAnimation()
            }
            UIApplication.shared.isIdleTimerDisabled = true
            DispatchQueue.main.async {
                locationManager.startLocationServicesIfNeeded()
                refreshVisitAndTimersForForeground()
                sfxPlayer.prepare()
                photoStorage.prepare()
                startFloorCurveDetection()
                startCapsuleUpdateTimer()
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            stopFloorCurveDetection()
            stopCapsuleUpdateTimer()
        }
        .onChange(of: scenePhase) { _, phase in
            meterManager.setActive(phase == .active)
            isInForeground = (phase == .active)
            if phase == .active {
                DispatchQueue.main.async {
                    // 重置速度濾波器，避免殘留舊值
                    locationManager.resetSpeedFilter()
                    locationManager.startLocationServicesIfNeeded()
                    refreshVisitAndTimersForForeground()
                    // Force the Live Activity to re-render with the latest
                    // widget build — the system keeps the archived render of
                    // the previous build until the next content update.
                    // forceRefresh bumps the render nonce so the payload is
                    // guaranteed to differ from the archived render.
                    syncLiveActivity(forceRefresh: true)
                    // 重新啟動樓層探測（背景回來後 timer 可能已被系統回收）
                    startFloorCurveDetection()
                    // 啟動 60 秒定期同步 compact trailing 計時器
                    startActivitySyncTimer()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .parkingPhotoCaptured)) { notification in
            if let photo = notification.object as? UIImage {
                guard isParkingMemoryExpanded else { return }
                guard photoStorage.photos.count < PhotoStorage.maxPhotos else { return }
                startCaptureAnimation(photo: photo)
            }
        }
        .onReceive(locationManager.$lastLocation) { location in
            guard let location = location else { return }
            timePhaseManager.fetchSunTimes(for: location.coordinate)
            // 追蹤低速時的 GPS 位置（用於修正泊車位置）
            if parkingFloorStore.barometer.currentSpeedKmh < 20 {
                parkingFloorStore.lastStationaryCoordinate = location.coordinate
            }
            // 有目的地時自動刷新 ETA
            if destinationManager.selectedDestination != nil {
                refreshETA()
            }
        }
        .onReceive(locationManager.$lastLocation) { location in
            guard let location = location else { return }
            guard showingRoute, let polyline = routePolyline else { return }
            guard locationManager.speed >= 15 else { return }
            if isRerouting || meterDirections != nil { return }
            if let last = lastRerouteRequestAt, Date().timeIntervalSince(last) < 8 { return }
            let distance = distanceFromRoute(location: location, polyline: polyline)
            if distance > 40 {
                offRouteStrikeCount += 1
            } else {
                offRouteStrikeCount = 0
            }
            if offRouteStrikeCount >= 3 {
                offRouteStrikeCount = 0
                reroute(from: location.coordinate)
            }
        }
        .onReceive(locationManager.$visits) { visits in
            guard let lastVisit = visits.first else { return }

            if lastVisit.departureDate != nil {
                // 到訪結束：自動停止計時
                if timerRunning && lastKnownArrivalDate == lastVisit.arrivalDate {
                    timerRunning = false
                    parkingTimer?.invalidate()
                    parkingTimer = nil
                    stopParkingReminder()
                    hasDeparted = true
                    departureTime = lastVisit.departureDate
                    showDepartedLabel = true
                    clearParkingContributions()
                    // 清理樓層曲線鎖定狀態
                    parkingFloorStore.floorCurveLockedFloor = nil
                    parkingFloorStore.lastStationaryCoordinate = nil
                    // 系統自動偵測到離開 — 推送通知
                    let content = UNMutableNotificationContent()
                    if isNonAutomotiveArrival && !hasParkingSpotData {
                        content.title = String(localized: "Gorilla 記憶")
                        content.body = String(localized: "記憶已退出")
                    } else {
                        content.title = String(localized: "Gorilla 記憶")
                        content.body = String(localized: "記憶已退出")
                    }
                    content.sound = UNNotificationSound(named: UNNotificationSoundName("gorilla_parking_status_notifi.mp3"))
                    let req = UNNotificationRequest(identifier: "parking-departed-\(UUID().uuidString)", content: content, trigger: nil)
                    UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showDepartedLabel = false
                        }
                    }
                    saveParkingState()
                    WidgetCenter.shared.reloadTimelines(ofKind: "ParkingTimerWidget")
                }
                if hasDeparted, let dep = departureTime {
                    departureElapsed = Date().timeIntervalSince(dep)
                    departureElapsedTimer?.invalidate()
                    let timer = Timer(timeInterval: 1.0, repeats: true) { _ in
                        guard hasDeparted, let d = departureTime else { return }
                        let e = Date().timeIntervalSince(d)
                        DispatchQueue.main.async {
                            departureElapsed = e
                        }
                    }
                    departureElapsedTimer = timer
                    RunLoop.main.add(timer, forMode: .common)
                }
            } else {
                // 新的到訪：自動開始計時
                let newArrival = lastVisit.arrivalDate
                // Guard: if user manually departed, the old visit is still active — don't restart
                // unless this is genuinely a different arrival (new visit event)
                if manualDeparted && newArrival == parkingStartTime { return }
                if lastKnownArrivalDate != newArrival {
                    lastKnownArrivalDate = newArrival
                    parkingEntryTime = newArrival
                    parkingStartTime = newArrival
                    capsuleDuration = 0
                    parkingElapsed = 0
                    hasDeparted = false
                    manualDeparted = false
                    timerRunning = false
                    departureElapsedTimer?.invalidate()
                    departureElapsedTimer = nil
                    startPersistentTimer()
                    // 系統自動偵測到泊車 — 推送通知
                    let content = UNMutableNotificationContent()
                    if isNonAutomotiveArrival && !hasParkingSpotData {
                        content.title = String(localized: "Gorilla 記憶")
                        content.body = String(localized: "記憶已開啟")
                    } else {
                        content.title = String(localized: "Gorilla 記憶")
                        content.body = String(localized: "記憶已開啟")
                    }
                    content.sound = UNNotificationSound(named: UNNotificationSoundName("gorilla_parking_status_notifi.mp3"))
                    let req = UNNotificationRequest(identifier: "parking-arrived-\(UUID().uuidString)", content: content, trigger: nil)
                    UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
                    parkingFloorStore.recordParkingPoint(from: lastVisit)
                    // Bug 1 修復：強制 SwiftUI 重新渲染地圖（確保停車點標記出現）
                    parkingFloorStore.objectWillChange.send()
                    // Show parking info on new arrival
                    parkingInfoDisplayMode = true
                    // 只有在用戶尚未手動拍照識別時才清除（避免覆蓋已有的泊車資訊）
                    let hasExistingData = llmSpotNumber != nil || llmAreaCode != nil || llmFloorText != nil || llmFloorIndex != nil
                    if !hasExistingData {
                        clearParkingContributions()
                    }
                }
            }
        }
        .onChange(of: isParkingMemoryExpanded) { _, expanded in
            if expanded {
                // Bug 2 修復：防禦性檢查，確保狀態穩定後再啟動相機
                isCameraActive = true
                cameraFadeOpacity = 0
                cameraButtonBlurIn = false  // 先重置
                viewfinderBreathe = false   // 先停止呼吸
                resetCameraInactivityTimer()
                // 拍照按鈕模糊入場動畫（延遲確保視圖已穩定）
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                        cameraButtonBlurIn = true
                    }
                }
                if hasDeparted {
                    hasDeparted = false
                    manualDeparted = false
                    parkingEntryTime = Date()
                    parkingStartTime = Date()
                    lastKnownArrivalDate = Date()
                    capsuleDuration = 0
                    parkingElapsed = 0
                    timerRunning = false
                    departureElapsedTimer?.invalidate()
                    departureElapsedTimer = nil
                    startPersistentTimer()
                } else if !timerRunning {
                    lastKnownArrivalDate = parkingStartTime
                    capsuleDuration = 0
                    parkingElapsed = 0
                    startPersistentTimer()
                }
            } else {
                deactivateCamera()
            }
        }
        .onChange(of: selectedPhotoIndex) { _, newIndex in
            // Hide delete button on deselect — show is handled by tap/drag/dissolve handlers
            if newIndex == nil {
                showDeleteButton = false
            }
        }

        // MARK: - Demo Animation Overlay
        if showDemoAnimation {
            let overlayColor: Color = colorScheme == .dark ? .black : .white
            ZStack {
                overlayColor.opacity(0.85)
                    .ignoresSafeArea()
                LaunchAnimationView(
                    isDemoMode: true,
                    onFadeOutStart: {},
                    onFinish: {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            showDemoAnimation = false
                        }
                    }
                )
            }
            .transition(.opacity)
            .zIndex(100)
        }

        // MARK: - 懸浮車道導航框（常態化：有目的地時自動顯示）
        VStack {
            FloatingLaneGuidanceView(naviManager: naviManager)
                .padding(.top, 60)
            Spacer()
        }
        .allowsHitTesting(naviManager.showLaneGuidance)
        .onChange(of: destinationManager.selectedDestination?.id) { _, _ in
            meterRouteTarget = nil
            meterDirections?.cancel()
            meterDirections = nil
            // 目的地變更時，自動開始/停止車道導航
            syncLaneNavigation()
        }
        .onAppear {
            syncLaneNavigation()
        }

        } // ZStack
    }

    // MARK: - 地址輪播（POI名稱 ↔ 街道名）
    private func startAddressAlternatingIfNeeded() {
        addressAlternatingTimer?.invalidate()
        addressAlternatingTimer = nil

        let hasPOI = !locationManager.currentPOIName.isEmpty
        let hasAddress = !locationManager.currentAddress.isEmpty
        let streetName = hasPOI ? locationManager.currentAddress : ""

        guard hasPOI && hasAddress && streetName != locationManager.currentPOIName else {
            showPOIName = false
            return
        }

        let isDriving = locationManager.speed >= 8

        // 開車時：街道名 10 秒 → POI 名 2 秒 → 循環
        // 停車瞬間：切換到 POI，然後 POI 2 秒 → 街道名 10 秒 → 循環
        showPOIName = isDriving ? false : true

        addressAlternatingTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: true) { _ in
            DispatchQueue.main.async {
                let driving = self.locationManager.speed >= 8
                if driving {
                    // 開車：街道名 10 秒 → POI 2 秒
                    withAnimation(.easeInOut(duration: 0.4)) {
                        self.showPOIName = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                        guard self.addressAlternatingTimer != nil else { return }
                        withAnimation(.easeInOut(duration: 0.4)) {
                            self.showPOIName = true
                        }
                    }
                } else {
                    // 停車：POI 2 秒 → 街道名 10 秒
                    withAnimation(.easeInOut(duration: 0.4)) {
                        self.showPOIName = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        guard self.addressAlternatingTimer != nil else { return }
                        withAnimation(.easeInOut(duration: 0.4)) {
                            self.showPOIName = false
                        }
                    }
                }
            }
        }

        // 第一個切換
        if isDriving {
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                guard self.addressAlternatingTimer != nil else { return }
                withAnimation(.easeInOut(duration: 0.4)) {
                    self.showPOIName = true
                }
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                guard self.addressAlternatingTimer != nil else { return }
                withAnimation(.easeInOut(duration: 0.4)) {
                    self.showPOIName = false
                }
            }
        }
    }

    /// 當前顯示嘅地址文字（考慮輪播）
    private var displayAddress: String {
        let hasPOI = !locationManager.currentPOIName.isEmpty
        let streetName = locationManager.currentAddress

        if hasPOI && !streetName.isEmpty && streetName != locationManager.currentPOIName {
            return showPOIName ? locationManager.currentPOIName : streetName
        }
        return locationManager.currentAddress
    }

    // MARK: - 同步車道導航（有目的地時自動開始，無時停止）
    private func syncLaneNavigation() {
        if let dest = destinationManager.selectedDestination {
            let currentLoc = locationManager.lastLocation?.coordinate
            if let loc = currentLoc {
                // 有目的地 + 有當前位置 → 自動開始靜默導航
                if !naviManager.isNavigating {
                    naviManager.startSilentNavigation(to: dest)
                }
            }
        } else {
            // 冇目的地 → 停止導航
            if naviManager.isNavigating {
                naviManager.stopNavigation()
            }
        }
    }

    // MARK: - Home Content
    var homeContent: some View {
        GeometryReader { geo in
            let newLandscape = geo.size.width > geo.size.height
            Color.clear.onAppear {
                isLandscape = newLandscape
                addressRevealProgress = locationManager.currentAddress.isEmpty ? 0 : 1
            }
                .onChange(of: newLandscape) { _, v in isLandscape = v }
                .onChange(of: locationManager.currentAddress) { _, newAddress in
                    if !newAddress.isEmpty {
                        roseLoopSpeed = 8.0
                        withAnimation(.easeInOut(duration: 0.45)) {
                            addressRevealProgress = 1
                            // Force address display for 5s when it first loads
                            if showSpeedInfo {
                                showSpeedInfo = false
                                stopRandomInfoTimer()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        showSpeedInfo = true
                                    }
                                }
                            }
                        }
                    } else {
                        roseLoopSpeed = 1.0
                        roseOpacity = 1.0
                        roseBlurRadius = 0
                        withAnimation(.easeInOut(duration: 0.25)) {
                            addressRevealProgress = 0
                        }
                    }
                    // 啟動/停止地址輪播
                    startAddressAlternatingIfNeeded()
                }
                .onChange(of: locationManager.currentPOIName) { _, _ in
                    startAddressAlternatingIfNeeded()
                }
                .onChange(of: locationManager.currentLocality) { _, newLocality in
                    if !newLocality.isEmpty {
                        parkingFloorStore.updateMissingLocalities(currentLocality: newLocality)
                    }
                }
                .onChange(of: locationManager.speed) { _, newSpeed in
                    // 時速跨越 8 km/h 閾值時重新啟動輪播
                    let wasDriving = showPOIName == false  // 之前顯示街道名 = 開車中
                    let isNowDriving = newSpeed >= 8
                    if wasDriving != isNowDriving {
                        startAddressAlternatingIfNeeded()
                    }
                }
            ZStack {
            if showMap || showSatellite {
                if darkKnightMode {
                    // 黑武士模式：地圖喺圓角容器內，邊緣模糊+暗邊，向中心減弱
                    Color.black.ignoresSafeArea()

                    ZStack {
                        // 底層：模糊版地圖（邊緣模糊效果）
                        VignetteMapView(savedRegion: $mapRegion, savedCamera: $mapCamera, firstFlyTrigger: $firstMapFlyTrigger, stationaryTrackingTrigger: stationaryTrackingTrigger, northOverrideTrackingToken: northOverrideTrackingToken, routeOverlay: routePolyline, routeAnimationOverlay: routeAnimationPolyline, followHeading: mapHeadingMode.isActive, continuousFollow: mapHeadingMode.isContinuous, hkDetailMode: hkDetailMode, parkingPoints: Array(parkingFloorStore.allPoints.prefix(30)), parkingPointTitlePrefixesByID: parkingFloorStore.lotNameByPointID, selectedParkingPointID: selectedParkingPointID, onSelectParkingPoint: { _ in }, onMoveParkingPoint: { _, _ in }, routePriorityToken: routePriorityToken, routePriorityAnchor: routePriorityAnchor, routeOverlayToken: routeOverlayToken, routeOverlayAnimationToken: routeOverlayAnimationToken, mapStyleIndex: mapStyleIndex, showSatellite: showSatellite, centerOffsetX: 0, hideCompass: true, onMapBlankTap: {}, onSelectHKLocation: { _ in })
                        .blur(radius: 25)
                        .clipShape(RoundedRectangle(cornerRadius: darkKnightMapCornerRadius))
                        .allowsHitTesting(false)

                        // 頂層：清晰地圖（中心區域，邊緣透明）
                        VignetteMapView(savedRegion: $mapRegion, savedCamera: $mapCamera, firstFlyTrigger: $firstMapFlyTrigger, stationaryTrackingTrigger: stationaryTrackingTrigger, northOverrideTrackingToken: northOverrideTrackingToken, routeOverlay: routePolyline, routeAnimationOverlay: routeAnimationPolyline, followHeading: mapHeadingMode.isActive, continuousFollow: mapHeadingMode.isContinuous, hkDetailMode: hkDetailMode, parkingPoints: Array(parkingFloorStore.allPoints.prefix(30)), parkingPointTitlePrefixesByID: parkingFloorStore.lotNameByPointID, selectedParkingPointID: selectedParkingPointID, onSelectParkingPoint: { id in
                            withAnimation(.easeOut(duration: 0.28)) {
                                selectedParkingPointID = id
                            }
                        }, onMoveParkingPoint: { id, coordinate in
                            parkingFloorStore.setPointCoordinate(pointID: id, coordinate: coordinate.gcj02ToWGS84)
                        }, routePriorityToken: routePriorityToken, routePriorityAnchor: routePriorityAnchor, routeOverlayToken: routeOverlayToken, routeOverlayAnimationToken: routeOverlayAnimationToken, mapStyleIndex: mapStyleIndex, showSatellite: showSatellite, centerOffsetX: (isLandscape && capsuleOnRight) ? (isParkingMemoryExpanded ? 420 : 300) : 0, hideCompass: true, onMapBlankTap: {
                            guard isCapsuleExpanded || isParkingMemoryExpanded else { return }
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                isCapsuleExpanded = false
                                isParkingMemoryExpanded = false
                                selectedPhotoIndex = nil
                                showDeleteButton = false
                                capsuleOnRight = false
                            }
                        }, onSelectHKLocation: { loc in
                            withAnimation(.easeOut(duration: 0.28)) {
                                selectedHKLocation = loc
                            }
                        })
                        .clipShape(RoundedRectangle(cornerRadius: darkKnightMapCornerRadius))
                        // 徑向遮罩：中心清晰，邊緣透明（露出底層模糊版）
                        .mask(
                            RadialGradient(
                                colors: [
                                    .white,
                                    .white,
                                    .white.opacity(0.7),
                                    .white.opacity(0.3),
                                    .clear,
                                ],
                                center: .center,
                                startRadius: 60,
                                endRadius: 280
                            )
                        )

                        // 暗邊層：圓角矩形同心描邊（由外到內漸變）
                        let cr = darkKnightMapCornerRadius
                        ZStack {
                            RoundedRectangle(cornerRadius: cr + 16).stroke(Color.black, lineWidth: 5)
                            RoundedRectangle(cornerRadius: cr + 10).stroke(Color.black.opacity(0.9), lineWidth: 5)
                            RoundedRectangle(cornerRadius: cr + 4).stroke(Color.black.opacity(0.8), lineWidth: 5)
                            RoundedRectangle(cornerRadius: cr - 2).stroke(Color.black.opacity(0.65), lineWidth: 5)
                            RoundedRectangle(cornerRadius: cr - 8).stroke(Color.black.opacity(0.5), lineWidth: 5)
                            RoundedRectangle(cornerRadius: cr - 14).stroke(Color.black.opacity(0.35), lineWidth: 5)
                            RoundedRectangle(cornerRadius: cr - 20).stroke(Color.black.opacity(0.2), lineWidth: 5)
                            RoundedRectangle(cornerRadius: cr - 26).stroke(Color.black.opacity(0.1), lineWidth: 5)
                            RoundedRectangle(cornerRadius: cr - 32).stroke(Color.black.opacity(0.0), lineWidth: 5)
                        }
                        .allowsHitTesting(false)

                        // 直暗邊：上
                        VStack(spacing: 0) {
                            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                                .frame(height: 60)
                            Spacer()
                        }
                        .clipShape(RoundedRectangle(cornerRadius: darkKnightMapCornerRadius))
                        .allowsHitTesting(false)

                        // 直暗邊：下
                        VStack(spacing: 0) {
                            Spacer()
                            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                                .frame(height: 60)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: darkKnightMapCornerRadius))
                        .allowsHitTesting(false)

                        // 直暗邊：左
                        HStack(spacing: 0) {
                            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: 60)
                            Spacer()
                        }
                        .clipShape(RoundedRectangle(cornerRadius: darkKnightMapCornerRadius))
                        .allowsHitTesting(false)

                        // 直暗邊：右
                        HStack(spacing: 0) {
                            Spacer()
                            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                                .frame(width: 60)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: darkKnightMapCornerRadius))
                        .allowsHitTesting(false)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: isLandscape ? 50 : 44))
                    .padding(.horizontal, isLandscape ? 80 : 20)
                    .padding(.top, isLandscape ? 50 : 100)
                    .padding(.bottom, isLandscape ? 10 : 120)
                    .transition(.opacity.animation(.easeInOut(duration: 0.8)))
                } else {
                    // 正常模式：全屏地圖
                    VignetteMapView(savedRegion: $mapRegion, savedCamera: $mapCamera, firstFlyTrigger: $firstMapFlyTrigger, stationaryTrackingTrigger: stationaryTrackingTrigger, northOverrideTrackingToken: northOverrideTrackingToken, routeOverlay: routePolyline, routeAnimationOverlay: routeAnimationPolyline, followHeading: mapHeadingMode.isActive, continuousFollow: mapHeadingMode.isContinuous, hkDetailMode: hkDetailMode, parkingPoints: Array(parkingFloorStore.allPoints.prefix(30)), parkingPointTitlePrefixesByID: parkingFloorStore.lotNameByPointID, selectedParkingPointID: selectedParkingPointID, onSelectParkingPoint: { id in
                        withAnimation(.easeOut(duration: 0.28)) {
                            selectedParkingPointID = id
                        }
                    }, onMoveParkingPoint: { id, coordinate in
                        parkingFloorStore.setPointCoordinate(pointID: id, coordinate: coordinate.gcj02ToWGS84)
                    }, routePriorityToken: routePriorityToken, routePriorityAnchor: routePriorityAnchor, routeOverlayToken: routeOverlayToken, routeOverlayAnimationToken: routeOverlayAnimationToken, mapStyleIndex: mapStyleIndex, showSatellite: showSatellite, centerOffsetX: (isLandscape && capsuleOnRight) ? (isParkingMemoryExpanded ? 420 : 300) : 0, onMapBlankTap: {
                        guard isCapsuleExpanded || isParkingMemoryExpanded else { return }
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            isCapsuleExpanded = false
                            isParkingMemoryExpanded = false
                            selectedPhotoIndex = nil
                            showDeleteButton = false
                            capsuleOnRight = false
                        }
                    }, onSelectHKLocation: { loc in
                        withAnimation(.easeOut(duration: 0.28)) {
                            selectedHKLocation = loc
                        }
                    })
                    .ignoresSafeArea()
                    .transition(.opacity.animation(.easeInOut(duration: 0.5)))
                }
            } else if darkKnightMode {
                Color.black.ignoresSafeArea()
            } else {
                AnimatedBackground(clock: animationClock, colorSchemeIndex: colorSchemeIndex, isVoiceRecording: false, orbEnabled: orbMasterEnabled && orbBackgroundHome, useTimeBasedOrb: orbMasterEnabled && orbBackgroundHome && useTimeBasedOrb, phaseManager: timePhaseManager)
                    .ignoresSafeArea()
            }

            // 冇開地圖時嘅收縮膠囊 fallback（開咗地圖就由 MKMapView 自己嘅
            // tap gesture 處理，噉先唔會擋住地圖操作）
            if (isCapsuleExpanded || isParkingMemoryExpanded || showingExpandedPhotos) && !showMap && !showSatellite {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            isCapsuleExpanded = false
                            isParkingMemoryExpanded = false
                            showingExpandedPhotos = false
                            selectedPhotoIndex = nil
                            showDeleteButton = false
                            capsuleOnRight = false
                            tiltAngleX = [:]
                            tiltAngleY = [:]
                        }
                    }
            }

            ZStack {
                VStack(spacing: 0) {
                    HStack(alignment: .center) {
                        // 液態玻璃標題
                        let titleText = Text(String(localized: "🦍 Gorilla")).font(.largeTitle.bold())
                        let goldColor = Color(hex: "FFC46D")
                        ZStack {
                            // 玻璃材料
                            (darkKnightMode ? goldColor.opacity(0.15) : Color.white.opacity(0.01))
                                .frame(width: 220, height: 50)
                                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                                .mask(titleText)

                            // 頂部高光邊緣
                            titleText
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: darkKnightMode
                                            ? [goldColor.opacity(0.9), .clear]
                                            : [.white.opacity(0.9), .clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .blendMode(.overlay)
                                .opacity(0.8)

                            // 左上斜角高光
                            titleText
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: darkKnightMode
                                            ? [goldColor.opacity(0.7), .clear, goldColor.opacity(0.35)]
                                            : [.white.opacity(0.7), .clear, .white.opacity(0.35)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .blendMode(.screen)
                                .opacity(0.6)
                        }
                        .compositingGroup()
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.5)) {
                                showDemoAnimation = true
                            }
                        }
                        Spacer()
                        gpsStatusBadge
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, isLandscape ? 43 : 30)
                    .frame(height: 44)

                    Spacer(minLength: 0)
                }

                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    let buttonOffset: CGFloat = !isLandscape ? (isParkingMemoryExpanded ? -453 : (isFloorCurveInCapsule ? -170 : (isCapsuleExpanded ? -140 : 0))) : 0
                    let landscapeButtonOffset: CGFloat = (isLandscape && (showMap || showSatellite)) ? 20 : 0
                    HStack {
                        if !hkDetailMode {
                            VStack(spacing: 10) {
                                if showMap || showSatellite {
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            switch mapHeadingMode {
                                            case .north: mapHeadingMode = .follow
                                            case .follow: mapHeadingMode = .continuousFollow
                                            case .continuousFollow: mapHeadingMode = .north
                                            }
                                        }
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            headingToastText = mapHeadingMode.label
                                        }
                                        headingToastTimer?.invalidate()
                                        headingToastTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
                                            withAnimation(.easeOut(duration: 0.35)) {
                                                headingToastText = nil
                                            }
                                        }
                                    } label: {
                                        Image(systemName: mapHeadingMode.iconName)
                                            .font(.system(size: 20, weight: .medium))
                                            .foregroundStyle(mapHeadingMode.isActive ? adaptiveTextColor() : adaptiveTextColor(opacity: 0.5))
                                            .frame(width: 44, height: 44)
                                            .id(mapHeadingMode)
                                            .transition(AnyTransition.blurFade)
                                            .animation(.easeInOut(duration: 0.25), value: mapHeadingMode)
                                    }
                                    .buttonStyle(.glass)
                                    .overlay(alignment: .trailing) {
                                        if let toast = headingToastText {
                                            Text(toast)
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundStyle(.primary)
                                                .frame(width: 72, height: 28)
                                                .glassEffect(.regular, in: .capsule)
                                                .offset(x: 78)
                                                .transition(.blurReplace())
                                                .allowsHitTesting(false)
                                        }
                                    }
                                }

                                Menu {
                                    Button {
                                        showingAddDestination = true
                                    } label: {
                                        Label(String(localized: "新增目的地"), systemImage: "plus")
                                    }

                                    // 更名停車場（排除重複 + 排除唔同地區嘅）
                                    let currentCity = locationManager.currentLocality
                                    let namedLots = parkingFloorStore.lots.filter { lot in
                                        guard let name = lot.name, !name.isEmpty else { return false }
                                        // 排除同手動目的地距離 <200m 嘅
                                        let isDuplicate = destinationManager.destinations.contains { dest in
                                            let a = CLLocation(latitude: lot.centerLatitude, longitude: lot.centerLongitude)
                                            let b = CLLocation(latitude: dest.coordinate.latitude, longitude: dest.coordinate.longitude)
                                            return a.distance(from: b) < 200
                                        }
                                        guard !isDuplicate else { return false }
                                        // 排除唔同城市嘅（有 locality 且唔同就排除）
                                        if !currentCity.isEmpty, let lotCity = lot.locality, !lotCity.isEmpty {
                                            return lotCity == currentCity
                                        }
                                        return true
                                    }
                                    if !namedLots.isEmpty {
                                        Divider()
                                        Text("停車場")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        ForEach(namedLots, id: \.id) { lot in
                                        Button {
                                            var dest = destinationManager.findOrCreateDestination(
                                                for: PlaceInfo(key: "lot:\(lot.id)", kind: .namedLot, displayName: lot.name ?? "", latitude: lot.centerLatitude, longitude: lot.centerLongitude, lotID: lot.id, updatedAt: lot.updatedAt)
                                            )
                                            // 填充 locality
                                            if dest.locality == nil, !currentCity.isEmpty {
                                                dest.locality = currentCity
                                                destinationManager.updateDestination(dest)
                                            }
                                            destinationManager.selectDestination(dest)
                                                if isCapsuleExpanded { refreshETA() }
                                                if showingRoute { recalculateRoute() }
                                            } label: {
                                                HStack {
                                                    Image(systemName: "car.fill")
                                                        .font(.system(size: 10))
                                                        .foregroundColor(.orange)
                                                    Text(lot.name ?? "")
                                                }
                                            }
                                        }
                                    }

                                    // 地址重集（排除重複）
                                    let clusters = TripPredictor.shared.placeCatalog.values.filter { place in
                                        guard place.kind == .addressCluster else { return false }
                                        let isDuplicate = destinationManager.destinations.contains { dest in
                                            let a = CLLocation(latitude: place.latitude, longitude: place.longitude)
                                            let b = CLLocation(latitude: dest.coordinate.latitude, longitude: dest.coordinate.longitude)
                                            return a.distance(from: b) < 200
                                        }
                                        return !isDuplicate
                                    }
                                    if !clusters.isEmpty {
                                        Divider()
                                        Text("學習地點")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        ForEach(Array(clusters.sorted(by: { $0.displayName < $1.displayName })), id: \.key) { place in
                                            Button {
                                                let dest = destinationManager.findOrCreateDestination(for: place)
                                                destinationManager.selectDestination(dest)
                                                if isCapsuleExpanded { refreshETA() }
                                                if showingRoute { recalculateRoute() }
                                            } label: {
                                                HStack {
                                                    Image(systemName: "mappin.and.ellipse")
                                                        .font(.system(size: 10))
                                                        .foregroundColor(.blue)
                                                    Text(place.displayName)
                                                }
                                            }
                                        }
                                    }

                                    // 手動添加嘅目的地（按城市篩選）
                                    let filteredDestinations = destinationManager.destinations.filter { dest in
                                        // 有 locality 且唔同就排除
                                        if !currentCity.isEmpty, let destCity = dest.locality, !destCity.isEmpty {
                                            return destCity == currentCity
                                        }
                                        // 冇 locality 嘅舊數據，用距離判斷（同城大約 <30km）
                                        if let loc = locationManager.lastLocation {
                                            let destLoc = CLLocation(latitude: dest.coordinate.latitude, longitude: dest.coordinate.longitude)
                                            return loc.distance(from: destLoc) < 30000
                                        }
                                        return true
                                    }
                                    if !filteredDestinations.isEmpty {
                                        Divider()
                                        Text("我的目的地")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        ForEach(filteredDestinations) { destination in
                                            Button {
                                                destinationManager.selectDestination(destination)
                                                if isCapsuleExpanded { refreshETA() }
                                                if showingRoute { recalculateRoute() }
                                            } label: {
                                                HStack {
                                                    Circle()
                                                        .fill(destination.color)
                                                        .frame(width: 8, height: 8)
                                                    Text(destination.name)
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundStyle(adaptiveTextColor())
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.glass)

                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        if !showMap && !showSatellite {
                                            // 光球 → 地圖
                                            showMap = true
                                        } else if showMap && !showSatellite {
                                            // 地圖 → 衛星3D
                                            showSatellite = true
                                            showMap = false
                                        } else {
                                            // 衛星3D → 光球
                                            showSatellite = false
                                        }
                                    }
                                }) {
                                    Image(systemName: globeToggleIcon)
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundStyle(adaptiveTextColor())
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.glass)
                            }
                            .padding(.leading, 16)
                            .padding(.bottom, 72)
                            .offset(y: buttonOffset + landscapeButtonOffset)
                            .animation(.timingCurve(0.4, 0.0, 0.2, 1.0, duration: 0.5), value: buttonOffset)
                        }

                        Spacer()
                    }
                }
            }

            if (showMap || showSatellite), let selected = selectedParkingPoint {
                parkingPointCapsule(point: selected)
                    .transition(
                        .asymmetric(
                            insertion: .modifier(
                                active: BlurSlideModifier(blur: 28, y: 10, scale: 0.985),
                                identity: BlurSlideModifier(blur: 0, y: 0, scale: 1)
                            ),
                            removal: .modifier(
                                active: BlurSlideModifier(blur: 28, y: 0, scale: 0.985),
                                identity: BlurSlideModifier(blur: 0, y: 0, scale: 1)
                            )
                        )
                    )
                    .zIndex(20)
            }

            if (showMap || showSatellite), let meter = meterManager.selectedMeter {
                ZStack {
                    Color.black.opacity(0.001).ignoresSafeArea().onTapGesture { meterManager.selectedMeter = nil }
                    ScrollView {
                        MeterDetailCapsule(meter: meter, manager: meterManager,
                                           onClose: { meterManager.selectedMeter = nil },
                                           onNavigate: { startNavigationToMeter(meter) })
                            .padding(.vertical, 20)
                    }.frame(maxHeight: 500)
                }.zIndex(23)
            } else if let notice = meterManager.notice, selectedParkingPointID == nil, selectedHKLocation == nil {
                MeterNoticeCapsule(notice: notice, onCancel: { meterManager.dismissNotice() }, onAction: {
                    meterManager.dismissNotice()
                    if notice.kind == .destination { startNavigationToMeter(notice.meter) }
                    else { MeterPayment.open(manager: meterManager) }
                }).zIndex(23)
            }

            if (showMap || showSatellite), let hkLoc = selectedHKLocation {
                hkLocationCapsule(title: hkLoc.title, coordinate: hkLoc.coordinate)
                    .transition(
                        .asymmetric(
                            insertion: .modifier(
                                active: BlurSlideModifier(blur: 28, y: 10, scale: 0.985),
                                identity: BlurSlideModifier(blur: 0, y: 0, scale: 1)
                            ),
                            removal: .modifier(
                                active: BlurSlideModifier(blur: 28, y: 0, scale: 0.985),
                                identity: BlurSlideModifier(blur: 0, y: 0, scale: 1)
                            )
                        )
                    )
                    .zIndex(20)
            }

            if showingTripConfirm, let p = tripConfirmPrediction {
                Color.black.opacity(0.42)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(24)
                    .onTapGesture {
                        withAnimation(.easeIn(duration: 0.18)) {
                            showingTripConfirm = false
                            tripConfirmPrediction = nil
                        }
                    }

                tripConfirmCard(prediction: p)
                    .frame(maxWidth: min(560, geo.size.width - 44))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .transition(
                        .asymmetric(
                            insertion: .modifier(
                                active: BlurSlideModifier(blur: 28, y: 18, scale: 0.96),
                                identity: BlurSlideModifier(blur: 0, y: 0, scale: 1)
                            ),
                            removal: .modifier(
                                active: BlurSlideModifier(blur: 28, y: 8, scale: 0.96),
                                identity: BlurSlideModifier(blur: 0, y: 0, scale: 1)
                            )
                        )
                    )
                    .zIndex(25)
            }

            if showFloorConfirm, let floor = recognizedFloorToConfirm {
                floorConfirmCard(floorIndex: floor, floorText: recognizedFloorText ?? "\(floor)" + String(localized: "樓"))
                    .frame(maxWidth: min(400, geo.size.width - 44))
                    .transition(
                        .asymmetric(
                            insertion: .modifier(
                                active: BlurSlideModifier(blur: 28, y: 18, scale: 0.96),
                                identity: BlurSlideModifier(blur: 0, y: 0, scale: 1)
                            ),
                            removal: .modifier(
                                active: BlurSlideModifier(blur: 28, y: 8, scale: 0.96),
                                identity: BlurSlideModifier(blur: 0, y: 0, scale: 1)
                            )
                        )
                    )
                    .zIndex(27)
            }

            // Address bar：放在底部，TabView 导航栏上方，永远显示
            addressCapsule
                .blur(radius: capsuleAppeared ? 0 : 30)
                .opacity(capsuleAppeared ? 1 : 0)
                .padding(.bottom, 20)
                .offset(x: isLandscape && capsuleOnRight ? (isParkingMemoryExpanded ? 135 : 210) : 0)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: capsuleOnRight)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 30)
                        .onEnded { value in
                            guard isLandscape && (isCapsuleExpanded || isParkingMemoryExpanded || isFloorCurveInCapsule) else { return }
                            let horizontal = value.translation.width
                            let vertical = value.translation.height
                            guard abs(horizontal) > abs(vertical) * 2 else { return }
                            if horizontal > 30 && !capsuleOnRight {
                                withAnimation { capsuleOnRight = true }
                            } else if horizontal < -30 && capsuleOnRight {
                                withAnimation { capsuleOnRight = false }
                            }
                        }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(width: geo.size.width, height: geo.size.height)
        }
        .onChange(of: showMap) { _, newValue in
            if newValue {
                if !hasShownMapFirstTime {
                    hasShownMapFirstTime = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    firstMapFlyTrigger += 1
                }
            }
        }
        .sheet(isPresented: $showingAddDestination) {
            AddDestinationView()
                .environmentObject(destinationManager)
                .environmentObject(locationManager)
        }
        .sheet(isPresented: $showSpotEditor) {
            SpotEditorSheet(
                spotNumber: $editSpotNumber,
                areaCode: $editAreaCode,
                floorText: $editFloorText,
                onSave: {
                    llmSpotNumber = editSpotNumber.isEmpty ? nil : editSpotNumber
                    llmAreaCode = editAreaCode.isEmpty ? nil : editAreaCode
                    llmFloorText = editFloorText.isEmpty ? nil : editFloorText
                    if let idx = Self.parseFloorIndex(editFloorText) {
                        llmFloorIndex = idx
                    }
                    parkingFloorStore.updateLLMData(
                        spotNumber: llmSpotNumber, areaCode: llmAreaCode,
                        floorText: llmFloorText, floorIndex: llmFloorIndex
                    )
                }
            )
        }
        // MARK: Trip Predictor bindings
        .onChange(of: tripPredictor.pendingConfirm) { (_: PendingTripPrediction?, newValue: PendingTripPrediction?) in
            if let p = newValue {
                tripConfirmPrediction = p
                tripToastPrediction = nil
                showingTripConfirm = true
            } else if showingTripConfirm && tripConfirmPrediction == nil {
                showingTripConfirm = false
            }
        }
        .onChange(of: tripPredictor.pendingToast) { (_: PendingTripPrediction?, newValue: PendingTripPrediction?) in
            if let p = newValue {
                tripToastAutoDismiss?.cancel()
                tripToastPrediction = p
                // auto switch destination 即刻生效
                Task { @MainActor in
                    let _ = DestinationManager.shared.applyAutoPrediction(p)
                }
                // auto dismiss after 2.6s
                let work = DispatchWorkItem { [weak tripPredictor] in
                    if let cur = tripToastPrediction, cur.id == p.id {
                        tripToastPrediction = nil
                        tripPredictor?.pendingToast = nil
                    }
                }
                tripToastAutoDismiss = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: work)
            }
        }

        .overlay(alignment: .top) {
            if let p = tripToastPrediction {
                tripToast(prediction: p)
                    .padding(.top, 20)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8),
                               value: tripToastPrediction != nil)
            }
        }
    }

    // MARK: - Trip Predictor UI
    @ViewBuilder
    private func tripConfirmCard(prediction p: PendingTripPrediction) -> some View {
        let confidencePct = Int((p.confidence * 100).rounded())
        let tintColor = Color(hex: "0098FF") ?? .blue
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "路線預測"))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                Text(String(localized: "根據過往習慣判斷"))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.62))
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(tintColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(p.predicted.displayName)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                        Text(p.twoStepAhead != nil
                             ? String(localized: "之後再去：") + "\(p.twoStepAhead!.displayName)"
                             : String(localized: "單站目的地"))
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.68))
                    }
                    Spacer()
                }
                .padding(18)

                VStack(spacing: 10) {
                    HStack {
                        Text(String(localized: "信心度"))
                            .foregroundStyle(.white.opacity(0.72))
                        Spacer()
                        Text("\(confidencePct)%  ·  \(String(localized: "樣本")) \(p.totalSamples)")
                            .foregroundStyle(.white.opacity(0.88))
                    }
                    ProgressView(value: p.confidence)
                        .tint(tintColor)
                }
                .padding(.horizontal, 2)
            }

            VStack(spacing: 12) {
                Button {
                    withAnimation(.easeIn(duration: 0.18)) {
                        showingTripConfirm = false
                        tripConfirmPrediction = nil
                    }
                    Task { @MainActor in
                        TripPredictor.shared.applyUserFeedback(
                            prediction: p,
                            actualNextPlaceKey: p.predicted.key,
                            confirmed: true
                        )
                        let _ = DestinationManager.shared.applyAutoPrediction(p)
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                        Text(String(localized: "是，切換到「") + "\(p.predicted.displayName)" + String(localized: "」"))
                            .font(.body.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(.black)
                    .background(
                        Capsule()
                            .fill(Color.white)
                    )
                    .glassEffect(.regular, in: .capsule)
                    .clipShape(.capsule)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeIn(duration: 0.18)) {
                        showingTripConfirm = false
                        tripConfirmPrediction = nil
                    }
                    Task { @MainActor in
                        TripPredictor.shared.applyUserFeedback(
                            prediction: p,
                            actualNextPlaceKey: nil,
                            confirmed: false
                        )
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "xmark.circle")
                        Text(String(localized: "否，不是這裡"))
                            .font(.body.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(.white)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                    )
                    .glassEffect(.regular, in: .capsule)
                    .clipShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(26)
        .background(
            RoundedRectangle(cornerRadius: 30)
                .fill(Color.black.opacity(0.58))
        )
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
        .clipShape(.rect(cornerRadius: 30))
        .borderBeam(
            size: .large,
            palette: .ocean,
            cornerRadius: 30,
            enableRotate: false,
            enablePulse: true
        )
    }

    // MARK: - Floor Confirmation Card
    private func floorConfirmCard(floorIndex: Int, floorText: String) -> some View {
        let tintColor = Color(hex: parkingTimerColorHex) ?? Color(hex: "46ADB8") ?? .teal
        return HStack(spacing: 0) {
            // Left: icon + floor info
            HStack(spacing: 12) {
                Image(systemName: "building.2.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(tintColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(floorText)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    Text(String(localized: "樓層指數：") + "\(floorIndex)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.68))
                }
            }
            .padding(.leading, 18)

            Spacer()

            // Right: confirm / reject buttons
            HStack(spacing: 10) {
                Button {
                    // User confirmed — write the deferred floor now
                    llmFloorText = pendingFloorText ?? floorText
                    llmFloorIndex = pendingFloorIndex ?? floorIndex
                    parkingFloorStore.updateLLMData(
                        spotNumber: llmSpotNumber, areaCode: llmAreaCode,
                        floorText: pendingFloorText ?? floorText,
                        floorIndex: pendingFloorIndex ?? floorIndex
                    )
                    if let photoID = currentRecognizingPhotoID ?? parkingPhotoContributions.keys.first {
                        parkingPhotoContributions[photoID, default: [:]]["floor"] = pendingFloorText ?? floorText
                    }
                    pendingOriginalFloorIndex = nil
                    pendingFloorText = nil
                    pendingFloorIndex = nil
                    withAnimation(.easeIn(duration: 0.18)) {
                        showFloorConfirm = false
                        hasConfirmedFloorThisSession = true
                    }
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.white)
                }
                .buttonStyle(.plain)

                Button {
                    // User rejected — revert to original barometer floor
                    if let orig = pendingOriginalFloorIndex {
                        llmFloorIndex = orig
                        llmFloorText = nil
                        parkingFloorStore.updateLLMData(
                            spotNumber: llmSpotNumber, areaCode: llmAreaCode,
                            floorText: nil, floorIndex: orig
                        )
                    }
                    pendingOriginalFloorIndex = nil
                    pendingFloorText = nil
                    pendingFloorIndex = nil
                    withAnimation(.easeIn(duration: 0.18)) {
                        showFloorConfirm = false
                        hasConfirmedFloorThisSession = true
                    }
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 18)
        }
        .padding(.vertical, 14)
        .glassEffect(.regular, in: .capsule)
        .clipShape(.capsule)
        .borderBeam(
            size: .large,
            palette: .senshackDark,
            cornerRadius: 30,
            enableRotate: false,
            enablePulse: true,
            showSurface: false
        )
    }

    // MARK: - Floor Curve Popup (Auto Garage Detection)

    /// 啟動地庫下降偵測
    private func startFloorCurveDetection() {
        floorCurveSampleTimer?.invalidate()
        // 低速時每 0.25 秒偵測一次，高速時每 1 秒一次
        let interval: TimeInterval = parkingFloorStore.barometer.currentSpeedKmh < 20 ? 0.25 : 1.0
        floorCurveSampleTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            DispatchQueue.main.async {
                self.checkGarageDescent()
                // 動態調整頻率
                self.adjustDetectionFrequency()
            }
        }
    }

    /// 根據速度動態調整偵測頻率
    private func adjustDetectionFrequency() {
        let barometer = parkingFloorStore.barometer
        let newInterval: TimeInterval = barometer.currentSpeedKmh < 20 ? 0.25 : 1.0
        let currentInterval = floorCurveSampleTimer?.timeInterval ?? 1.0
        // 頻率變化超過 0.1 秒才重啟
        if abs(newInterval - currentInterval) > 0.1 {
            startFloorCurveDetection()
        }
    }

    /// 停止偵測
    private func stopFloorCurveDetection() {
        floorCurveSampleTimer?.invalidate()
        floorCurveSampleTimer = nil
        floorCurveDismissTimer?.invalidate()
        floorCurveDismissTimer = nil
    }

    /// 檢查是否正在下降入地庫
    private func checkGarageDescent() {
        // 已經顯示緊就唔好重複觸發
        guard !isFloorCurveInCapsule else { return }

        let barometer = parkingFloorStore.barometer
        guard barometer.samples.count >= 3 else { return }  // 3 個樣本即可開始（~3 秒）

        // 取最近 3 個樣本（減少延遲）
        let recent = Array(barometer.samples.suffix(3))
        let speeds = recent.map { $0.speedKmh }

        // 全部都要低速（< 20 km/h）
        guard speeds.allSatisfy({ $0 < 20 }) else {
            floorCurveDescendingCount = 0
            return
        }

        if floorCurveTriggerMode == 0 {
            // 模式 A（純速度）：速度 < 20 就觸發，不需要海拔持續下降
            floorCurveDescendingCount += 1
            if floorCurveDescendingCount >= 2 {
                triggerFloorCurvePopup()
            }
        } else {
            // 模式 B（速度 + 海拔）：需要偵測到海拔變化
            let alts = recent.map { $0.relativeAltitude }
            // 檢查海拔是否有明顯變化（總變化 > 0.15m，更敏感）
            let altChange = (alts.max() ?? 0) - (alts.min() ?? 0)
            if altChange > 0.15 {
                floorCurveDescendingCount += 1
                // 連續 2 次檢測到變化才觸發
                if floorCurveDescendingCount >= 2 {
                    triggerFloorCurvePopup()
                }
            } else {
                floorCurveDescendingCount = 0
            }
        }
    }

    /// 觸發彈窗
    private func triggerFloorCurvePopup() {
        let barometer = parkingFloorStore.barometer
        guard let lastSample = barometer.samples.last else { return }

        floorCurveBaseAltitude = lastSample.relativeAltitude
        floorCurveHistory = [0] // 起始點為 0
        floorCurveLocked = false
        floorCurveLockedFloor = 0
        floorCurveDescendingCount = 0

        floorCurveAppearTime = Date()
        floorCurveLockAnimating = false

        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            isFloorCurveInCapsule = true
        }

        // 播放樓層探測態出現音效
        sfxPlayer.playFloorCurveAppear()

        // 開始 0.5 秒採樣
        startFloorCurveSampling()

        // 監聽停留偵測
        startStationaryMonitoring()
    }

    /// 0.5 秒採樣海拔
    private func startFloorCurveSampling() {
        floorCurveSampleTimer?.invalidate()
        floorCurveSampleTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            DispatchQueue.main.async {
                guard self.isFloorCurveInCapsule, !self.floorCurveLocked else { return }
                let barometer = self.parkingFloorStore.barometer
                guard let lastSample = barometer.samples.last else { return }
                // 速度為0時不加新數據點，但保持現有曲線不動
                guard barometer.currentSpeedKmh > 0.5 else { return }
                let relativeAlt = lastSample.relativeAltitude - self.floorCurveBaseAltitude
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.floorCurveHistory.append(relativeAlt)
                }
            }
        }
    }

    /// 監聽停留偵測
    private func startStationaryMonitoring() {
        var lastAltitudeSample: Double? = nil
        var unchangedSeconds: Int = 0
        // 用 Timer 每秒檢查 stationaryAltitude 或速度 = 0
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            DispatchQueue.main.async {
                guard self.isFloorCurveInCapsule else {
                    timer.invalidate()
                    return
                }
                let barometer = self.parkingFloorStore.barometer

                // 檢查海拔是否有變化
                let currentAlt = barometer.samples.last?.relativeAltitude
                if let last = lastAltitudeSample, let cur = currentAlt {
                    if abs(cur - last) < 0.05 {
                        unchangedSeconds += 1
                    } else {
                        unchangedSeconds = 0
                    }
                }
                lastAltitudeSample = currentAlt

                // 海拔5秒無變化且速度為0，自動關閉
                if unchangedSeconds >= 5 && barometer.currentSpeedKmh <= 0.5 {
                    timer.invalidate()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        self.dismissFloorCurve()
                    }
                    return
                }

                // 樓層探測態出現後至少等 10 秒才能鎖定
                guard let appearTime = self.floorCurveAppearTime,
                      Date().timeIntervalSince(appearTime) >= 10.0 else { return }

                // 條件 1：stationaryAltitude 已計算（10 秒低速）
                if let statAlt = barometer.stationaryAltitude {
                    self.lockFloorCurve(statAlt: statAlt)
                    timer.invalidate()
                    return
                }

                // 條件 2：速度 = 0（停車了），立即鎖定
                if barometer.currentSpeedKmh <= 0.5 {
                    // 用最近 10 個樣本的平均海拔作為 stationary altitude
                    let recent = barometer.samples.suffix(10)
                    guard recent.count >= 3 else { return }
                    let smoothedAlt = recent.map { $0.relativeAltitude }.reduce(0, +) / Double(recent.count)
                    self.lockFloorCurve(statAlt: smoothedAlt)
                    timer.invalidate()
                }
            }
        }
    }

    /// 鎖定樓層
    private func lockFloorCurve(statAlt: Double) {
        guard !floorCurveLocked else { return }
        floorCurveLocked = true
        // 播放樓層鎖定音效
        sfxPlayer.playFloorCurveLocked()
        // 模糊漸入動畫
        floorCurveLockAnimating = false
        withAnimation(.easeInOut(duration: 0.5)) {
            floorCurveLockAnimating = true
        }

        // 計算樓層
        let barometer = parkingFloorStore.barometer
        let recent = barometer.samples.suffix(10)
        let currentAlt = recent.map { $0.relativeAltitude }.reduce(0, +) / Double(recent.count)
        let delta = currentAlt - statAlt
        // 找最近的停車場，用佢嘅 learnedMetersPerFloor
        let currentCoord = locationManager.lastLocation?.coordinate
        let nearestLotIdx = currentCoord.flatMap { parkingFloorStore.findLotIndex(near: $0, radiusMeters: 180) }
        let mpF: Double
        let offset: Double
        if let idx = nearestLotIdx, let learned = parkingFloorStore.lots[idx].learnedMetersPerFloor {
            mpF = learned
            offset = parkingFloorStore.lots[idx].learnedOffsetMeters ?? 0
        } else {
            mpF = 3.0
            offset = 0
        }
        let adjusted = delta - offset
        let raw = adjusted / mpF
        floorCurveLockedFloor = Int(raw.rounded(.toNearestOrAwayFromZero))

        // Bug 3b 修復：保存鎖定樓層到 ParkingFloorStore
        // 但如果已有照片識別的樓層，或已泊車狀態，不要覆蓋
        let lockedFloor = floorCurveLockedFloor
        let hasPhotoFloor = llmFloorIndex != nil || llmFloorText != nil
        let alreadyParked = !hasDeparted && parkingFloorStore.allPoints.contains(where: { $0.predictedFloorIndex != nil || $0.manualFloorIndex != nil })
        if !hasPhotoFloor && !alreadyParked {
            parkingFloorStore.updateActivePointFromFloorCurve(lockedFloor: lockedFloor, coordinate: currentCoord)
        }

        // 5 秒後自動關閉
        floorCurveDismissTimer?.invalidate()
        floorCurveDismissTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            DispatchQueue.main.async {
                self.dismissFloorCurve()
            }
        }
    }

    /// 重置 lift-scale 拖動狀態
    private func resetLiftScaleDrag() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
            capsuleDragOffsetY = 0
            capsuleDragScale = 1.0
        }
    }

    // MARK: - 光效動畫

    /// 光效完成動畫：上升 + 到頂後自動消失
    private func animateLightEffectToFull() {
        lightEffectDismissWorkItem?.cancel()
        lightEffectIsFadingOut = false
        lightEffectFadeProgress = 0
        lightEffectProgress = 0

        // 直接啟動上升動畫（2秒）
        withAnimation(.timingCurve(0.25, 0.1, 0.2, 1.0, duration: 2.0)) {
            lightEffectProgress = 1.0
        }

        // 到頂後 1 秒自動消失（淡出 0.8 秒）
        let workItem = DispatchWorkItem { [self] in
            withAnimation(.easeOut(duration: 0.8)) {
                lightEffectIsFadingOut = true
                lightEffectFadeProgress = 1.0
            }
            // 消失後重置
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [self] in
                lightEffectProgress = 0
                lightEffectIsFadingOut = false
                lightEffectFadeProgress = 0
            }
        }
        lightEffectDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: workItem)
    }

    /// 光效收回動畫（下滑收回時，超慢柔和）
    private func animateLightEffectRetract() {
        lightEffectDismissWorkItem?.cancel()
        lightEffectIsFadingOut = false
        lightEffectFadeProgress = 0

        // 超慢收回：2.5 秒
        withAnimation(.timingCurve(0.08, 0.0, 0.15, 1.0, duration: 2.5)) {
            lightEffectProgress = 0
        }
    }

    /// 關閉彈窗
    private func dismissFloorCurve() {
        floorCurveDismissTimer?.invalidate()
        floorCurveDismissTimer = nil
        floorCurveSampleTimer?.invalidate()
        floorCurveSampleTimer = nil
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            isFloorCurveInCapsule = false
            isCapsuleExpanded = true
            orbOpacity = 0.5
        }
        // 光效收回（暫時移除）
        // animateLightEffectRetract()
        // 重置
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            floorCurveHistory = []
            floorCurveLocked = false
            floorCurveLockAnimating = false
            floorCurveDescendingCount = 0
            floorCurveAppearTime = nil
        }
    }

    /// 膠囊內嘅樓層探測內容
    private var floorCurveCapsuleContent: some View {
        let accentColor: Color = (floorCurveHistory.last ?? 0) < 0 ? .blue : .green
        let barometer = parkingFloorStore.barometer
        let currentAlt = barometer.samples.last?.relativeAltitude ?? 0
        let relativeAlt = currentAlt - floorCurveBaseAltitude

        return VStack(spacing: 4) {
            // 頂部：返回 + 樓層探測 + 車 icon + 樓層 + 方向
            HStack {
                Button(action: {
                    dismissFloorCurve()
                }) {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(adaptiveTextColor(opacity: 0.8))
                }
                Text("樓層探測")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(adaptiveTextColor())
                Spacer()
                HStack(spacing: 6) {
                    Text(floorCurveLocked ? ParkingFloorStore.formatFloor(floorCurveLockedFloor) : String(format: "%+.1fm", relativeAlt))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.2), value: floorCurveLocked)
                        .scaleEffect(floorCurveLocked ? 1.05 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: floorCurveLocked)

                    if floorCurveLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.teal)
                            .transition(.scale.combined(with: .opacity))
                            .blur(radius: floorCurveLockAnimating ? 0 : 6)
                            .opacity(floorCurveLockAnimating ? 1 : 0)
                    }
                }
                if floorCurveLocked {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.teal)
                        .symbolEffect(.bounce, value: floorCurveLocked)
                        .blur(radius: floorCurveLockAnimating ? 0 : 6)
                        .opacity(floorCurveLockAnimating ? 1 : 0)
                } else {
                    Image(systemName: relativeAlt < 0 ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            // 曲線區域
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                ZStack {
                    if floorCurveHistory.count <= 1 {
                        ZStack {
                            Circle()
                                .fill(accentColor.opacity(0.15))
                                .frame(width: 24, height: 24)
                            Image(systemName: "car.side.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(accentColor)
                                .scaleEffect(x: -1)
                        }
                        .position(x: 18, y: h / 2)
                    } else {
                        InlineCurveContent(
                            history: floorCurveHistory,
                            w: w, h: h,
                            accentColor: accentColor,
                            carIconName: "car.side.fill"
                        )
                    }
                }
            }
            .frame(height: 110)
            .padding(.horizontal, 8)
            .background(accentColor.opacity(0.1))
            .cornerRadius(12)
            .blur(radius: floorCurveLocked ? (floorCurveLockAnimating ? 4 : 0) : 0)
            .animation(.easeInOut(duration: 0.4), value: floorCurveLockAnimating)
            .padding(.horizontal, 12)
            .overlay {
                // 鎖定後在曲線區域內顯示確認訊息
                if floorCurveLocked {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.teal)
                        Text("已鎖定樓層")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                    .blur(radius: floorCurveLockAnimating ? 0 : 8)
                    .opacity(floorCurveLockAnimating ? 1 : 0)
                    .transition(.opacity)
                }
            }

            // 速度 + 地址 + 剩餘時間（同擴展態佈局）
            HStack(alignment: .lastTextBaseline) {
                Text("\(Int(locationManager.smoothedSpeed)) km/h")
                    .font(.body.bold())
                    .foregroundStyle(adaptiveTextColor(opacity: 0.6))
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.3), value: Int(locationManager.smoothedSpeed))
                    .monospacedDigit()
                    .padding(.leading, 5)
                Spacer()
                Text(locationManager.currentAddress)
                    .font(.body.bold())
                    .foregroundStyle(adaptiveTextColor())
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.15), value: locationManager.currentAddress)
                Spacer()
                Text(etaText ?? "--")
                    .font(.body.bold())
                    .foregroundStyle(adaptiveTextColor(opacity: 0.6))
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.15), value: etaText ?? "--")
                    .monospacedDigit()
                    .frame(minWidth: 60, alignment: .trailing)
                    .padding(.trailing, 5)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

        }
    }

    /// 彈窗卡片
    private func floorCurvePopupCard(geoWidth: CGFloat) -> some View {
        let accentColor: Color = (floorCurveHistory.last ?? 0) < 0 ? .blue : .green
        let barometer = parkingFloorStore.barometer
        let currentAlt = barometer.samples.last?.relativeAltitude ?? 0
        let relativeAlt = currentAlt - floorCurveBaseAltitude

        return VStack(spacing: 10) {
            // 頂部：車 icon + 樓層 + 方向
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(accentColor.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: "car.side.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(accentColor)
                        .scaleEffect(x: -1)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("樓層探測")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Text(floorCurveLocked ? ParkingFloorStore.formatFloor(floorCurveLockedFloor) : String(format: "%+.1fm", relativeAlt))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.2), value: floorCurveLocked)
                            .scaleEffect(floorCurveLocked ? 1.05 : 1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: floorCurveLocked)

                        if floorCurveLocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.teal)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                }

                Spacer()

                if floorCurveLocked {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.teal)
                        .symbolEffect(.bounce, value: floorCurveLocked)
                } else {
                    Image(systemName: relativeAlt < 0 ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(accentColor)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)

            // 曲線區域
            floorCurveArea(accentColor: accentColor)
                .frame(height: 100)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(accentColor.opacity(0.1))
                .cornerRadius(14)
                .padding(.horizontal, 14)

            // 鎖定後顯示確認訊息
            if floorCurveLocked {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.teal)
                    Text("已鎖定樓層")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Spacer().frame(height: floorCurveLocked ? 0 : 4)
        }
        .frame(maxWidth: 340)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(Color(.secondarySystemBackground))
        )
        .cornerRadius(28)
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    /// 曲線區域
    private func floorCurveArea(accentColor: Color) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                if floorCurveHistory.count <= 1 {
                    // 只有一個初始點：顯示車喺左邊
                    ZStack {
                        Circle()
                            .fill(accentColor.opacity(0.15))
                            .frame(width: 28, height: 28)
                        Image(systemName: "car.side.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(accentColor)
                            .scaleEffect(x: -1)
                    }
                    .position(x: 20, y: h / 2)
                } else {
                    InlineCurveContent(
                        history: floorCurveHistory,
                        w: w, h: h,
                        accentColor: accentColor,
                        carIconName: "car.side.fill"
                    )
                }
            }
        }
    }

    // MARK: - Recognized Info Overlay
    private func recognizedInfoOverlay(info: ParkingRecognizedInfo) -> some View {
        let items = info.relevantItems
        let hasContent = !items.isEmpty || info.floorText != nil
        return Group {
            if hasContent {
                VStack(spacing: 4) {
                    // Show each relevant item with appropriate icon
                    ForEach(Array(items.prefix(4).enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 6) {
                            if Self.isFloorText(item) {
                                Image(systemName: "building.2.fill")
                                    .font(.system(size: 10))
                            } else if Self.isSpotNumberText(item) {
                                Image(systemName: "car.fill")
                                    .font(.system(size: 10))
                            } else {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.system(size: 10))
                            }
                            Text(item)
                                .font(.system(size: 14, weight: .bold))
                        }
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.black.opacity(0.55))
                )
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
            }
        }
    }

    private static func isFloorText(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.hasPrefix("b") || lower.hasPrefix("lg") || lower.hasPrefix("ug") ||
               lower.contains("樓") || lower.contains("層") || lower.contains("地下")
    }

    private static func isSpotNumberText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let regex = try? NSRegularExpression(pattern: "^\\d{1,5}$"),
           regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)) != nil {
            return true
        }
        return false
    }

    // MARK: - Recognizing Loading Indicator
    private var recognizingIndicator: some View {
        HStack(spacing: 6) {
            ProgressView()
                .scaleEffect(0.7)
                .tint(.white)
            Text(String(localized: "識別中..."))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.5))
        )
    }

    @ViewBuilder
    private func tripToast(prediction p: PendingTripPrediction) -> some View {
        let confidencePct = Int((p.confidence * 100).rounded())
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 18).weight(.bold))
                .foregroundStyle(Color.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "自動切換目的地：") + "\(p.predicted.displayName)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                let extra = p.twoStepAhead != nil ? "  · " + String(localized: "之後再去：") + "\(p.twoStepAhead!.displayName)" : ""
                Text(String(localized: "信心") + "\(confidencePct)%" + String(localized: " · 樣本 ") + "\(p.totalSamples)" + extra)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 520)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color.black.opacity(0.55))
        )
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .clipShape(.rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
        .padding(.horizontal, 20)
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
    }

    // MARK: - Address Capsule
    private var addressCapsule: some View {
        let baseHeight: CGFloat = isParkingMemoryExpanded ? 495 : (isFloorCurveInCapsule ? 210 : (isCapsuleExpanded ? 182 : 44))
        let capsuleHeight: CGFloat = {
            if isParkingMemoryExpanded {
                return isLandscape ? 296 : 495
            }
            if isFloorCurveInCapsule {
                return 210
            }
            let raw: CGFloat
            if capsuleDragState.active {
                if capsuleAnimationStyle == 1 {
                    raw = smoothDragHeight
                } else {
                    if capsuleDragState.mode == -1 {
                        raw = 44 + min(capsuleDragState.offset, 138)
                    } else if capsuleDragState.mode == 1 {
                        raw = 182 - min(capsuleDragState.offset, 138)
                    } else {
                        raw = baseHeight
                    }
                }
            } else if let settleHeight = capsuleSettleHeight {
                raw = settleHeight
            } else {
                raw = baseHeight
            }
            let scale = UIScreen.main.scale
            return (raw * scale).rounded() / scale
        }()
        let dragProgress: CGFloat = isParkingMemoryExpanded ? 1.0 : max(0, min((capsuleHeight - 44) / 138, 1))
        let capsuleWidth: CGFloat = {
            if isLandscape {
                if isParkingMemoryExpanded { return 525 }
                if isCapsuleExpanded || isFloorCurveInCapsule { return 370 }
                return 280
            }
            return (isCapsuleExpanded || isFloorCurveInCapsule) ? 370 : (270 + 100 * dragProgress)
        }()

        return ZStack {
            if isParkingMemoryExpanded {
                parkingMemoryContent
                    .transition(.opacity)
                    .alert(String(localized: "請啟動動作按鈕"), isPresented: $showLLMActionPrompt) {
                        Button(String(localized: "已準備好")) { startLLMPollingAfterAction() }
                        Button(String(localized: "取消"), role: .cancel) {
                            llmSoundStopTimer?.invalidate()
                            llmSoundStopTimer = nil
                            sfxPlayer.stopVLMLoadingImmediately()
                            stopOrbRecognitionBoost(triggerSixColor: false)
                            isRecognizing = false
                        }
                    } message: {
                        Text(String(localized: "圖片已複製到剪貼簿。\n請按動作按鈕執行「") + "\(llmShortcutName)" + String(localized: "」快捷指令。"))
                    }
                    .alert(String(localized: "車位資訊"), isPresented: $showRecognitionLogicAlert) {
                        Button(String(localized: "編輯")) {
                            editSpotNumber = llmSpotNumber ?? ""
                            editAreaCode = llmAreaCode ?? ""
                            editFloorText = llmFloorText ?? ""
                            showSpotEditor = true
                        }
                        Button(String(localized: "清除車位"), role: .destructive) {
                            withAnimation(.easeInOut(duration: 0.4)) {
                                clearParkingContributions()
                            }
                        }
                        Button(String(localized: "確定"), role: .cancel) {}
                    } message: {
                        Text(buildRecognitionLogicText())
                        if let raw = llmRawResult, !raw.isEmpty {
                            Text("\n" + String(localized: "原始結果：") + "\n" + raw)
                                .font(.caption)
                        }
                    }
            } else if isFloorCurveInCapsule {
                floorCurveCapsuleContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(AnyTransition.blurFade)
            } else if isCapsuleExpanded {
                expandedContent
                    .id(parkingStartTime)
                    .transition(AnyTransition.blurFade)
                    .allowsHitTesting(!capsuleDragState.active)
            } else {
                let addressReveal = locationManager.currentAddress.isEmpty ? 0 : addressRevealProgress
                ZStack {
                    RoseFourView(
                        loop: roseLoopSpeed,
                        opacity: roseOpacity * (1 - addressReveal),
                        blurRadius: roseBlurRadius + 20 * addressReveal
                    )
                    .frame(width: 50, height: 50)
                    .padding(.horizontal, 6)

                    ZStack {
                        if compactModeShowStatus {
                            HStack(spacing: 8) {
                                Text(compactStatusTitle)
                                    .font(.body.bold())
                                    .foregroundStyle(adaptiveTextColor(opacity: 0.85))
                                Text(frozenCompactStatus ?? compactStatusDuration)
                                    .font(.body.bold())
                                    .foregroundStyle(adaptiveTextColor())
                                    .contentTransition(.numericText())
                                    .animation(capsuleDragState.active ? nil : .easeInOut(duration: 0.15), value: compactStatusTickValue)
                                    .monospacedDigit()
                                    .blur(radius: capsuleDragState.active ? 6 : 0)
                                    .animation(.easeInOut(duration: 0.25), value: capsuleDragState.active)
                            }
                            .transition(.blurReplace())
                        } else if showSpeedInfo {
                            HStack(spacing: 16) {
                                Text("\(Int(locationManager.smoothedSpeed)) km/h")
                                    .font(.body.bold())
                                    .foregroundStyle(adaptiveTextColor())
                                    .contentTransition(.numericText())
                                    .monospacedDigit()
                                    .animation(.easeInOut(duration: 0.3), value: Int(locationManager.smoothedSpeed))
                                if let eta = drivingETASeconds {
                                    Text(formatCompactETA(eta))
                                        .font(.body.bold())
                                        .foregroundStyle(adaptiveTextColor())
                                        .contentTransition(.numericText())
                                }
                            }
                            .transition(.blurReplace())
                        } else {
                            Text(displayAddress)
                                .font(.body.bold())
                                .foregroundStyle(adaptiveTextColor())
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                                .transition(.blurReplace())
                                .id(showPOIName)  // 觸發 transition
                        }
                    }
                    .opacity(addressReveal)
                    .blur(radius: 20 * (1 - addressReveal))
                    .animation(.easeInOut(duration: 0.3), value: showSpeedInfo)
                    .animation(.easeInOut(duration: 0.3), value: compactModeShowStatus)
                }
                .transition(AnyTransition.blurFade)
            }
        }
        .frame(width: capsuleWidth)
        .frame(height: capsuleHeight)
        .background {
            orbBackground
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 34))
        .overlay(
            // 黑武士模式：半透明黑色覆蓋層
            RoundedRectangle(cornerRadius: 34)
                .fill(Color.black.opacity(darkKnightMode ? 0.3 : 0))
                .allowsHitTesting(false)
        )
        .clipShape(.rect(cornerRadius: 34))
        .contentShape(Rectangle())
        .scaleEffect(capsuleAnimationStyle == 1 ? capsuleDragScale : capsuleScale)
        .offset(y: capsuleAnimationStyle == 1 ? capsuleDragOffsetY : 0)
        .animation(capsuleDragState.active ? nil : .spring(response: 0.6, dampingFraction: 0.78), value: isCapsuleExpanded)
        .animation(capsuleDragState.active ? nil : .spring(response: 0.6, dampingFraction: 0.78), value: isParkingMemoryExpanded)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isFloorCurveInCapsule)
        .animation(.easeInOut(duration: 0.4), value: orbOpacity)
        .highPriorityGesture(
            DragGesture(minimumDistance: 10)
                .updating($capsuleDragState) { value, state, _ in
                    guard !isParkingMemoryExpanded else { return }
                    let dy = value.translation.height
                    if state.mode == 0 {
                        peakDragOffset = 0
                        // 凍結計時顯示
                        frozenParkingElapsed = parkingElapsed
                        frozenCompactStatus = compactStatusDuration
                        // 從當前動畫位置接手，避免跳動
                        if let settle = capsuleSettleHeight {
                            smoothDragHeight = settle
                        } else {
                            smoothDragHeight = isCapsuleExpanded ? 182 : 44
                        }
                        capsuleSettleWorkItem?.cancel()
                        capsuleSettleWorkItem = nil
                        capsuleSettleHeight = nil
                        if !isCapsuleExpanded, dy < 0 {
                            // 緊湊態上滑 → 展開
                            state.mode = -1
                            lastGestureMode = -1
                        } else if isCapsuleExpanded, dy > 0 {
                            // 展開態下滑 → 收縮
                            state.mode = 1
                            lastGestureMode = 1
                        } else if isCapsuleExpanded, dy < 0 {
                            // 展開態上滑 → 進入樓層探測
                            state.mode = -1
                            lastGestureMode = -1
                        } else {
                            state.active = false
                            state.offset = 0
                            return
                        }
                    }
                    state.active = state.mode != 0
                    if state.mode == -1 {
                        let next = min(-dy, 120)
                        state.offset = max(state.offset, max(0, next))
                    } else if state.mode == 1 {
                        let next = min(dy, 120)
                        state.offset = max(state.offset, max(0, next))
                    } else {
                        state.offset = 0
                    }
                }
                .onChanged { value in
                    guard !isParkingMemoryExpanded else { return }
                    capsuleSettleWorkItem?.cancel()
                    capsuleSettleWorkItem = nil
                    capsuleSettleHeight = nil
                    // Lift-scale: 用彈簧追蹤目標，產生延遲跟手感
                    if capsuleAnimationStyle == 1 {
                        let dy = value.translation.height
                        let maxDrag: CGFloat = 120
                        if !isCapsuleExpanded, dy < 0 {
                            let current = min(-dy, maxDrag)
                            lastDragOffset = current
                            peakDragOffset = max(peakDragOffset, current)
                            let progress = current / maxDrag
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                                capsuleDragOffsetY = -progress * 30
                                capsuleDragScale = 1.0 + progress * 0.12
                                smoothDragHeight = 44 + current
                            }
                        } else if isCapsuleExpanded, dy < 0 {
                            // 展開態上滑：準備進入樓層探測
                            let current = min(-dy, maxDrag)
                            lastDragOffset = current
                            peakDragOffset = max(peakDragOffset, current)
                            let progress = current / maxDrag
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                                capsuleDragOffsetY = -progress * 20
                                capsuleDragScale = 1.0 + progress * 0.06
                            }
                            // 光效：暫時移除
                        } else if isCapsuleExpanded, dy > 0 {
                            let current = min(dy, maxDrag)
                            lastDragOffset = current
                            peakDragOffset = max(peakDragOffset, current)
                            let progress = current / maxDrag
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                                capsuleDragOffsetY = progress * 30
                                capsuleDragScale = 1.0 - progress * 0.12
                                smoothDragHeight = 182 - current
                            }
                        } else {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                                capsuleDragOffsetY = 0
                                capsuleDragScale = 1.0
                                smoothDragHeight = isCapsuleExpanded ? 182 : 44
                            }
                        }
                    }
                }
                .onEnded { value in
                    guard !isParkingMemoryExpanded else { return }
                    // 解凍計時顯示
                    frozenParkingElapsed = nil
                    frozenCompactStatus = nil
                    let dy = value.translation.height
                    let predictedDY = value.predictedEndTranslation.height
                    let velocity = value.predictedEndTranslation.height - value.translation.height
                    let threshold: CGFloat = 50
                    // 快滑判定：速度超過 threshold/0.3s 就算快滑
                    let isFastSwipe = abs(velocity) > threshold * 0.6

                    // Lift-scale animation mode
                    if capsuleAnimationStyle == 1 {
                        // 樓層探測態：下滑縮回整修態
                        if isFloorCurveInCapsule {
                            if dy > threshold || predictedDY > threshold {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                    dismissFloorCurve()
                                }
                            }
                            resetLiftScaleDrag()
                            return
                        }

                        // 展開態上滑：進入樓層探測（只有一開始就是上滑方向才觸發）
                        if isCapsuleExpanded && lastGestureMode == -1 && (dy < -threshold || velocity < -threshold * 0.5) {
                            // 先觸發樓層探測（設 isFloorCurveInCapsule = true），再收縮
                            triggerFloorCurvePopup()
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                isCapsuleExpanded = false
                            }
                            resetLiftScaleDrag()
                            return
                        }

                        // 判斷展開/收縮：距離或速度，其中一個夠就觸發
                        let shouldExpand = !isCapsuleExpanded && (dy < -threshold || velocity < -threshold * 0.5)
                        let shouldCollapse = isCapsuleExpanded && (dy > threshold || velocity > threshold * 0.5)
                        let targetExpanded = shouldExpand ? true : (shouldCollapse ? false : isCapsuleExpanded)

                        // 計算鬆手時的高度，用於平滑過渡
                        let releasedHeight: CGFloat = {
                            if !isCapsuleExpanded {
                                return 44 + min(max(0, -dy), 120)
                            } else {
                                return 182 - min(max(0, dy), 120)
                            }
                        }()
                        if targetExpanded && !isCapsuleExpanded {
                            // 展開：高度 + offset + scale 一起動畫，用高 damping 避免 overshoot
                            capsuleSettleHeight = smoothDragHeight
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                                isCapsuleExpanded = true
                                orbOpacity = 0.5
                                capsuleSettleHeight = 182
                                capsuleDragOffsetY = 0
                                capsuleDragScale = 1.0
                            }
                            let workItem = DispatchWorkItem { capsuleSettleHeight = nil }
                            capsuleSettleWorkItem = workItem
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: workItem)
                            // 延遲計算，避免阻塞展開動畫
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                updateVisitStatus()
                                refreshETA()
                            }
                        } else if !targetExpanded && isCapsuleExpanded {
                            // 收縮：高度 + offset + scale 一起動畫
                            capsuleSettleHeight = releasedHeight
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                isCapsuleExpanded = false
                                orbOpacity = 1.0
                                capsuleOnRight = false
                                capsuleSettleHeight = 44
                                capsuleDragOffsetY = 0
                                capsuleDragScale = 1.0
                            }
                            let workItem = DispatchWorkItem { capsuleSettleHeight = nil }
                            capsuleSettleWorkItem = workItem
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: workItem)
                        } else {
                            // 不夠距離：用當前視覺高度做起點，慢慢回去
                            capsuleSettleHeight = smoothDragHeight
                            withAnimation(.timingCurve(0.25, 0.1, 0.25, 1.0, duration: 0.55)) {
                                capsuleSettleHeight = isCapsuleExpanded ? 182 : 44
                                capsuleDragOffsetY = 0
                                capsuleDragScale = 1.0
                            }
                            // 光效：重置
                            lightEffectProgress = 0
                            let workItem = DispatchWorkItem { capsuleSettleHeight = nil }
                            capsuleSettleWorkItem = workItem
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
                        }
                        return
                    }

                    // Default animation mode
                    // 樓層探測態：下滑縮回整修態
                    if isFloorCurveInCapsule {
                        if dy > threshold || predictedDY > threshold {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                dismissFloorCurve()
                            }
                        }
                        return
                    }

                    // 展開態上滑：進入樓層探測態
                    if isCapsuleExpanded && (dy < -threshold || predictedDY < -threshold) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            isCapsuleExpanded = false
                        }
                        triggerFloorCurvePopup()
                        return
                    }

                    let shouldExpand = (!isCapsuleExpanded) && (dy < -threshold || predictedDY < -threshold)
                    let shouldCollapse = isCapsuleExpanded && (dy > threshold || predictedDY > threshold)
                    let targetExpanded: Bool = shouldExpand ? true : (shouldCollapse ? false : isCapsuleExpanded)
                    let releasedHeight: CGFloat = {
                        if !isCapsuleExpanded {
                            return 44 + min(max(0, -dy), 138)
                        } else {
                            return 182 - min(max(0, dy), 138)
                        }
                    }()
                    capsuleSettleWorkItem?.cancel()
                    capsuleSettleWorkItem = nil
                    capsuleSettleHeight = releasedHeight
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        isCapsuleExpanded = targetExpanded
                        orbOpacity = targetExpanded ? 0.5 : 1.0
                        if !targetExpanded {
                            capsuleOnRight = false
                        }
                        capsuleSettleHeight = targetExpanded ? 182 : 44
                    }
                    let workItem = DispatchWorkItem {
                        capsuleSettleHeight = nil
                    }
                    capsuleSettleWorkItem = workItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: workItem)
                    if isCapsuleExpanded {
                        updateVisitStatus()
                        refreshETA()
                    }
                }
        )
        .onTapGesture {
            guard !isCapsuleExpanded, !capsuleDragState.active, capsuleSettleHeight == nil else { return }
            // 微微放大提示「這是可拖曳的」
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                capsuleDragScale = 1.08
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                    capsuleDragScale = 1.0
                }
            }
        }
        .onReceive(locationManager.$visits) { _ in
            if isCapsuleExpanded {
                updateVisitStatus()
            }
            // visits 載入後：重啟計時器 + 同步實時活動（冷啟動時確保恢復）
            refreshVisitAndTimersForForeground()
        }
        .onChange(of: showDepartedLabel) { _, _ in
            if isCapsuleExpanded {
                updateVisitStatus()
            }
        }
        .onChange(of: visitStatus) { oldStatus, newStatus in
            if newStatus == "已停留", oldStatus != "已停留" {
                sfxPlayer.playEnterStationary()
            } else if newStatus == "已開車", oldStatus != "已開車" {
                sfxPlayer.playEnterDriving()
            } else if newStatus == "已步行", oldStatus != "已步行" {
                sfxPlayer.playEnterDriving()  // 步行也用開車音效（移動狀態切換）
            } else if newStatus == "已騎車", oldStatus != "已騎車" {
                sfxPlayer.playEnterDriving()  // 騎車也用開車音效（移動狀態切換）
            }
            guard hasDeparted else {
                stopStationaryTimer()
                syncLiveActivity()
                return
            }
            if newStatus == "已停留", oldStatus != "已停留" {
                stationaryTrackingTrigger &+= 1
                northOverrideTrackingToken &+= 1
                startStationaryTimer()
            } else if newStatus != "已停留", oldStatus == "已停留" {
                stopStationaryTimer()
            }
            syncLiveActivity()
        }
        .onChange(of: visitSecondaryStatus) { oldStatus, newStatus in
            if newStatus == "已開車（未離場）", oldStatus != "已開車（未離場）" {
                sfxPlayer.playEnterDriving()
            }
        }
        .onChange(of: hasDeparted) { _, departed in
            if !departed {
                stopStationaryTimer()
            }
        }
        .onChange(of: isCapsuleExpanded) { _, expanded in
            if expanded {
                stopRandomInfoTimer()
            } else {
                if !isParkingMemoryExpanded {
                    startRandomInfoTimer()
                }
            }
        }
        .onChange(of: isParkingMemoryExpanded) { _, expanded in
            if expanded {
                stopRandomInfoTimer()
            } else if !isCapsuleExpanded {
                startRandomInfoTimer()
            }
        }
        .onChange(of: visitStatus) { _, _ in
            restartRandomInfoTimerIfNeeded()
        }
        .onChange(of: hasDeparted) { _, _ in
            restartRandomInfoTimerIfNeeded()
            syncLiveActivity()
        }
        .onChange(of: drivingETASeconds) { _, _ in
            syncLiveActivity()
        }
        .onChange(of: parkingFloorStore.lots) { _, _ in syncLiveActivity() }
        .onAppear {
            if !isCapsuleExpanded && !isParkingMemoryExpanded {
                startRandomInfoTimer()
            }
        }
    }

    private var effectiveOrbOpacity: Double {
        let showCapsuleOrbs = orbMasterEnabled && orbCapsule
        if !orbMasterEnabled { return 0 }
        if isParkingMemoryExpanded { return orbParkingMemory ? 0.5 : 0 }
        if isCapsuleExpanded { return orbExpanded ? 0.5 : 0 }
        return showCapsuleOrbs ? 1.0 : 0
    }

    /// 根據 orbColorPreset 返回三顆圓球嘅 hex 顏色
    private func orbPresetColors() -> [(hex: String, opacity: Double)] {
        switch orbColorPreset {
        case 1: // 動態橙：隨時速變化，越快越橙紅
            let speed = locationManager.speed  // m/s
            let kmh = max(0, speed * 3.6)
            // 低速(0-60): 橙色 FF8C00 → 中速(60-120): 深橙 FF6B00 → 高速(120+): 紅橙 FF4500
            let t = min(max((kmh - 30) / 90, 0), 1)  // 30kmh=0, 120kmh=1
            let hex: String
            if t < 0.5 {
                // FF8C00 → FF6B00
                let u = t * 2
                let r = 255, g = Int(140 - 33 * u), b = 0
                hex = String(format: "%02X%02X%02X", r, g, b)
            } else {
                // FF6B00 → FF4500
                let u = (t - 0.5) * 2
                let r = 255, g = Int(107 - 38 * u), b = 0
                hex = String(format: "%02X%02X%02X", r, g, b)
            }
            return [(hex, 0.35), ("5CAEB7", 0.3), ("0098FF", 0.3)]
        case 2: // #9BF783
            return [("9BF783", 0.3), ("5CAEB7", 0.3), ("0098FF", 0.3)]
        case 3: // #99E695
            return [("99E695", 0.3), ("5CAEB7", 0.3), ("0098FF", 0.3)]
        case 4: // #97D5AB
            return [("97D5AB", 0.3), ("5CAEB7", 0.3), ("0098FF", 0.3)]
        default: // 0 = 金黃色（預設）
            return [("BEBC3F", 0.3), ("5CAEB7", 0.3), ("0098FF", 0.3)]
        }
    }

    private var orbBackgroundColor: Color {
        let opacity = effectiveOrbOpacity
        if opacity <= 0 { return Color.black.opacity(0.92) }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        UIColor(Color.black.opacity(0.4)).getRed(&r, green: &g, blue: &b, alpha: nil)
        var rr = r, gg = g, bb = b
        let orbColors = orbPresetColors().map { (UIColor(hex: $0.hex), $0.opacity) }
        for (uc, baseOpacity) in orbColors {
            var or: CGFloat = 0, og: CGFloat = 0, ob: CGFloat = 0
            uc.getRed(&or, green: &og, blue: &ob, alpha: nil)
            let a = baseOpacity * opacity
            rr += or * a; gg += og * a; bb += ob * a
        }
        rr = min(rr, 1); gg = min(gg, 1); bb = min(bb, 1)
        var gr: CGFloat = 0, gg2: CGFloat = 0, gb: CGFloat = 0
        UIColor(Color.white).getRed(&gr, green: &gg2, blue: &gb, alpha: nil)
        rr += (gr - rr) * 0.2; gg += (gg2 - gg) * 0.2; bb += (gb - bb) * 0.2
        return Color(.sRGB, red: min(rr, 1), green: min(gg, 1), blue: min(bb, 1), opacity: 1)
    }

    private func adaptiveTextColor(opacity: Double = 1.0) -> Color {
        let color: Color = colorScheme == .dark ? .white : .black
        return opacity < 1.0 ? color.opacity(opacity) : color
    }

    /// 描邊/點綴顏色（黑武士模式用金色，否則用白色）
    private func accentStrokeColor(opacity: Double = 0.6) -> Color {
        if darkKnightMode {
            return Color(hex: "FFC46D").opacity(opacity)
        }
        return Color.white.opacity(opacity)
    }

    /// 按鈕背景透明度（黑武士模式更暗）
    private func buttonBgOpacity(isActive: Bool) -> Double {
        let base = isActive
            ? (colorScheme == .dark ? 0.68 : 0.78)
            : (colorScheme == .dark ? 0.32 : 0.26)
        return darkKnightMode ? base * 0.5 : base
    }

    /// 黑武士模式半透明黑色覆蓋層
    private func darkKnightOverlay() -> some View {
        RoundedRectangle(cornerRadius: 34)
            .fill(Color.black.opacity(darkKnightMode ? 0.35 : 0))
            .allowsHitTesting(false)
    }

    /// 更新 TabBar 外觀
    private func updateTabBarAppearance() {
        let appearance = UITabBarAppearance()
        if darkKnightMode {
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(red: 1.0, green: 0.77, blue: 0.43, alpha: 0.15) // 金色半透明
        } else {
            appearance.configureWithDefaultBackground()
        }
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    @ViewBuilder
    private var orbBackground: some View {
        if effectiveOrbOpacity > 0 {
            let colors = orbPresetColors()
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let t = animationClock.elapsed
                let orbScale = sqrt(h / 44.0)

                ZStack {
                    Color.black.opacity(0.2)

                    Circle()
                        .fill(Color(hex: colors[0].hex).opacity(colors[0].opacity * effectiveOrbOpacity))
                        .blur(radius: 20)
                        .frame(width: 200 * orbScale, height: 200 * orbScale)
                        .offset(
                            x: w * 0.5 + CGFloat(sin(t * 0.5)) * w * 0.35 - 100 * orbScale,
                            y: h * 0.5 + CGFloat(cos(t * 0.4)) * h * 0.35 - 100 * orbScale
                        )
                    Circle()
                        .fill(Color(hex: colors[1].hex).opacity(colors[1].opacity * effectiveOrbOpacity))
                        .blur(radius: 20)
                        .frame(width: 220 * orbScale, height: 220 * orbScale)
                        .offset(
                            x: w * 0.5 + CGFloat(sin(t * 0.4 + 2)) * w * 0.3 - 110 * orbScale,
                            y: h * 0.5 + CGFloat(cos(t * 0.35 + 2)) * h * 0.3 - 110 * orbScale
                        )
                    Circle()
                        .fill(Color(hex: colors[2].hex).opacity(colors[2].opacity * effectiveOrbOpacity))
                        .blur(radius: 20)
                        .frame(width: 180 * orbScale, height: 180 * orbScale)
                        .offset(
                            x: w * 0.5 + CGFloat(sin(t * 0.6 + 4)) * w * 0.33 - 90 * orbScale,
                            y: h * 0.5 + CGFloat(cos(t * 0.45 + 4)) * h * 0.33 - 90 * orbScale
                        )
                }
            }
            .clipShape(.rect(cornerRadius: 34))
        }
    }

    private var expandedContent: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 4) {
                        Text("\(distanceLabel):")
                            .font(.body.bold())
                            .foregroundStyle(adaptiveTextColor(opacity: 0.8))
                            .contentTransition(.opacity)
                            .animation(capsuleDragState.active ? nil : .easeInOut(duration: 0.3), value: distanceLabel)
                        Text(drivingDistanceText ?? "--")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(adaptiveTextColor())
                            .contentTransition(.numericText())
                            .animation(capsuleDragState.active ? nil : .easeInOut(duration: 0.3), value: drivingDistanceText)
                            .monospacedDigit()
                            .blur(radius: capsuleDragState.active ? 6 : 0)
                            .animation(.easeInOut(duration: 0.25), value: capsuleDragState.active)
                    }
                    HStack(spacing: 4) {
                        Text("\(compactStatusTitle):")
                            .font(.body.bold())
                            .foregroundStyle(adaptiveTextColor(opacity: 0.8))
                        Text(frozenCompactStatus ?? (hasDeparted ? (visitStatus == "已停留" ? formatStationaryDuration() : formatDepartureDuration()) : formatParkingElapsed()))
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(adaptiveTextColor())
                            .contentTransition(.numericText())
                            .animation(capsuleDragState.active ? nil : .easeInOut(duration: 0.15), value: hasDeparted ? (visitStatus == "已停留" ? stationaryElapsed : departureElapsed) : parkingElapsed)
                            .monospacedDigit()
                            .blur(radius: capsuleDragState.active ? 6 : 0)
                            .animation(.easeInOut(duration: 0.25), value: capsuleDragState.active)
                    }
                    if let secondary = visitSecondaryStatus {
                        Text(secondary)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(adaptiveTextColor(opacity: 0.7))
                            .transition(.opacity)
                            .id(secondary)
                    }
                }
                .animation(.easeInOut(duration: 0.22), value: visitSecondaryStatus)

                Spacer()

                VStack(spacing: 8) {
                    Button(action: {
                        guard !isFloorCurveInCapsule else { return }
                        let opening = !isParkingMemoryExpanded
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            isParkingMemoryExpanded.toggle()
                            orbOpacity = isParkingMemoryExpanded ? 0.5 : 1.0
                            if !isParkingMemoryExpanded {
                                capsuleOnRight = false
                            }
                        }
                        if opening && hasDeparted {
                            hasDeparted = false
                            manualDeparted = false
                            parkingEntryTime = Date()
                            parkingStartTime = Date()
                            lastKnownArrivalDate = Date()
                            capsuleDuration = 0
                            parkingElapsed = 0
                            timerRunning = false
                            startPersistentTimer()
                        }
                    }) {
                        Label((isNonAutomotiveArrival && !hasParkingSpotData) ? String(localized: "逗留記憶") : String(localized: "泊車記憶"), systemImage: (isNonAutomotiveArrival && !hasParkingSpotData) ? "mappin.and.ellipse" : "car.fill")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.white)
                            .frame(width: 126, height: 54)
                            .glassEffect(.regular, in: .capsule)
                            .background(
                                (Color(hex: parkingTimerColorHex) ?? Color(hex: "46ADB8")).opacity(
                                    buttonBgOpacity(isActive: timerRunning)
                                )
                                    .clipShape(Capsule())
                                    .allowsHitTesting(false)
                            )
                    }
                    .opacity(timerRunning ? 1.0 : 0.7)

                    Button(action: {
                        guard !isFloorCurveInCapsule else { return }
                        if showingRoute {
                            withAnimation {
                                showingRoute = false
                                meterRouteTarget = nil
                                meterDirections?.cancel()
                                meterDirections = nil
                                routePolyline = nil
                                routeAnimationPolyline = nil
                            }
                            routePriorityToken = nil
                            routePriorityAnchor = nil
                            routeOverlayToken = nil
                            routeOverlayAnimationToken = nil
                            isRerouting = false
                            lastRerouteRequestAt = nil
                            offRouteStrikeCount = 0
                        } else {
                            guard let destination = destinationManager.selectedDestination else {
                                showNoDestinationAlert = true
                                return
                            }
                            guard let currentLocation = locationManager.lastLocation else { return }
                            let routeToken = UUID()
                            routePriorityToken = routeToken
                            routePriorityAnchor = currentLocation.coordinate
                            let overlayToken = UUID()
                            routeOverlayToken = overlayToken
                            routeOverlayAnimationToken = overlayToken
                            if !showMap && !showSatellite {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    showMap = true
                                }
                            }
                            let request = MKDirections.Request()
                            request.source = MKMapItem(placemark: MKPlacemark(coordinate: currentLocation.coordinate.wgs84ToGCJ02))
                            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.coordinate.wgs84ToGCJ02))
                            request.transportType = .automobile
                            request.requestsAlternateRoutes = false
                            let directions = MKDirections(request: request)
                            directions.calculate { response, error in
                                guard let route = response?.routes.first, error == nil else {
                                    DispatchQueue.main.async {
                                        guard meterRouteTarget == nil, routePriorityToken == routeToken else { return }
                                        routePriorityToken = nil
                                        routePriorityAnchor = nil
                                        routeOverlayToken = nil
                                        routeOverlayAnimationToken = nil
                                    }
                                    return
                                }
                                DispatchQueue.main.async {
                                    guard meterRouteTarget == nil, routePriorityToken == routeToken else { return }
                                    withAnimation {
                                        showingRoute = true
                                        routePolyline = route.polyline
                                        routeAnimationPolyline = simplifiedRoutePolyline(route.polyline, maxPoints: 220)
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                                        guard showingRoute, routePriorityToken == routeToken else { return }
                                        routePriorityToken = nil
                                        routePriorityAnchor = nil
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) {
                                        guard showingRoute, routeOverlayToken == overlayToken else { return }
                                        routeOverlayAnimationToken = nil
                                        routeAnimationPolyline = nil
                                    }
                                }
                            }
                        }
                    }) {
                        Label(String(localized: "最優路線"), systemImage: "map")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.white)
                            .frame(width: 126, height: 54)
                            .glassEffect(.regular, in: .capsule)
                            .background(
                                (Color(hex: bestRouteColorHex) ?? Color(hex: "BCBA1E")).opacity(
                                    buttonBgOpacity(isActive: showingRoute)
                                )
                                    .clipShape(Capsule())
                                    .allowsHitTesting(false)
                            )
                    }
                    .opacity(showingRoute ? 1.0 : 0.7)
                    .alert(String(localized: "請選擇目的地"), isPresented: $showNoDestinationAlert) {
                        Button(String(localized: "確定"), role: .cancel) {}
                    } message: {
                        Text(String(localized: "請先選擇目的地，再計算最優路線"))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            Spacer(minLength: 0)

            HStack {
                HStack(spacing: 4) {
                    Text("\(Int(locationManager.smoothedSpeed))")
                        .font(.body.bold())
                        .foregroundStyle(adaptiveTextColor(opacity: 0.6))
                        .contentTransition(.numericText())
                        .animation(capsuleDragState.active ? nil : .easeInOut(duration: 0.3), value: Int(locationManager.smoothedSpeed))
                        .monospacedDigit()
                        .blur(radius: capsuleDragState.active ? 6 : 0)
                        .animation(.easeInOut(duration: 0.25), value: capsuleDragState.active)
                    Text("km/h")
                        .font(.body.bold())
                        .foregroundStyle(adaptiveTextColor(opacity: 0.6))
                }
                Spacer()
                Text(locationManager.currentAddress)
                    .font(.body.bold())
                    .foregroundStyle(adaptiveTextColor())
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.15), value: locationManager.currentAddress)
                Spacer()
                Text(etaText ?? "--")
                    .font(.body.bold())
                    .foregroundStyle(adaptiveTextColor(opacity: 0.6))
                    .contentTransition(.numericText())
                    .animation(capsuleDragState.active ? nil : .easeInOut(duration: 0.15), value: etaText ?? "--")
                    .monospacedDigit()
                    .frame(minWidth: 60, alignment: .trailing)
                    .blur(radius: capsuleDragState.active ? 6 : 0)
                    .animation(.easeInOut(duration: 0.25), value: capsuleDragState.active)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    private var statusDurationText: String {
        if hasDeparted {
            let interval = Date().timeIntervalSince(parkingStartTime)
            let hours = Int(interval / 3600)
            let mins = Int(interval.truncatingRemainder(dividingBy: 3600) / 60)
            let secs = Int(interval.truncatingRemainder(dividingBy: 60))
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        }
        guard let lastVisit = locationManager.visits.first else { return "--" }
        let date: Date
        if let departure = lastVisit.departureDate {
            date = departure
        } else {
            date = lastVisit.arrivalDate
        }
        let interval = Date().timeIntervalSince(date)
        let hours = Int(interval / 3600)
        let mins = Int(interval.truncatingRemainder(dividingBy: 3600) / 60)
        let secs = Int(interval.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d:%02d", hours, mins, secs)
    }

    private var parkingMemoryContent: some View {
        VStack(spacing: 0) {
            if isLandscape {
                parkingMemoryLandscape
            } else {
                parkingMemoryPortrait
            }
        }
    }

    // MARK: - Parking Memory Landscape
    private var parkingMemoryLandscape: some View {
        VStack(spacing: 10) {
            // 顶部：返回 + 泊車記憶 + 入場時間 + 加减按钮（横跨全宽）
            parkingMemoryLandscapeHeader
            // 下方：左相机 + 右按钮
            HStack(alignment: .bottom, spacing: 20) {
                // 左边：相机预览
                VStack(spacing: 0) {
                    cameraSection
                }
                .padding(.bottom, 20)
                .frame(width: isLandscape ? 304 : 370)
                .frame(maxHeight: .infinity, alignment: .bottom)
                // 右边：离场 + 入场计时
                parkingMemoryLandscapeButtons
            }
        }
        .padding(.horizontal, 20)
    }

    private var parkingMemoryLandscapeHeader: some View {
        HStack {
            parkingBackButton
            Text((isNonAutomotiveArrival && !hasParkingSpotData) ? String(localized: "逗留記憶") : String(localized: "泊車記憶"))
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(adaptiveTextColor())
            Spacer()
            if let text = timeAdjustText {
                Text(text)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(adaptiveTextColor(opacity: 0.8))
                    .transition(.opacity)
            }
            HStack(spacing: 4) {
                Text(String(localized: "入場時間"))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(adaptiveTextColor(opacity: 0.6))
                parkingEntryTimeDisplay(fontSize: 12)
            }
            parkingTimeAdjustButtons(buttonSize: 28, iconSize: 14)
        }
        .padding(.top, 18)
    }

    private var parkingMemoryLandscapeButtons: some View {
        VStack(spacing: 16) {
            // 離場 button
            parkingDepartureButton(width: 161, height: 70, countdownSize: 40, labelSize: 22)
            // 入场计时
            parkingTimerOrb(width: 161, height: 70, orbBaseSize: 100, titleSize: 16, elapsedSize: 32, labelWidth: 28, labelSize: 11, onLongPress: {
                editSpotNumber = llmSpotNumber ?? ""
                editAreaCode = llmAreaCode ?? ""
                editFloorText = llmFloorText ?? ""
                showSpotEditor = true
            })
        }
        .padding(.bottom, 20)
        .frame(width: isLandscape ? 161 : 190)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    // MARK: - Parking Memory Portrait
    private var parkingMemoryPortrait: some View {
        Group {
            // Back button + Title
            HStack {
                parkingBackButton
                Text((isNonAutomotiveArrival && !hasParkingSpotData) ? String(localized: "逗留記憶") : String(localized: "泊車記憶"))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(adaptiveTextColor())
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // Entry time + adjustment
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(String(localized: "入場時間"))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(adaptiveTextColor(opacity: 0.6))
                        if let text = timeAdjustText {
                            Text(text)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(adaptiveTextColor(opacity: 0.8))
                                .transition(.opacity)
                        }
                    }
                    parkingEntryTimeDisplay(fontSize: 18)
                }
                Spacer()
                parkingTimeAdjustButtons(buttonSize: 32, iconSize: 16)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // Camera preview + photo button + thumbnails
            cameraSection
                .padding(.top, 14)

            Spacer()
                .frame(height: 20)

            // Bottom: 離場 button + entry timer
            HStack(spacing: 14) {
                parkingDepartureButton(width: 161, height: 87, countdownSize: 48, labelSize: 24)
                parkingTimerOrb(width: 161, height: 87, orbBaseSize: 120, titleSize: 18, elapsedSize: 36, labelWidth: 32, labelSize: 13, onLongPress: { showRecognitionLogicAlert = true })
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Parking Memory Shared Components
    private var parkingBackButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                isParkingMemoryExpanded = false
                orbOpacity = 1.0
                capsuleOnRight = false
                showingExpandedPhotos = false
                selectedPhotoIndex = nil
                tiltAngleX = [:]
                tiltAngleY = [:]
                deletingPhotoID = nil
                deletingIndex = nil
                deletingImage = nil
                parkingRecognizedDisplayText = nil
                hasConfirmedFloorThisSession = false
                showFloorConfirm = false
                recognizedFloorToConfirm = nil
                pendingOriginalFloorIndex = nil
                pendingFloorText = nil
                pendingFloorIndex = nil
                llmPollTimer?.invalidate()
                parkingInfoSwitchTimer?.invalidate()
            }
        }) {
            Image(systemName: "chevron.left.circle.fill")
                .font(.system(size: isLandscape ? 28 : 32))
                .foregroundStyle(adaptiveTextColor(opacity: 0.8))
        }
    }

    @ViewBuilder
    private func parkingEntryTimeDisplay(fontSize: CGFloat) -> some View {
        let cal = Calendar.current
        let d = cal.component(.day, from: parkingEntryTime)
        let m = cal.component(.month, from: parkingEntryTime)
        let y = cal.component(.year, from: parkingEntryTime)
        let hr = cal.component(.hour, from: parkingEntryTime)
        let mi = cal.component(.minute, from: parkingEntryTime)
        Text(String(format: "%02d/%02d/%04d %02d:%02d", d, m, y, hr, mi))
            .font(.system(size: fontSize, weight: .bold))
            .foregroundStyle(adaptiveTextColor())
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(.easeInOut(duration: 0.15), value: parkingEntryTime)
    }

    @ViewBuilder
    private func parkingTimeAdjustButtons(buttonSize: CGFloat, iconSize: CGFloat) -> some View {
        HStack(spacing: isLandscape ? 6 : 8) {
            Button(action: {
                timeAdjustAccumulated -= 1
                withAnimation(.easeInOut(duration: 0.2)) {
                    parkingEntryTime = parkingEntryTime.addingTimeInterval(-60)
                }
                showAdjustText()
            }) {
                Image(systemName: "minus")
                    .font(.system(size: iconSize, weight: .bold))
                    .foregroundStyle(adaptiveTextColor())
                    .frame(width: buttonSize, height: buttonSize)
                    .glassEffect(.regular, in: .rect(cornerRadius: 8))
            }
            Button(action: {
                timeAdjustAccumulated += 1
                withAnimation(.easeInOut(duration: 0.2)) {
                    parkingEntryTime = parkingEntryTime.addingTimeInterval(60)
                }
                showAdjustText()
            }) {
                Image(systemName: "plus")
                    .font(.system(size: iconSize, weight: .bold))
                    .foregroundStyle(adaptiveTextColor())
                    .frame(width: buttonSize, height: buttonSize)
                    .glassEffect(.regular, in: .rect(cornerRadius: 8))
            }
        }
    }

    @ViewBuilder
    private func parkingDepartureButton(width: CGFloat, height: CGFloat, countdownSize: CGFloat, labelSize: CGFloat) -> some View {
        Button(action: {
            startDepartureCountdown()
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 25)
                    .fill(Color(hex: "D2251F"))
                    .frame(width: width, height: height)
                    .overlay(
                        RoundedRectangle(cornerRadius: 25)
                            .stroke(Color.white.opacity(0.6), lineWidth: 4)
                    )
                if let countdown = parkingCountdown {
                    Text("\(countdown)")
                        .font(.system(size: countdownSize, weight: .bold))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.15), value: parkingCountdown)
                } else if parkingDeparted {
                    AnimatedCheckmarkView()
                } else {
                    Text(String(localized: "離場"))
                        .font(.system(size: labelSize, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
    }

    @ViewBuilder
    private func parkingTimerOrb(width: CGFloat, height: CGFloat, orbBaseSize: CGFloat, titleSize: CGFloat, elapsedSize: CGFloat, labelWidth: CGFloat, labelSize: CGFloat, onLongPress: @escaping () -> Void) -> some View {
        ZStack {
            parkingOrbBackground(width: width, height: height, orbBaseSize: orbBaseSize)
            parkingTimerOverlay(titleSize: titleSize, elapsedSize: elapsedSize, labelWidth: labelWidth, labelSize: labelSize, onLongPress: onLongPress)
        }
    }

    private func parkingOrbBackground(width: CGFloat, height: CGFloat, orbBaseSize: CGFloat) -> some View {
        parkingOrbCanvas(width: width, height: height, orbBaseSize: orbBaseSize)
            .frame(width: width, height: height)
            .clipShape(.rect(cornerRadius: 25))
            .overlay(
                RoundedRectangle(cornerRadius: 25)
                    .fill(Color.black.opacity(0.18))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 25)
                    .stroke(Color.white.opacity(0.6), lineWidth: 4)
            )
    }

    private func parkingOrbCanvas(width: CGFloat, height: CGFloat, orbBaseSize: CGFloat) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            parkingOrbCircles(w: w, h: h, orbBaseSize: orbBaseSize)
        }
    }

    private func parkingOrbCircles(w: CGFloat, h: CGFloat, orbBaseSize: CGFloat) -> some View {
        let orbElapsed = orbBoostElapsedOffset > 0 ? (animationClock.elapsed - orbBoostElapsedOffset) : animationClock.elapsed
        let t = orbElapsed * 0.3 * parkingOrbBoost
        let isBoosted = !isOrbRecognizingBoost && parkingOrbBoost > 1.01
        let boostFactor = min(max((parkingOrbBoost - 1.0) / 1.0, 0), 1)
        let threeColorOp = isOrbRecognizingBoost ? 0.5 : (isBoosted ? 0.5 * (1 - boostFactor) : 0.5)
        let sixColorOp = isOrbRecognizingBoost ? 0 : (isBoosted ? 0.5 * boostFactor : 0)
        let baseColor = Color(hex: parkingTimerColorHex) ?? Color(hex: "46ADB8")

        return ZStack {
            parkingSingleOrb(color: baseColor, opacity: threeColorOp, size: orbBaseSize, w: w, h: h, t: t, freqX: 0.5, freqY: 0.4, ampX: 0.35, ampY: 0.35, phaseX: 0, phaseY: 0)
            parkingSingleOrb(color: Color(hex: "0098FF"), opacity: threeColorOp, size: orbBaseSize + 10, w: w, h: h, t: t, freqX: 0.4, freqY: 0.35, ampX: 0.3, ampY: 0.3, phaseX: 2, phaseY: 2)
            parkingSingleOrb(color: Color(hex: "BCBAE1"), opacity: threeColorOp, size: orbBaseSize - 10, w: w, h: h, t: t, freqX: 0.6, freqY: 0.45, ampX: 0.33, ampY: 0.33, phaseX: 4, phaseY: 4)
            boostOrbs(w: w, h: h, t: t, isBoosted: isBoosted, orbSize: orbBaseSize, sixColorOpacity: sixColorOp)
        }
    }

    private func parkingSingleOrb(color: Color, opacity: Double, size: CGFloat, w: CGFloat, h: CGFloat, t: Double, freqX: Double, freqY: Double, ampX: Double, ampY: Double, phaseX: Double, phaseY: Double) -> some View {
        Circle()
            .fill(color.opacity(opacity))
            .blur(radius: 16)
            .frame(width: size, height: size)
            .offset(
                x: w * 0.5 + CGFloat(sin(t * freqX + phaseX)) * w * ampX - size / 2,
                y: h * 0.5 + CGFloat(cos(t * freqY + phaseY)) * h * ampY - size / 2
            )
    }

    @ViewBuilder
    private func parkingTimerOverlay(titleSize: CGFloat, elapsedSize: CGFloat, labelWidth: CGFloat, labelSize: CGFloat, onLongPress: @escaping () -> Void) -> some View {
        VStack(spacing: 2) {
            let isLingering = isNonAutomotiveArrival && !hasParkingSpotData
            Text(isLingering ? String(localized: "計時") : (parkingInfoDisplayMode ? String(localized: "車位資訊") : String(localized: "入場計時")))
                .font(.system(size: titleSize, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, isLandscape ? 28 : 18)
                .id("parkingTitle")
            if !isLingering && parkingInfoDisplayMode {
                let session = parkingFloorStore.currentSession
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(String(localized: "車位")).frame(width: labelWidth, alignment: .trailing)
                        Text(session?.spotNumber ?? "-")
                    }
                    HStack(spacing: 4) {
                        Text(String(localized: "區域")).frame(width: labelWidth, alignment: .trailing)
                        Text(session?.areaCode ?? "-")
                    }
                    HStack(spacing: 4) {
                        Text(String(localized: "樓層")).frame(width: labelWidth, alignment: .trailing)
                        Text(session?.floorDisplay ?? "-")
                    }
                }
                .font(.system(size: labelSize, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
            } else {
                Text(formatParkingElapsed())
                    .font(.system(size: elapsedSize, weight: .bold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.15), value: parkingElapsed)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: parkingInfoDisplayMode)
        .animation(.easeInOut(duration: 0.3), value: parkingFloorStore.lots)
        .onTapGesture {
            guard !(isNonAutomotiveArrival && !hasParkingSpotData) else { return }
            withAnimation(.easeInOut(duration: 0.5)) {
                parkingInfoDisplayMode.toggle()
            }
            resetParkingInfoSwitchTimer()
        }
        .onLongPressGesture { onLongPress() }
    }

    private func formatParkingElapsed() -> String {
        let interval = parkingElapsed
        let hours = Int(interval / 3600)
        let mins = Int(interval.truncatingRemainder(dividingBy: 3600) / 60)
        let secs = Int(interval.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d:%02d", hours, mins, secs)
    }

    private func formatCapsuleDuration() -> String {
        let interval = capsuleDuration
        let hours = Int(interval / 3600)
        let mins = Int(interval.truncatingRemainder(dividingBy: 3600) / 60)
        let secs = Int(interval.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d:%02d", hours, mins, secs)
    }

    private func formatDepartureDuration() -> String {
        let interval = departureElapsed
        let hours = Int(interval / 3600)
        let mins = Int(interval.truncatingRemainder(dividingBy: 3600) / 60)
        let secs = Int(interval.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d:%02d", hours, mins, secs)
    }

    private func formatStationaryDuration() -> String {
        let interval = stationaryElapsed
        let hours = Int(interval / 3600)
        let mins = Int(interval.truncatingRemainder(dividingBy: 3600) / 60)
        let secs = Int(interval.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d:%02d", hours, mins, secs)
    }

    private func formatCompactETA(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds / 60)
        if mins < 60 {
            return "\(mins) mins"
        }
        let hrs = mins / 60
        let remainMins = mins % 60
        return remainMins > 0 ? "\(hrs)h\(remainMins)m" : "\(hrs)h"
    }

    private var compactModeShowStatus: Bool {
        if !hasDeparted { return true }
        return visitStatus == "已停留"
    }

    private var compactStatusTitle: String {
        if !hasDeparted {
            // 有車位資訊時一律顯示「已泊車」
            if hasParkingSpotData { return String(localized: "已泊車") }
            if isNonAutomotiveArrival { return String(localized: "已逗留") }
            return String(localized: "已泊車")
        }
        if visitStatus == "已停留" { return String(localized: "已停留") }
        if visitStatus == "已開車" { return String(localized: "已開車") }
        if visitStatus == "已步行" { return String(localized: "已步行") }
        if visitStatus == "已騎車" { return String(localized: "已騎車") }
        if visitStatus == "已開車（未離場）" { return String(localized: "已開車（未離場）") }
        return visitStatus
    }

    private var compactStatusDuration: String {
        if !hasDeparted { return formatParkingElapsed() }
        if visitStatus == "已停留" { return formatStationaryDuration() }
        if hasDeparted { return formatDepartureDuration() }
        return formatCapsuleDuration()
    }

    private var compactStatusTickValue: TimeInterval {
        if !hasDeparted { return parkingElapsed }
        if visitStatus == "已停留" { return stationaryElapsed }
        if hasDeparted { return departureElapsed }
        return capsuleDuration
    }

    private func distanceFromRoute(location: CLLocation, polyline: MKPolyline) -> CLLocationDistance {
        let p = MKMapPoint(location.coordinate)
        let points = polyline.points()
        guard polyline.pointCount >= 2 else { return .greatestFiniteMagnitude }
        var best = CLLocationDistance.greatestFiniteMagnitude
        for i in 0..<(polyline.pointCount - 1) {
            let a = points[i]
            let b = points[i + 1]
            let abx = b.x - a.x
            let aby = b.y - a.y
            let apx = p.x - a.x
            let apy = p.y - a.y
            let ab2 = abx * abx + aby * aby
            let t = ab2 > 0 ? max(0, min(1, (apx * abx + apy * aby) / ab2)) : 0
            let proj = MKMapPoint(x: a.x + abx * t, y: a.y + aby * t)
            let d = p.distance(to: proj)
            if d < best { best = d }
        }
        return best
    }

    private func simplifiedRoutePolyline(_ polyline: MKPolyline, maxPoints: Int) -> MKPolyline {
        let count = polyline.pointCount
        guard count > maxPoints, maxPoints >= 2 else { return polyline }
        let pts = polyline.points()
        var mp: [MKMapPoint] = []
        mp.reserveCapacity(count)
        for i in 0..<count {
            mp.append(pts[i])
        }
        var cumulative: [Double] = Array(repeating: 0, count: count)
        if count > 1 {
            for i in 1..<count {
                cumulative[i] = cumulative[i - 1] + mp[i - 1].distance(to: mp[i])
            }
        }
        let total = cumulative.last ?? 0
        if total <= 0 { return polyline }

        let targetCount = maxPoints
        let step = total / Double(targetCount - 1)
        var sampled: [MKMapPoint] = []
        sampled.reserveCapacity(targetCount)
        sampled.append(mp[0])

        func pointAt(_ dist: Double) -> MKMapPoint {
            var lo = 0
            var hi = cumulative.count - 1
            while lo < hi {
                let mid = (lo + hi) / 2
                if cumulative[mid] < dist {
                    lo = mid + 1
                } else {
                    hi = mid
                }
            }
            let idx = lo
            if idx <= 0 { return mp[0] }
            if idx >= mp.count { return mp.last ?? mp[0] }
            let prev = idx - 1
            let prevLen = cumulative[prev]
            let segLen = max(0.000001, cumulative[idx] - prevLen)
            let t = max(0, min(1, (dist - prevLen) / segLen))
            let a = mp[prev]
            let b = mp[idx]
            return MKMapPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }

        for i in 1..<(targetCount - 1) {
            sampled.append(pointAt(Double(i) * step))
        }
        sampled.append(mp[count - 1])

        return MKPolyline(points: sampled, count: sampled.count)
    }

    private func reroute(from coordinate: CLLocationCoordinate2D) {
        if let meter = meterRouteTarget {
            lastRerouteRequestAt = Date()
            startNavigationToMeter(meter)
            return
        }
        guard let destination = destinationManager.selectedDestination else { return }
        isRerouting = true
        lastRerouteRequestAt = Date()
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: coordinate.wgs84ToGCJ02))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.coordinate.wgs84ToGCJ02))
        request.transportType = .automobile
        request.requestsAlternateRoutes = false
        let directions = MKDirections(request: request)
        directions.calculate { response, error in
            DispatchQueue.main.async {
                defer { isRerouting = false }
                guard meterRouteTarget == nil else { return }
                guard let route = response?.routes.first, error == nil else { return }
                routeOverlayToken = UUID()
                routeOverlayAnimationToken = nil
                withAnimation(.easeInOut(duration: 0.2)) {
                    routePolyline = route.polyline
                    routeAnimationPolyline = nil
                    showingRoute = true
                }
            }
        }
    }

    private static let appGroupDefaults = UserDefaults(suiteName: "group.com.gorilla.translate")

    private func saveParkingState() {
        let d = Self.appGroupDefaults ?? .standard
        d.set(parkingStartTime, forKey: "parkingStartTime")
        d.set(hasDeparted, forKey: "hasDeparted")
        d.set(manualDeparted, forKey: "manualDeparted")
        d.set(departureTime, forKey: "parkingDepartureTime")
        d.set(timerRunning, forKey: "timerRunning")
        d.set(lastKnownArrivalDate, forKey: "lastKnownArrivalDate")
        d.synchronize()
        WidgetCenter.shared.reloadTimelines(ofKind: "ParkingTimerWidget")
    }

    // MARK: - 專注模式

    private var globeToggleIcon: String {
        if showSatellite { return "binoculars.fill" }       // 衛星3D
        if showMap { return "map.fill" }                     // 地圖
        return "map"                                         // 光球
    }

    private var focusActive: Bool { focusMode != nil }

    /// 平衡／極致：切走資訊彈出同 ETA／路線網絡請求
    private var focusCutsInfoAndETA: Bool {
        focusMode == .balanced || focusMode == .extreme
    }

    /// 極致：暫停泊車／停留／開車偵測同靈動島更新
    private var focusCutsDetection: Bool { focusMode == .extreme }

    private func enterFocusMode(_ level: FocusModeLevel, frameRate: FocusFrameRate) {
        let wasActive = focusMode != nil
        focusFrameRate = frameRate
        animationClock.setFrameRate(Double(frameRate.rawValue))
        withAnimation(.easeInOut(duration: 0.25)) {
            focusMode = level
        }
        if level == .balanced || level == .extreme {
            stopRandomInfoTimer()
        } else if wasActive {
            restartRandomInfoTimerIfNeeded()
        }
        // 極致專注模式：自動開啟黑武士模式
        if level == .extreme && !darkKnightMode {
            darkKnightMode = true
            darkKnightActivatedByFocus = true
            updateTabBarAppearance()
        }
    }

    private func exitFocusMode() {
        // 如果黑武士模式係由極致專注自動開啟嘅，一併退出
        if darkKnightActivatedByFocus {
            darkKnightMode = false
            darkKnightActivatedByFocus = false
            updateTabBarAppearance()
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            focusMode = nil
        }
        animationClock.setFrameRate(60)
        restartRandomInfoTimerIfNeeded()
        refreshVisitAndTimersForForeground()
        syncLiveActivity(forceRefresh: true)
    }

    /// Restart the stationary timer + departure elapsed timer + sync Live Activity.
    /// Called after cold-launch when `manualDeparted` and visit data hasn't changed.
    private func ensureStationaryTimerRunning() {
        // Start stationary timer (counts up since departure)
        if stationaryTimer == nil, let dep = departureTime {
            let elapsed = Date().timeIntervalSince(dep)
            stationaryElapsed = elapsed
            stationaryStartTime = dep
            let timer = Timer(timeInterval: 1.0, repeats: true) { _ in
                let e = Date().timeIntervalSince(dep)
                DispatchQueue.main.async { stationaryElapsed = e }
            }
            stationaryTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        // Start departure elapsed timer (for the header label)
        if departureElapsedTimer == nil, let dep = departureTime {
            departureElapsed = Date().timeIntervalSince(dep)
            let timer = Timer(timeInterval: 1.0, repeats: true) { _ in
                guard hasDeparted, let d = departureTime else { return }
                let e = Date().timeIntervalSince(d)
                DispatchQueue.main.async { departureElapsed = e }
            }
            departureElapsedTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        syncLiveActivity()
    }

    private func refreshVisitAndTimersForForeground() {
        updateVisitStatus()

        // visits 尚未載入時不重置狀態（防止冷啟動計時器被清空）
        guard locationManager.hasLoadedVisits else { return }

        guard let lastVisit = locationManager.visits.first else {
            // If user manually departed, don't reset — stay dormant
            if manualDeparted {
                ensureStationaryTimerRunning()
                return
            }
            hasDeparted = false
            timerRunning = false
            parkingTimer?.invalidate()
            parkingTimer = nil
            departureElapsedTimer?.invalidate()
            departureElapsedTimer = nil
            departureTime = nil
            departureElapsed = 0
            GorillaActivityManager.shared.end()
            return
        }

        if lastVisit.departureDate == nil {
            // Guard: if user manually departed, don't restart parking memory
            // for the SAME visit. Only a genuinely new visit event resets this.
            if manualDeparted {
                // Same visit (same arrival) → stay dormant
                if lastVisit.arrivalDate == parkingStartTime {
                    ensureStationaryTimerRunning()
                    return
                }
                // Different arrival → new visit event, reset manual flag
                manualDeparted = false
                saveParkingState()
            }

            hasDeparted = false
            departureElapsedTimer?.invalidate()
            departureElapsedTimer = nil
            departureTime = nil
            departureElapsed = 0

            parkingEntryTime = lastVisit.arrivalDate
            parkingStartTime = lastVisit.arrivalDate
            lastKnownArrivalDate = lastVisit.arrivalDate
            if !timerRunning {
                startPersistentTimer()
            }
        } else {
            let dep = lastVisit.departureDate!
            hasDeparted = true
            timerRunning = false
            parkingTimer?.invalidate()
            parkingTimer = nil

            departureTime = dep
            departureElapsed = Date().timeIntervalSince(dep)
            departureElapsedTimer?.invalidate()
            let timer = Timer(timeInterval: 1.0, repeats: true) { _ in
                guard hasDeparted, let d = departureTime else { return }
                let e = Date().timeIntervalSince(d)
                DispatchQueue.main.async {
                    departureElapsed = e
                }
            }
            departureElapsedTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func startPersistentTimer() {
        guard !timerRunning else { return }
        timerRunning = true
        // 非自己開車（打車、步行等）唔需要泊車時間提醒
        if !isNonAutomotiveArrival {
            startParkingReminder()
        }
        let d = Self.appGroupDefaults ?? .standard
        d.set(parkingStartTime, forKey: "parkingStartTime")
        d.set(hasDeparted, forKey: "hasDeparted")
        d.set(manualDeparted, forKey: "manualDeparted")
        d.set(departureTime, forKey: "parkingDepartureTime")
        d.set(timerRunning, forKey: "timerRunning")
        d.set(lastKnownArrivalDate, forKey: "lastKnownArrivalDate")
        d.set(locationManager.currentAddress, forKey: "parkingEntryLocation")
        d.synchronize()
        syncLiveActivity()
        parkingTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { _ in
            let entry = parkingEntryTime
            let start = parkingStartTime
            let e = Date().timeIntervalSince(entry)
            let d = Date().timeIntervalSince(start)
            DispatchQueue.main.async {
                parkingElapsed = e
                capsuleDuration = d
            }
            // 專注模式（極致）：連 widget timeline 每秒刷新都慳埋
            if !focusCutsDetection {
                WidgetCenter.shared.reloadTimelines(ofKind: "ParkingTimerWidget")
            }
        }
        parkingTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func startStationaryTimer() {
        stationaryTimer?.invalidate()
        let start = Date()
        stationaryStartTime = start
        stationaryElapsed = 0
        let timer = Timer(timeInterval: 1.0, repeats: true) { _ in
            let e = Date().timeIntervalSince(start)
            DispatchQueue.main.async {
                stationaryElapsed = e
            }
        }
        stationaryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopStationaryTimer() {
        stationaryTimer?.invalidate()
        stationaryTimer = nil
        stationaryStartTime = nil
        stationaryElapsed = 0
    }

    private func startDepartureCountdown() {
        if let timer = departureTimer {
            timer.invalidate()
            departureTimer = nil
            parkingCountdown = nil
            return
        }
        parkingCountdown = 3
        departureTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            guard let count = parkingCountdown, count > 1 else {
                timer.invalidate()
                departureTimer = nil
                parkingCountdown = nil
                parkingDeparted = true
                showCheckmarkAnimation = true
                hasDeparted = true
                manualDeparted = true
                departureTime = Date()
                showDepartedLabel = true
                departureTimerID = UUID()
                DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showDepartedLabel = false
                    }
                }
                let savedDuration = capsuleDuration
                capsuleDuration = 0
                parkingElapsed = 0
                timerRunning = false
                parkingTimer?.invalidate()
                parkingTimer = nil
                lastKnownArrivalDate = nil
                saveParkingState()
                WidgetCenter.shared.reloadTimelines(ofKind: "ParkingTimerWidget")
                photoStorage.deleteAll()
                showingExpandedPhotos = false
                selectedPhotoIndex = nil
                departureElapsed = 0
                departureElapsedTimer?.invalidate()
                let t = Timer(timeInterval: 1.0, repeats: true) { _ in
                    guard hasDeparted, let dep = departureTime else { return }
                    let e = Date().timeIntervalSince(dep)
                    DispatchQueue.main.async {
                        departureElapsed = e
                    }
                }
                departureElapsedTimer = t
                RunLoop.main.add(t, forMode: .common)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        parkingDeparted = false
                        showCheckmarkAnimation = false
                        isParkingMemoryExpanded = false
                        isCapsuleExpanded = true
                        orbOpacity = 0.5
                        capsuleOnRight = false
                        capsuleDuration = savedDuration
                    }
                }
                return
            }
            DispatchQueue.main.async {
                parkingCountdown = count - 1
            }
        }
    }

    @State private var adjustHideWorkItem: DispatchWorkItem?

    // MARK: - 泊車時間提醒
    /// 每30分鐘整點前5分鐘發送通知（25min, 55min, 1h25m...），超過3小時停止
    /// 如果該地點習慣長時間停泊（>=3小時），則跳過提醒
    private func startParkingReminder() {
        stopParkingReminder()
        lastReminderMinute = -1

        // 用 UNTimeIntervalNotificationTrigger 預先排程通知（後台都能觸發）
        scheduleParkingNotifications()

        // 同時保留 Timer 用嚟更新 lastReminderMinute（前台時）
        parkingReminderTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            DispatchQueue.main.async {
                guard !hasDeparted, timerRunning else { return }
                let elapsed = parkingElapsed
                let minutes = Int(elapsed / 60)
                guard minutes < 180 else {
                    self.stopParkingReminder()
                    return
                }
                if self.isLongParkingHabit() { return }
                let nextHalfHour = ((minutes / 30) + 1) * 30
                let minutesBefore = nextHalfHour - minutes
                if minutesBefore <= 5 && minutesBefore > 0 && minutes != self.lastReminderMinute {
                    self.lastReminderMinute = minutes
                    // 前台時直接發通知
                    self.sendParkingReminder(minutes: minutes)
                }
            }
        }
    }

    /// 預先排程泊車提醒通知（後台都能觸發）
    private func scheduleParkingNotifications() {
        let center = UNUserNotificationCenter.current()
        // 先移除舊嘅泊車提醒
        center.removePendingNotificationRequests(withIdentifiers: ["parking-reminder-scheduled"])

        let entryTime = parkingEntryTime

        // 計算未來3小時內嘅提醒時間（每30分鐘整點前5分鐘）
        var identifiers: [String] = []
        for halfHour in stride(from: 30, through: 180, by: 30) {
            let reminderMinute = halfHour - 5  // 整點前5分鐘
            let secondsFromNow = Double(reminderMinute) * 60 - parkingElapsed
            guard secondsFromNow > 10 else { continue }  // 至少10秒後

            let content = UNMutableNotificationContent()
            let hours = reminderMinute / 60
            let mins = reminderMinute % 60
            let timeStr = hours > 0 ? "\(hours)小時\(mins)分鐘" : "\(mins)分鐘"
            content.title = String(localized: "泊車時間提醒")
            content.body = String(localized: "你已經泊車\(timeStr)")
            content.sound = .default

            let id = "parking-reminder-scheduled-\(halfHour)"
            identifiers.append(id)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: secondsFromNow, repeats: false)
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            center.add(request)
        }
    }

    private func stopParkingReminder() {
        parkingReminderTimer?.invalidate()
        parkingReminderTimer = nil
        // 取消排程通知
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [
            "parking-reminder-scheduled-30",
            "parking-reminder-scheduled-60",
            "parking-reminder-scheduled-90",
            "parking-reminder-scheduled-120",
            "parking-reminder-scheduled-150",
            "parking-reminder-scheduled-180",
        ])
    }

    /// 檢查當前停車地點是否習慣長時間停泊（>=3小時）
    private func isLongParkingHabit() -> Bool {
        guard let currentCoord = locationManager.lastLocation?.coordinate else { return false }
        // 找最近的停車場
        guard let lotIdx = parkingFloorStore.findLotIndex(near: currentCoord, radiusMeters: 200) else { return false }
        let lot = parkingFloorStore.lots[lotIdx]
        // 計算該地點的平均泊車時長
        let durations = lot.points.compactMap { point -> TimeInterval? in
            // 用 createdAt 作為到達時間，如果有多個記錄可以計算平均
            return nil  // 暫時用簡單邏輯
        }
        // 如果有手動設定的長時間標記
        if lot.points.contains(where: { $0.predictedFloorIndex != nil }) {
            // 有樓層記錄的地點通常是有結構的停車場，可能是長時間
            return false  // 暫時不跳過，後續可根據歷史數據判斷
        }
        return false
    }

    private func sendParkingReminder(minutes: Int) {
        // 只喺 App 喺後台時先發通知，前台唔發
        guard !isInForeground else { return }

        let content = UNMutableNotificationContent()
        let hours = minutes / 60
        let mins = minutes % 60
        let timeStr = hours > 0 ? "\(hours)小時\(mins)分鐘" : "\(mins)分鐘"
        content.title = String(localized: "泊車時間提醒")
        content.body = String(localized: "你已經泊車\(timeStr)")
        content.sound = .default
        let req = UNNotificationRequest(identifier: "parking-reminder-\(minutes)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    private func startCapsuleUpdateTimer() {
        stopCapsuleUpdateTimer()
        let timer = Timer(timeInterval: 2.0, repeats: true) { _ in
            DispatchQueue.main.async {
                // 時速頁（selectedTab == 0）時跳過主頁專用嘅重計算，減少主線程阻塞
                if selectedTab == 1 {
                    updateVisitStatus()
                    if locationManager.speed >= 5 {
                        refreshETA()
                    }
                }
            }
        }
        capsuleUpdateTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopCapsuleUpdateTimer() {
        capsuleUpdateTimer?.invalidate()
        capsuleUpdateTimer = nil
    }

    // MARK: - Random Speed Info Display
    private func startRandomInfoTimer() {
        stopRandomInfoTimer()
        // 專注模式（平衡／極致）：唔再彈資訊／定時 refreshETA
        guard !focusCutsInfoAndETA else { return }
        if compactModeShowStatus {
            return
        }
        showSpeedInfo = true
        scheduleNextRandomInfo()
    }

    private func stopRandomInfoTimer() {
        randomInfoTimer?.invalidate()
        randomInfoTimer = nil
        speedInfoTimer?.invalidate()
        speedInfoTimer = nil
        showSpeedInfo = false
    }

    private func scheduleNextRandomInfo() {
        if compactModeShowStatus {
            return
        }
        let interval = Double.random(in: 40...60)
        randomInfoTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [self] _ in
            DispatchQueue.main.async {
                guard !compactModeShowStatus else { return }
                // 排程期間開咗專注模式 → 直接唔彈，退出時會重新排
                guard !focusCutsInfoAndETA else { return }
                refreshETA()
                withAnimation(.easeInOut(duration: 0.3)) {
                    showSpeedInfo = false
                }
                speedInfoTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [self] _ in
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showSpeedInfo = true
                        }
                        scheduleNextRandomInfo()
                    }
                }
            }
        }
    }

    private func restartRandomInfoTimerIfNeeded() {
        guard !isCapsuleExpanded, !isParkingMemoryExpanded else { return }
        if compactModeShowStatus {
            stopRandomInfoTimer()
            return
        }
        startRandomInfoTimer()
    }

    private var selectedParkingPoint: ParkingPointRecord? {
        guard let id = selectedParkingPointID else { return nil }
        return parkingFloorStore.allPoints.first(where: { $0.id == id })
    }

    private func parkingPointCapsule(point: ParkingPointRecord) -> some View {
        let currentFloor = point.manualFloorIndex ?? point.predictedFloorIndex ?? 0
        let hasFloor = point.manualFloorIndex != nil || point.predictedFloorIndex != nil
        return ZStack {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeIn(duration: 0.18)) {
                        selectedParkingPointID = nil
                    }
                }

            VStack(spacing: 12) {
                VStack(spacing: 6) {
                    Text(point.address.isEmpty ? String(localized: "停車點") : point.address)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(String(localized: "樓層") + " \(ParkingFloorStore.formatFloor(currentFloor))")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.18), value: currentFloor)

                    if !hasFloor {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("氣壓計採集中…")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                
                HStack(spacing: 14) {
                    Button {
                        parkingFloorStore.setManualFloor(pointID: point.id, floorIndex: currentFloor - 1)
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: 56, height: 44)
                            .contentShape(Rectangle())
                            .glassEffect(.regular, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        parkingFloorStore.setManualFloor(pointID: point.id, floorIndex: currentFloor + 1)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: 56, height: 44)
                            .contentShape(Rectangle())
                            .glassEffect(.regular, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        startNavigationToParkingPoint(point)
                        withAnimation(.easeIn(duration: 0.18)) {
                            selectedParkingPointID = nil
                        }
                    } label: {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: 56, height: 44)
                            .contentShape(Rectangle())
                            .glassEffect(.regular, in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
            .padding(.horizontal, 28)
            .offset(y: 56)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func startNavigationToParkingPoint(_ point: ParkingPointRecord) {
        meterRouteTarget = nil
        meterDirections?.cancel()
        meterDirections = nil
        guard let currentLocation = locationManager.lastLocation else { return }
        let routeToken = UUID()
        routePriorityToken = routeToken
        routePriorityAnchor = currentLocation.coordinate
        let overlayToken = UUID()
        routeOverlayToken = overlayToken
        routeOverlayAnimationToken = overlayToken
        if !showMap && !showSatellite {
            withAnimation(.easeInOut(duration: 0.3)) {
                showMap = true
            }
        }
        
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: currentLocation.coordinate.wgs84ToGCJ02))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: point.coordinate.wgs84ToGCJ02))
        request.transportType = .automobile
        request.requestsAlternateRoutes = false
        let directions = MKDirections(request: request)
        directions.calculate { response, error in
            guard let route = response?.routes.first, error == nil else {
                DispatchQueue.main.async {
                    routePriorityToken = nil
                    routePriorityAnchor = nil
                    routeOverlayToken = nil
                    routeOverlayAnimationToken = nil
                }
                return
            }
            DispatchQueue.main.async {
                withAnimation {
                    showingRoute = true
                    routePolyline = route.polyline
                    routeAnimationPolyline = simplifiedRoutePolyline(route.polyline, maxPoints: 220)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    guard showingRoute, routePriorityToken == routeToken else { return }
                    routePriorityToken = nil
                    routePriorityAnchor = nil
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) {
                    guard showingRoute, routeOverlayToken == overlayToken else { return }
                    routeOverlayAnimationToken = nil
                    routeAnimationPolyline = nil
                }
            }
        }
    }

    // MARK: - 香港地點彈窗

    private func startNavigationToMeter(_ meter: ParkingMeter) {
        guard let location = locationManager.lastLocation else {
            meterRouteError = "尚未取得目前位置"
            return
        }
        meterManager.selectedMeter = nil
        meterManager.dismissNotice()
        meterDirections?.cancel()
        meterRouteTarget = meter
        lastRerouteRequestAt = Date()
        let token = UUID()
        routePriorityToken = token
        routePriorityAnchor = location.coordinate
        if !showMap && !showSatellite { showMap = true }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate.wgs84ToGCJ02))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: meter.coordinate.wgs84ToGCJ02))
        request.transportType = .automobile
        request.requestsAlternateRoutes = true
        let directions = MKDirections(request: request)
        meterDirections = directions
        directions.calculate { response, error in
            DispatchQueue.main.async {
                guard meterDirections === directions, meterRouteTarget?.id == meter.id else { return }
                meterDirections = nil
                guard let route = response?.routes.min(by: { $0.expectedTravelTime < $1.expectedTravelTime }), error == nil else {
                    meterRouteError = error?.localizedDescription ?? "暫時找不到可行駕駛路線"
                    routePriorityToken = nil
                    routePriorityAnchor = nil
                    meterRouteTarget = nil
                    return
                }
                routeOverlayToken = token
                routeOverlayAnimationToken = token
                withAnimation {
                    showingRoute = true
                    routePolyline = route.polyline
                    routeAnimationPolyline = simplifiedRoutePolyline(route.polyline, maxPoints: 220)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    guard routeOverlayToken == token else { return }
                    routePriorityToken = nil
                    routePriorityAnchor = nil
                    routeOverlayAnimationToken = nil
                    routeAnimationPolyline = nil
                }
            }
        }
    }

    private func hkLocationCapsule(title: String, coordinate: CLLocationCoordinate2D) -> some View {
        ZStack {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeIn(duration: 0.18)) {
                        selectedHKLocation = nil
                    }
                }

            VStack(spacing: 12) {
                VStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }

                HStack(spacing: 14) {
                    Button {
                        startNavigationToHKLocation(coordinate)
                        withAnimation(.easeIn(duration: 0.18)) {
                            selectedHKLocation = nil
                        }
                    } label: {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: 56, height: 44)
                            .contentShape(Rectangle())
                            .glassEffect(.regular, in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
            .padding(.horizontal, 28)
            .offset(y: 56)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func startNavigationToHKLocation(_ coordinate: CLLocationCoordinate2D) {
        meterRouteTarget = nil
        meterDirections?.cancel()
        meterDirections = nil
        guard let currentLocation = locationManager.lastLocation else { return }
        let routeToken = UUID()
        routePriorityToken = routeToken
        routePriorityAnchor = currentLocation.coordinate
        let overlayToken = UUID()
        routeOverlayToken = overlayToken
        routeOverlayAnimationToken = overlayToken
        if !showMap && !showSatellite {
            withAnimation(.easeInOut(duration: 0.3)) {
                showMap = true
            }
        }

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: currentLocation.coordinate.wgs84ToGCJ02))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: coordinate.wgs84ToGCJ02))
        request.transportType = .automobile
        request.requestsAlternateRoutes = false
        let directions = MKDirections(request: request)
        directions.calculate { response, error in
            guard let route = response?.routes.first, error == nil else {
                DispatchQueue.main.async {
                    routePriorityToken = nil
                    routePriorityAnchor = nil
                    routeOverlayToken = nil
                    routeOverlayAnimationToken = nil
                }
                return
            }
            DispatchQueue.main.async {
                withAnimation {
                    showingRoute = true
                    routePolyline = route.polyline
                    routeAnimationPolyline = simplifiedRoutePolyline(route.polyline, maxPoints: 220)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    guard showingRoute, routePriorityToken == routeToken else { return }
                    routePriorityToken = nil
                    routePriorityAnchor = nil
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) {
                    guard showingRoute, routeOverlayToken == overlayToken else { return }
                    routeOverlayAnimationToken = nil
                    routeAnimationPolyline = nil
                }
            }
        }
    }

    private func showAdjustText() {
        adjustHideWorkItem?.cancel()
        withAnimation(.easeIn(duration: 0.15)) {
            timeAdjustText = String(localized: "已調整") + "\(timeAdjustAccumulated)" + String(localized: "分鐘")
        }
        if timeAdjustAccumulated == 0 {
            let work = DispatchWorkItem { [self] in
                withAnimation(.easeOut(duration: 0.2)) {
                    timeAdjustText = nil
                }
            }
            adjustHideWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
        }
    }

    private func capturePhoto() {
        #if !targetEnvironment(simulator)
        guard !isCapturing else { return }
        guard isCameraActive else { return }
        isCapturing = true
        NotificationCenter.default.post(name: .captureParkingPhoto, object: nil)
        resetCameraInactivityTimer()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.isCapturing = false
        }
        #endif
    }

    private func activateCamera() {
        isCameraActive = true
        viewfinderBreathe = false  // 停止呼吸
        // 拍照按鈕模糊入場動畫
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            cameraButtonBlurIn = true
        }
        withAnimation(.easeInOut(duration: 0.8)) {
            cameraFadeOpacity = 0
        }
        resetCameraInactivityTimer()
    }

    private func deactivateCamera() {
        // viewfinder 呼吸動畫開始
        viewfinderBreathe = true
        // 拍照按鈕模糊退場動畫
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            cameraButtonBlurIn = false
        }
        withAnimation(.easeInOut(duration: 0.8)) {
            cameraFadeOpacity = 1
        }
        // Delay setting isCameraActive until fade completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.isCameraActive = false
        }
        cameraInactivityTimer?.invalidate()
        cameraInactivityTimer = nil
    }

    private func resetCameraInactivityTimer() {
        cameraInactivityTimer?.invalidate()
        cameraInactivityTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { _ in
            DispatchQueue.main.async {
                self.deactivateCamera()
            }
        }
    }

    private func startCaptureAnimation(photo: UIImage) {
        guard let saved = photoStorage.savePhoto(photo) else { return }
        let tempID = saved.id
        animatingPhotoID = tempID
        animatingPhotoImage = photo
        animatingPhotoPhase = 0
        animatingPhotoRotation = 0
        // 計算縮略圖位置偏移（左上角）
        let camW: CGFloat = isLandscape ? 304.0 : 338.0
        let camH: CGFloat = isLandscape ? 211.0 : 235.0
        animatingPhotoOffsetX = -(camW / 2 - 20 - 46.0 / 2) + CGFloat(saved.offsetX)
        animatingPhotoOffsetY = -(camH / 2 - 18 - 32.0 / 2) + CGFloat(saved.offsetY)

        // 動畫：喺縮略圖位置原位放大 + 旋轉
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            withAnimation(.timingCurve(0.4, 0.0, 0.2, 1.0, duration: 0.45)) {
                animatingPhotoPhase = 1
                animatingPhotoRotation = saved.rotation
            }
        }

        // Clean up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            animatingPhotoID = nil
            animatingPhotoImage = nil
            animatingPhotoPhase = 0
            animatingPhotoOffsetX = 0
            animatingPhotoOffsetY = 0
            animatingPhotoRotation = 0
        }

        // Trigger LLM recognition via shortcut (if enabled)
        if vlmRecognitionEnabled {
            recognizeParkingWithLLM(image: photo, photoID: tempID)
        }
    }

    // MARK: - LLM Parking Recognition

    private var hasLLMResult: Bool {
        llmRawResult != nil
    }

    private func recognizeParkingWithLLM(image: UIImage, photoID: UUID) {
        currentRecognizingPhotoID = photoID
        UIPasteboard.general.image = image
        llmRawResult = nil
        llmError = nil
        parkingInfoSwitchTimer?.invalidate()
        showLLMActionPrompt = true
    }

    private func startLLMPollingAfterAction() {
        isRecognizing = true
        showLLMActionPrompt = false
        sfxPlayer.playVLMLoading()
        startOrbRecognitionBoost()
        startLLMPollingClipboard()

        // 1 分鐘後自動停止 loading 音效 + 光球漸進回歸正常速度（不觸發六色）
        llmSoundStopTimer?.invalidate()
        llmSoundStopTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak sfxPlayer] _ in
            sfxPlayer?.stopVLMLoadingGracefully()
            DispatchQueue.main.async {
                stopOrbRecognitionBoostGradually(triggerSixColor: false)
            }
        }
    }

    private func startLLMPollingClipboard() {
        llmPollTimer?.invalidate()
        var attempts = 0
        let maxAttempts = 120 // 2 minutes max (1s interval)
        let initialChangeCount = UIPasteboard.general.changeCount

        llmPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            attempts += 1

            let currentChangeCount = UIPasteboard.general.changeCount
            if currentChangeCount != initialChangeCount,
               let text = UIPasteboard.general.string,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {

                timer.invalidate()
                self.llmPollTimer = nil

                DispatchQueue.main.async {
                    self.llmSoundStopTimer?.invalidate()
                    self.llmSoundStopTimer = nil
                    self.sfxPlayer.stopVLMLoadingGracefully()
                    self.sfxPlayer.playVLMDone()
                    self.stopOrbRecognitionBoost()
                    self.llmRawResult = text
                    self.isRecognizing = false
                    self.parseParkingLLMResponse(text)
                }
            } else if attempts >= maxAttempts {
                timer.invalidate()
                self.llmPollTimer = nil

                DispatchQueue.main.async {
                    self.llmSoundStopTimer?.invalidate()
                    self.llmSoundStopTimer = nil
                    if self.isRecognizing {
                        self.sfxPlayer.stopVLMLoadingImmediately()
                        self.stopOrbRecognitionBoostGradually(triggerSixColor: false)
                        self.llmError = String(localized: "等待超時（2分鐘）。請確認快捷指令名稱是否正確，或手動運行一次快捷指令後重試。")
                        self.isRecognizing = false
                    }
                }
            }
        }
    }

    private func parseParkingLLMResponse(_ text: String) {
        let lines = text.components(separatedBy: .newlines)
        var needsFloorConfirm = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Helper: extract value after "：" or ":", checking multiple keywords
            func extractValue(from line: String, keywords: [String]) -> String? {
                for keyword in keywords {
                    guard line.contains(keyword) else { continue }
                    for sep in ["：", ":"] {
                        let components = line.components(separatedBy: sep)
                        if components.count > 1, let val = components.last?.trimmingCharacters(in: .whitespacesAndNewlines), isValidParkingValue(val) {
                            return val
                        }
                    }
                }
                return nil
            }

            // Only accept short, concrete values — reject descriptive text
            func isValidParkingValue(_ val: String) -> Bool {
                if val.isEmpty || val == "-" || val == "无" || val == "沒有" || val == "没有" { return false }
                // Reject long descriptive sentences (>6 chars likely not a code)
                if val.count > 6 { return false }
                // Reject common "not found" phrases
                let reject = ["未", "需", "无法", "不能", "不确", "未知", "待", "暂"]
                for r in reject {
                    if val.contains(r) { return false }
                }
                return true
            }

            // Extract spot number — simplified "车位号" / traditional "車位號"
            if let val = extractValue(from: trimmed, keywords: ["车位号", "車位號", "车位", "車位"]) {
                llmSpotNumber = val
                hasParkingSpotData = true
            }

            // Extract area code — simplified "区域号" / traditional "區域號"
            if let val = extractValue(from: trimmed, keywords: ["区域号", "區域號", "区域", "區域"]) {
                llmAreaCode = val
                hasParkingSpotData = true
            }

            // Extract floor — simplified "楼层" / traditional "樓層"
            var needsFloorConfirm = false
            if let floorStr = extractValue(from: trimmed, keywords: ["楼层", "樓層"]) {
                hasParkingSpotData = true
                if let index = Self.parseFloorIndex(floorStr) {
                    // 與氣壓計預測比較，觸發確認彈窗
                    if let current = parkingFloorStore.allPoints.first,
                       let barometerFloor = current.predictedFloorIndex,
                       index != barometerFloor,
                       !hasConfirmedFloorThisSession {
                        // Defer: save pending floor, don't write to store yet
                        pendingOriginalFloorIndex = barometerFloor
                        pendingFloorText = floorStr
                        pendingFloorIndex = index
                        recognizedFloorToConfirm = index
                        recognizedFloorText = floorStr
                        showFloorConfirm = true
                        needsFloorConfirm = true
                    } else {
                        // No confirmation needed — write floor immediately
                        llmFloorText = floorStr
                        llmFloorIndex = index
                    }
                } else {
                    llmFloorText = floorStr
                }
            }
        }

        // Save this photo's contribution
        if let photoID = currentRecognizingPhotoID {
            var contribution: [String: String] = [:]
            if let s = llmSpotNumber { contribution["spot"] = s }
            if let a = llmAreaCode { contribution["area"] = a }
            if let f = llmFloorText { contribution["floor"] = f }
            if !contribution.isEmpty {
                parkingPhotoContributions[photoID] = contribution
            }
            currentRecognizingPhotoID = nil
        }

        // Merge all contributions and display —
        // if floor is pending confirmation, merge spot/area only (skip floor)
        if needsFloorConfirm {
            mergeParkingInfoExcludingFloor()
        } else {
            mergeAndDisplayParkingInfo()
        }
        saveParkingContributions()
        // triggerOrbSpeedBoost 已由 stopOrbRecognitionBoost() 處理
    }

    private func startParkingInfoSwitchTimer() {
        parkingInfoSwitchTimer?.invalidate()
        parkingInfoSwitchTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.5)) {
                    self.parkingInfoDisplayMode.toggle()
                }
            }
        }
        // Show parking info immediately after recognition
        withAnimation(.easeInOut(duration: 0.5)) {
            parkingInfoDisplayMode = true
        }
    }

    private func resetParkingInfoSwitchTimer() {
        parkingInfoSwitchTimer?.invalidate()
        parkingInfoSwitchTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.5)) {
                    self.parkingInfoDisplayMode.toggle()
                }
            }
        }
    }

    private func boostOrbs(w: CGFloat, h: CGFloat, t: Double, isBoosted: Bool, orbSize: CGFloat, sixColorOpacity: Double = 0) -> some View {
        let ax: CGFloat = w * 0.3
        let ay: CGFloat = h * 0.3
        let baseX: CGFloat = w * 0.5 - orbSize / 2
        let baseY: CGFloat = h * 0.5 - orbSize / 2
        let op: CGFloat = sixColorOpacity > 0 ? CGFloat(sixColorOpacity) : (isBoosted ? 0.5 : 0)
        return ZStack {
            boostOrb(hex: "F79B1C", op: op, orbSize: orbSize, baseX: baseX, baseY: baseY, t: t, sx: 0.7, sxMul: 1.3, cy: 0.5, cyMul: 1.1, phase: 0.0, ax: ax, ay: ay)
            boostOrb(hex: "DB7FFB", op: op, orbSize: orbSize, baseX: baseX, baseY: baseY, t: t, sx: 0.6, sxMul: 1.5, cy: 0.8, cyMul: 1.2, phase: 1.0, ax: ax, ay: ay)
            boostOrb(hex: "FFFFFF", op: sixColorOpacity > 0 ? CGFloat(sixColorOpacity * 0.8) : (isBoosted ? 0.4 : 0), orbSize: orbSize, baseX: baseX, baseY: baseY, t: t, sx: 0.5, sxMul: 1.7, cy: 0.7, cyMul: 1.0, phase: 2.0, ax: ax, ay: ay)
            boostOrb(hex: "03AAF6", op: op, orbSize: orbSize, baseX: baseX, baseY: baseY, t: t, sx: 0.8, sxMul: 1.1, cy: 0.6, cyMul: 1.4, phase: 3.0, ax: ax, ay: ay)
            boostOrb(hex: "ED75FA", op: op, orbSize: orbSize, baseX: baseX, baseY: baseY, t: t, sx: 0.65, sxMul: 1.4, cy: 0.55, cyMul: 1.6, phase: 4.0, ax: ax, ay: ay)
            boostOrb(hex: "F62B6A", op: op, orbSize: orbSize, baseX: baseX, baseY: baseY, t: t, sx: 0.75, sxMul: 1.2, cy: 0.65, cyMul: 1.5, phase: 5.0, ax: ax, ay: ay)
        }
    }

    private func boostOrb(hex: String, op: CGFloat, orbSize: CGFloat, baseX: CGFloat, baseY: CGFloat, t: Double, sx: Double, sxMul: Double, cy: Double, cyMul: Double, phase: Double, ax: CGFloat, ay: CGFloat) -> some View {
        let ox = baseX + CGFloat(sin(t * sx + phase) + 0.3 * sin(t * sxMul + phase * 0.5)) * ax
        let oy = baseY + CGFloat(cos(t * cy + phase) + 0.3 * cos(t * cyMul + phase * 0.5)) * ay
        return Circle()
            .fill(Color(hex: hex).opacity(Double(op)))
            .blur(radius: 16)
            .frame(width: orbSize, height: orbSize)
            .offset(x: ox, y: oy)
    }

    private func triggerOrbSpeedBoost() {
        // Phase 1: ramp up 1.0 → 1.5 (slow start)
        withAnimation(.easeIn(duration: 1.0)) {
            parkingOrbBoost = 1.5
        }
        // Phase 2: accelerate 1.5 → 2.6
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeIn(duration: 0.8)) {
                self.parkingOrbBoost = 2.6
            }
        }
        // Phase 3: hold at 2.6, then ramp down 2.6 → 1.0（延長六色動畫時長）
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.8) {
            withAnimation(.easeOut(duration: 3.0)) {
                self.parkingOrbBoost = 1.0
            }
        }
    }

    // MARK: - Orb Recognition Boost (識別中加速)

    private func startOrbRecognitionBoost() {
        // 取消正在進行的漸進停止
        orbGradualStopTimer?.invalidate()
        orbGradualStopTimer = nil
        isOrbRecognizingBoost = true
        // 確保 speedMultiplier 重置，避免同 entrance effect 疊加
        animationClock.speedMultiplier = 1.0
        // 記錄當前 elapsed 作為基準，識別期間用相對時間
        orbBoostElapsedOffset = animationClock.elapsed
        withAnimation(.easeInOut(duration: 3.0)) {
            parkingOrbBoost = 5.0
        }
    }

    /// 漸進停止：光球速度慢慢回歸正常（保持 isOrbRecognizingBoost=true 避免跳變）
    private func stopOrbRecognitionBoostGradually(triggerSixColor: Bool, duration: TimeInterval = 3.0) {
        // 保持 isOrbRecognizingBoost = true，orbElapsed 繼續用相對時間
        // 只漸降 parkingOrbBoost：5.0 → 1.0
        let startBoost = parkingOrbBoost
        let startTime = Date()
        orbGradualStopTimer?.invalidate()
        orbGradualStopTimer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { timer in
            let elapsed = Date().timeIntervalSince(startTime)
            let progress = min(elapsed / duration, 1.0)
            // easeInOut 曲線
            let eased = progress < 0.5
                ? 2 * progress * progress
                : 1 - pow(-2 * progress + 2, 2) / 2
            let newBoost = startBoost + (1.0 - startBoost) * eased
            DispatchQueue.main.async {
                parkingOrbBoost = newBoost
                if progress >= 1.0 {
                    timer.invalidate()
                    orbGradualStopTimer = nil
                    parkingOrbBoost = 1.0
                    // boost 已到 1.0，切 flag 回正常
                    // offset 保留唔歸零，避免 orbElapsed 跳變
                    isOrbRecognizingBoost = false
                    // orbBoostElapsedOffset 唔歸零：trig 係週期性，永久 offset 只 shift phase 不跳位置
                    if triggerSixColor {
                        triggerOrbSpeedBoost()
                    }
                }
            }
        }
        RunLoop.main.add(orbGradualStopTimer!, forMode: .common)
    }

    private func stopOrbRecognitionBoost(triggerSixColor: Bool = true) {
        // 取消正在進行的漸進停止
        orbGradualStopTimer?.invalidate()
        orbGradualStopTimer = nil
        // offset 保留唔歸零（trig 週期性，永久 offset 只 shift phase 不跳位置）
        // 立即重置（取消正在跑的 easeInOut 動畫）
        withTransaction(Transaction(animation: .none)) {
            parkingOrbBoost = 1.0
        }
        isOrbRecognizingBoost = false
        // 只有識別成功時才觸發六色 ramp up
        if triggerSixColor {
            triggerOrbSpeedBoost()
        }
    }

    private static func parseFloorIndex(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // "B2" → -2
        if let regex = try? NSRegularExpression(pattern: "^[Bb](\\d+)$", options: []),
           let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: trimmed.utf16.count)),
           let range = Range(match.range(at: 1), in: trimmed),
           let num = Int(trimmed[range]) {
            return -num
        }
        // "-2樓/楼" or "2樓/楼" (traditional & simplified)
        if let regex = try? NSRegularExpression(pattern: "^(-?)(\\d+)\\s*[樓楼]$", options: []),
           let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: trimmed.utf16.count)),
           let numRange = Range(match.range(at: 2), in: trimmed),
           let num = Int(trimmed[numRange]) {
            let hasMinus = match.range(at: 1).length > 0
            return hasMinus ? -num : num
        }
        // "地下2層/层" (traditional & simplified)
        if let regex = try? NSRegularExpression(pattern: "地下(\\d+)[層层]", options: []),
           let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: trimmed.utf16.count)),
           let range = Range(match.range(at: 1), in: trimmed),
           let num = Int(trimmed[range]) {
            return -num
        }
        return nil
    }

    private func buildRecognitionLogicText() -> String {
        if parkingPhotoContributions.isEmpty {
            return String(localized: "尚未進行識別")
        }
        var lines: [String] = [String(localized: "識別方式：Apple Intelligence (Cloud)"), "快捷指令：\(llmShortcutName)", ""]
        for (photoID, contribution) in parkingPhotoContributions {
            let shortID = photoID.uuidString.prefix(8)
            var parts: [String] = []
            if let s = contribution["spot"] { parts.append(String(localized: "車位") + ":\(s)") }
            if let a = contribution["area"] { parts.append(String(localized: "區域") + ":\(a)") }
            if let f = contribution["floor"] { parts.append(String(localized: "樓層") + ":\(f)") }
            lines.append("[\(shortID)] \(parts.joined(separator: " "))")
        }
        return lines.joined(separator: "\n")
    }

    /// Merge contributions but skip floor if pending confirmation.
    /// Called immediately so spot/area update live, while floor waits for user OK.
    private func mergeParkingInfoExcludingFloor() {
        var spot: String? = nil
        var area: String? = nil
        for (_, contribution) in parkingPhotoContributions {
            if let s = contribution["spot"], spot == nil { spot = s }
            if let a = contribution["area"], area == nil { area = a }
        }
        llmSpotNumber = spot
        llmAreaCode = area
        llmRawResult = parkingPhotoContributions.isEmpty ? nil : "multi-photo"
        if spot != nil || area != nil {
            hasParkingSpotData = true
        }
        // Don't write floor — it's pending confirmation
        parkingFloorStore.updateLLMData(
            spotNumber: spot, areaCode: area,
            floorText: nil, floorIndex: nil
        )
        if spot != nil || area != nil {
            startParkingInfoSwitchTimer()
        }
    }

    private func mergeAndDisplayParkingInfo() {
        var spot: String? = nil
        var area: String? = nil
        var floor: String? = nil
        var floorIdx: Int? = nil

        for (_, contribution) in parkingPhotoContributions {
            if let s = contribution["spot"], spot == nil { spot = s }
            if let a = contribution["area"], area == nil { area = a }
            if let f = contribution["floor"], floor == nil {
                floor = f
                floorIdx = Self.parseFloorIndex(f)
            }
        }

        llmSpotNumber = spot
        llmAreaCode = area
        llmFloorText = floor
        llmFloorIndex = floorIdx
        llmRawResult = parkingPhotoContributions.isEmpty ? nil : "multi-photo"
        if spot != nil || area != nil || floor != nil {
            hasParkingSpotData = true
        }

        // 同步到 ParkingFloorStore（統一數據源）
        parkingFloorStore.updateLLMData(
            spotNumber: spot, areaCode: area, floorText: floor, floorIndex: floorIdx
        )

        if hasLLMResult {
            startParkingInfoSwitchTimer()
        }
    }

    private func saveParkingContributions() {
        let d = Self.appGroupDefaults ?? .standard
        if let data = try? JSONEncoder().encode(parkingPhotoContributions) {
            d.set(data, forKey: "parkingPhotoContributions")
        }
        d.synchronize()
    }

    private func loadParkingContributions() {
        let d = Self.appGroupDefaults ?? .standard
        if let data = d.data(forKey: "parkingPhotoContributions"),
           let decoded = try? JSONDecoder().decode([UUID: [String: String]].self, from: data) {
            parkingPhotoContributions = decoded
        }
    }

    private func clearParkingContributions() {
        parkingPhotoContributions = [:]
        llmSpotNumber = nil
        llmAreaCode = nil
        llmFloorText = nil
        llmFloorIndex = nil
        llmRawResult = nil
        llmError = nil
        hasParkingSpotData = false
        llmPollTimer?.invalidate()
        llmPollTimer = nil
        parkingInfoSwitchTimer?.invalidate()
        parkingInfoSwitchTimer = nil
        let d = Self.appGroupDefaults ?? .standard
        d.removeObject(forKey: "parkingPhotoContributions")
        d.synchronize()
        // 清除 ParkingFloorStore 中的 LLM 數據
        parkingFloorStore.updateLLMData(spotNumber: nil, areaCode: nil, floorText: nil, floorIndex: nil)
    }

    @State private var lastETASuccessLocation: CLLocation?  // 上次成功計算時嘅位置

    private func refreshETA() {
        guard !focusCutsInfoAndETA else { return }
        guard let dest = destinationManager.selectedDestination,
              let loc = locationManager.lastLocation else {
            return
        }

        // 如果位置偏移超過 2km 且一直失敗，清空結果
        if let lastLoc = lastETASuccessLocation {
            let moved = loc.distance(from: lastLoc)
            if moved > 2000 {
                // 偏移太遠，清空舊結果
                drivingDistanceText = nil
                etaText = nil
                drivingETASeconds = nil
                lastETASuccessLocation = nil
            }
        }

        destinationManager.calculateRoute(
            from: loc.coordinate,
            to: dest.coordinate
        ) { distance, time in
            DispatchQueue.main.async {
                if let distance = distance {
                    meterManager.updateRouteDistance(distance, destinationID: dest.id)
                    if distance < 1000 {
                        drivingDistanceText = "\(Int(distance)) m"
                    } else {
                        drivingDistanceText = String(format: "%.1f km", distance / 1000)
                    }
                    lastETASuccessLocation = loc
                }
                if let time = time {
                    drivingETASeconds = time
                    let mins = Int(time / 60)
                    if mins < 60 {
                        etaText = "\(mins) mins"
                    } else {
                        let h = mins / 60
                        let m = mins % 60
                        etaText = "\(h)h \(m)m"
                    }
                    lastETASuccessLocation = loc
                }
            }
        }
    }

    private func recalculateRoute() {
        if let meter = meterRouteTarget {
            startNavigationToMeter(meter)
            return
        }
        // 專注模式（平衡／極致）：切走 MKDirections 網絡請求
        guard !focusCutsInfoAndETA else { return }
        guard let destination = destinationManager.selectedDestination,
              let currentLocation = locationManager.lastLocation else { return }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: currentLocation.coordinate.wgs84ToGCJ02))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.coordinate.wgs84ToGCJ02))
        request.transportType = .automobile
        request.requestsAlternateRoutes = false
        let directions = MKDirections(request: request)
        directions.calculate { response, error in
            guard let route = response?.routes.first, error == nil else { return }
            DispatchQueue.main.async {
                guard meterRouteTarget == nil else { return }
                routeOverlayToken = UUID()
                routeOverlayAnimationToken = nil
                withAnimation {
                    showingRoute = true
                    routePolyline = route.polyline
                    routeAnimationPolyline = nil
                }
            }
        }
    }

    private var distanceLabel: String {
        guard let dest = destinationManager.selectedDestination else { return String(localized: "離目的地距離") }
        let name = dest.name.lowercased()
        if name.contains("home") || name.contains("家") {
            return String(localized: "離家距離")
        } else if name.contains("office") || name.contains("公司") {
            return String(localized: "離公司距離")
        }
        return "離\(dest.name)距離"
    }

    private func updateVisitStatus() {
        // 專注模式（極致）：暫停狀態偵測，退出時會重新同步
        guard !focusCutsDetection else { return }
        guard let lastVisit = locationManager.visits.first else {
            visitStatus = "已停留"
            isNonAutomotiveArrival = false
            hasParkingSpotData = true
            (Self.appGroupDefaults ?? .standard).set(false, forKey: "isNonAutomotiveArrival")
            if visitSecondaryStatus != nil {
                withAnimation(.easeInOut(duration: 0.22)) {
                    visitSecondaryStatus = nil
                }
            }
            return
        }
        
        var desiredSecondary: String? = nil
        
        if hasDeparted {
            if showDepartedLabel {
                desiredSecondary = String(localized: "已離場")
            }
            
            // 离场后：CMMotionActivity 优先，GPS 速度辅助
            let speed = locationManager.speed
            let gpsLocationChanged = isGPSLocationChanged()
            let motion = locationManager.currentMotionActivity

            // CMMotionActivity 是硬體感測器，比 GPS 速度更可靠
            if motion?.walking == true && speed > 1 {
                // 步行中：CMMotionActivity 說步行 + GPS 有移動 → 已步行
                if visitStatus != "已步行" {
                    walkingStartTime = Date()
                }
                visitStatus = "已步行"
                lastMovementTime = Date()
            } else if motion?.cycling == true && speed > 3 {
                // 騎車中：CMMotionActivity 說騎車 + GPS 有移動 → 已騎車
                if visitStatus != "已騎車" {
                    cyclingStartTime = Date()
                }
                visitStatus = "已騎車"
                lastMovementTime = Date()
            } else if speed > 8 || (speed > 5 && gpsLocationChanged) {
                // 開車中：GPS 速度快（CMMotionActivity 沒說步行/騎車才走這裡）
                if visitStatus != "已開車" {
                    walkingStartTime = nil
                    cyclingStartTime = nil
                }
                visitStatus = "已開車"
                lastMovementTime = Date()
            } else if let lastMove = lastMovementTime {
                // 不在移动，检查是否已持续2分钟以上
                let stationaryDuration = Date().timeIntervalSince(lastMove)
                if stationaryDuration >= 120 {
                    visitStatus = "已停留"
                } else {
                    // 保持之前的移动状态
                    if motion?.walking == true || motion?.cycling == true {
                        // CMMotionActivity 仍偵測到移動，保持原狀態
                    } else {
                        visitStatus = "已開車"
                    }
                }
            } else {
                if let dep = departureTime {
                    let elapsed = Date().timeIntervalSince(dep)
                    if elapsed < 120 {
                        // Manual departure: start stationary, wait for actual movement
                        // System-detected departure: assume driving (motion was the trigger)
                        visitStatus = manualDeparted ? "已停留" : "已開車"
                    } else {
                        visitStatus = "已停留"
                    }
                } else {
                    visitStatus = "已停留"
                }
            }
        } else if lastVisit.departureDate == nil {
            visitStatus = "已泊車"
            // 二次驗證：CMMotionActivity 可能誤判，用 GPS 速度輔助
            var automotive = lastVisit.isAutomotive
            if !automotive && locationManager.speed > 10 {
                // GPS 顯示仍在開車，修正為開車到達
                automotive = true
            }
            isNonAutomotiveArrival = !automotive
            if isNonAutomotiveArrival { hasParkingSpotData = false }
            (Self.appGroupDefaults ?? .standard).set(isNonAutomotiveArrival, forKey: "isNonAutomotiveArrival")
            
            let now = Date()
            let speed = locationManager.speed
            let moved = isGPSLocationChanged()
            if speed > 8 || (speed > 5 && moved) {
                preDepartureDriving = true
                preDepartureLastMoveAt = now
            } else if preDepartureDriving, let last = preDepartureLastMoveAt, now.timeIntervalSince(last) > 10 {
                preDepartureDriving = false
            }
            
            if preDepartureDriving {
                desiredSecondary = String(localized: "已開車（未離場）")
            }
        } else {
            let elapsed = Date().timeIntervalSince(lastVisit.departureDate!)
            if elapsed < 120 {
                visitStatus = "已開車"
            } else {
                visitStatus = "已停留"
            }
        }
        
        if desiredSecondary != visitSecondaryStatus {
            withAnimation(.easeInOut(duration: 0.22)) {
                visitSecondaryStatus = desiredSecondary
            }
        }
    }

    // MARK: - Live Activity sync

    /// 60 秒定時器：定期 push content state，讓 compact trailing 計時器自動更新
    private func startActivitySyncTimer() {
        activitySyncTimer?.invalidate()
        activitySyncTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            syncLiveActivity()
        }
    }

    /// Pushes the current visit state into the system Live Activity.
    private func syncLiveActivity(forceRefresh: Bool = false) {
        // 專注模式（極致）：靈動島凍結喺最後狀態，退出時會 forceRefresh 補返
        guard !focusCutsDetection else { return }
        // visits 尚未載入時不結束活動（冷啟動保護）
        guard locationManager.hasLoadedVisits else { return }
        guard !locationManager.visits.isEmpty else {
            GorillaActivityManager.shared.end()
            return
        }

        let d = Self.appGroupDefaults ?? .standard

        let activityState: GorillaActivityState
        let anchor: Date

        switch visitStatus {
        case "已泊車":
            // 有車位資訊時強制顯示泊車
            activityState = (isNonAutomotiveArrival && !hasParkingSpotData) ? .nonAutomotiveParking : .parking
            anchor = parkingStartTime
        case "已開車":
            activityState = .driving
            anchor = departureTime ?? parkingStartTime
        case "已步行":
            activityState = .walking
            anchor = walkingStartTime ?? departureTime ?? parkingStartTime
        case "已騎車":
            activityState = .cycling
            anchor = cyclingStartTime ?? departureTime ?? parkingStartTime
        default: // 已停留
            activityState = .stationary
            anchor = hasDeparted
                ? (stationaryStartTime ?? departureTime ?? parkingStartTime)
                : parkingStartTime
        }

        var content = GorillaActivityAttributes.ContentState(
            state: activityState, startDate: anchor
        )

        switch activityState {
        case .driving:
            content.speedKmh = Int(locationManager.speed)
            let road = locationManager.currentAddress
            content.road = road.isEmpty ? nil : road
            if let secs = drivingETASeconds {
                content.etaMinutes = max(1, Int(secs / 60))
            }
        case .parking:
            let session = parkingFloorStore.currentSession
            let entry = d.string(forKey: "parkingEntryLocation")
            content.location = session?.locationName ?? ((entry?.isEmpty == false) ? entry : nil)
            content.area = session?.areaCode
            content.floor = session?.floorDisplay
            content.spot = session?.spotNumber
        case .nonAutomotiveParking:
            let session = parkingFloorStore.currentSession
            let entry = d.string(forKey: "parkingEntryLocation")
            content.location = session?.locationName ?? ((entry?.isEmpty == false) ? entry : nil)
            content.area = session?.areaCode
            // Non-automotive: no floor/spot
        case .stationary:
            let session = parkingFloorStore.currentSession
            let entry = d.string(forKey: "parkingEntryLocation")
            content.location = session?.locationName ?? ((entry?.isEmpty == false) ? entry : nil)
            content.area = session?.areaCode
            content.floor = session?.floorDisplay
            content.spot = session?.spotNumber
            // Design row: 目的地 + distance | road | eta
            content.destinationName = destinationManager.selectedDestination?.name
            content.distanceText = drivingDistanceText
            let road = locationManager.currentAddress
            content.road = road.isEmpty ? nil : road
            if let secs = drivingETASeconds {
                content.etaMinutes = max(1, Int(secs / 60))
            }
        case .walking:
            let road = locationManager.currentAddress
            content.road = road.isEmpty ? nil : road
            if let secs = drivingETASeconds {
                content.etaMinutes = max(1, Int(secs / 60))
            }
        case .cycling:
            content.speedKmh = Int(locationManager.speed)
            let road = locationManager.currentAddress
            content.road = road.isEmpty ? nil : road
            if let secs = drivingETASeconds {
                content.etaMinutes = max(1, Int(secs / 60))
            }
        }

        GorillaActivityManager.shared.sync(content, forceRefresh: forceRefresh)
    }

    // 检查GPS位置是否有显著变化（>20米）
    private func isGPSLocationChanged() -> Bool {
        guard let currentLocation = locationManager.manager.location,
              let lastLocation = lastGPSLocation else {
            lastGPSLocation = locationManager.manager.location
            return false
        }
        
        let distance = currentLocation.distance(from: lastLocation)
        if distance > 12 {
            lastGPSLocation = currentLocation
            return true
        }
        return false
    }
    
    // MARK: - Camera Section
    private var cameraSection: some View {
        let camW: CGFloat = isLandscape ? 304 : 338
        let camH: CGFloat = isLandscape ? 211 : 235
        let camCR: CGFloat = isLandscape ? 33 : 37
        return ZStack(alignment: .topLeading) {
            CameraPreviewView(isLandscape: isLandscape, sessionRunning: isCameraActive)
                .frame(width: camW, height: camH)
                .clipShape(RoundedRectangle(cornerRadius: camCR))
                .overlay(
                    RoundedRectangle(cornerRadius: camCR)
                        .stroke(Color.white.opacity(0.6), lineWidth: 4)
                )

            // Black fade overlay — 相機未啟動時顯示，攔截觸控開啟相機
            RoundedRectangle(cornerRadius: camCR)
                .fill(Color.black)
                .frame(width: camW, height: camH)
                .overlay(
                    RoundedRectangle(cornerRadius: camCR)
                        .stroke(Color.white.opacity(0.6), lineWidth: 4)
                )
                .overlay(
                    VStack(spacing: 10) {
                        ZStack {
                            // 底層：整個 symbol（含四角框框）
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 36))
                                .foregroundStyle(.white.opacity(0.6))
                            // 頂層：中央 icon 裁切掉邊框區域
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 36))
                                .foregroundStyle(.white.opacity(0.6))
                                .mask(
                                    RoundedRectangle(cornerRadius: 6)
                                        .frame(width: 20, height: 18)
                                )
                        }
                        // 統一呼吸動畫
                        .opacity(viewfinderBreathe ? 0.45 : 0.7)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: viewfinderBreathe)
                        Text(String(localized: "輕觸以開啟相機"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .opacity(cameraFadeOpacity > 0.5 ? 1 : 0)
                )
                .opacity(cameraFadeOpacity)
                .allowsHitTesting(cameraFadeOpacity > 0.5)
                .onTapGesture {
                    activateCamera()
                }

            cameraDimOverlay
            // 相機未啟動時禁用 hit testing，讓觸控穿透到黑色遮罩
            cameraPhotoStack
            // captureAnimationOverlay — 改用縮略圖自身動畫，避免閃退
            EmptyView()
            cameraButton
                .allowsHitTesting(cameraButtonBlurIn && !showingExpandedPhotos && photoStorage.photos.count < PhotoStorage.maxPhotos)

            // Delete button on selected photo (positioned at photo's top-left corner)
            if let idx = selectedPhotoIndex, idx < photoStorage.photos.count,
               showDeleteButton, deletingPhotoID == nil {
                Button {
                    triggerSmokyDissolve(index: idx)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .glassEffect(.regular, in: .circle)
                }
                .position(x: 40, y: 34)
                .transition(.opacity)
            }

            // Thumbnail-only tap area for expanding (top-left, matching thumb position)
            if !showingExpandedPhotos {
                Color.clear
                    .frame(width: isLandscape ? 72 : 80, height: isLandscape ? 63 : 70)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                            showingExpandedPhotos = true
                            selectedPhotoIndex = nil
                        }
                    }
            }
        }
        .frame(width: camW, height: camH)
    }

    private var cameraDimOverlay: some View {
        let dimOpacity = showingExpandedPhotos ? (selectedPhotoIndex != nil ? 0.65 : 0.45) : 0
        let camW: CGFloat = isLandscape ? 304 : 338
        let camH: CGFloat = isLandscape ? 211 : 235
        let camCR: CGFloat = isLandscape ? 33 : 37
        return Color.black.opacity(dimOpacity)
            .frame(width: camW, height: camH)
            .clipShape(RoundedRectangle(cornerRadius: camCR))
            .animation(.easeInOut(duration: 0.3), value: selectedPhotoIndex)
            .animation(.easeInOut(duration: 0.3), value: showingExpandedPhotos)
            .contentShape(Rectangle())
            .allowsHitTesting(showingExpandedPhotos)
            .onTapGesture {
                guard showingExpandedPhotos else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    if let idx = selectedPhotoIndex {
                        resetTilt(index: idx)
                        selectedPhotoIndex = nil
                    } else {
                        showingExpandedPhotos = false
                        selectedPhotoIndex = nil
                    }
                    tiltAngleX = [:]
                    tiltAngleY = [:]
                }
            }
    }

    private var cameraPhotoStack: some View {
        let photos = photoStorage.photos
        let count = photos.count
        return ZStack {
            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                // Skip by ID — an index-based check would wrongly hide the next
                // photo when indices shift after the deleted one is removed
                if photo.id != deletingPhotoID {
                    let isNewPhoto = photo.id == animatingPhotoID
                    CameraPhotoItem(
                        photo: photo,
                        index: index,
                        totalCount: count,
                        isExpanded: showingExpandedPhotos,
                        isSelected: selectedPhotoIndex == index,
                        tiltX: tiltAngleX[index] ?? 0,
                        tiltY: tiltAngleY[index] ?? 0,
                        isLandscape: isLandscape,
                        swipeOffset: (selectedPhotoIndex == index) ? photoSwipeOffset : 0,
                        isSwiping: selectedPhotoIndex == index && isPhotoSwiping,
                        isAnimatingOut: photoAnimatingOutIndex == index,
                        swipePhotoScale: swipePhotoScale,
                        isSwipingPhoto: isSwipingPhoto,
                        entranceScale: isNewPhoto ? 0.1 : 1.0
                    )
                    .opacity(isNewPhoto ? 0.0 : 1.0)
                    .animation(.timingCurve(0.4, 0.0, 0.2, 1.0, duration: 0.45), value: animatingPhotoID)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                            if showingExpandedPhotos {
                                let wasSelected = selectedPhotoIndex == index
                                if wasSelected {
                                    // Deselect — reset tilt
                                    resetTilt(index: index)
                                    selectedPhotoIndex = nil
                                    showDeleteButton = false
                                } else {
                                    // Select new — reset old, trigger TILT on new
                                    if let oldIdx = selectedPhotoIndex {
                                        resetTilt(index: oldIdx)
                                    }
                                    selectedPhotoIndex = index
                                    triggerTiltEffect(index: index)
                                    // Show delete button after selection settles
                                    showDeleteButton = false
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                            if selectedPhotoIndex == index, deletingPhotoID == nil {
                                                showDeleteButton = true
                                            }
                                        }
                                    }
                                }
                            } else {
                                // 緊湊態：點擊縮圖展開照片堆疊
                                showingExpandedPhotos = true
                                selectedPhotoIndex = nil
                            }
                        }
                    }
                }
            }
            // Smoky Dissolve overlay — inside the same ZStack/frame so positioning matches exactly
            cameraDissolveOverlay
        }
        .frame(width: isLandscape ? 304 : 338, height: isLandscape ? 211 : 235, alignment: .center)
        .mask(
            Group {
                if showingExpandedPhotos {
                    RoundedRectangle(cornerRadius: isLandscape ? 37 : 37)
                } else {
                    Rectangle()
                }
            }
        )
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    guard showingExpandedPhotos, selectedPhotoIndex != nil, photos.count > 1 else { return }
                    let horizontal = value.translation.width
                    let vertical = value.translation.height

                    // Only respond to clear horizontal swipes
                    guard abs(horizontal) > abs(vertical) * 0.5 else { return }

                    let direction: CGFloat = horizontal < 0 ? -1 : 1
                    let nextIndex: Int
                    if horizontal < 0 {
                        nextIndex = ((selectedPhotoIndex ?? 0) + 1) % photos.count
                    } else {
                        nextIndex = ((selectedPhotoIndex ?? 0) - 1 + photos.count) % photos.count
                    }
                    let oldIndex = selectedPhotoIndex ?? 0

                    // Hide delete button immediately
                    withAnimation(.easeOut(duration: 0.15)) {
                        showDeleteButton = false
                    }

                    // ═══════════════════════════════════════════════════════
                    // New photo starts enlarging FIRST
                    // ═══════════════════════════════════════════════════════
                    triggerTiltEffect(index: nextIndex)

                    // ═══════════════════════════════════════════════════════
                    // Phase 1: Slide out + shrink (0.15s after TILT)
                    // ═══════════════════════════════════════════════════════
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        let camH: CGFloat = isLandscape ? 211 : 235
                        let expandedH: CGFloat = 32 * 3.8
                        let fullScale: CGFloat = (camH - 24) / expandedH
                        isSwipingPhoto = true
                        swipePhotoScale = fullScale

                        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                            photoSwipeOffset = direction * 180
                        }
                        withAnimation(.easeOut(duration: 0.8)) {
                            swipePhotoScale = 0.85
                        }
                    }

                    // ═══════════════════════════════════════════════════════
                    // Phase 2: Drop z-index once photo is near the edge
                    // ═══════════════════════════════════════════════════════
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                        photoAnimatingOutIndex = oldIndex
                        isPhotoAnimatingOut = true
                    }

                    // ═══════════════════════════════════════════════════════
                    // Phase 3: Slide back to stack (photo already at stack scale)
                    // ═══════════════════════════════════════════════════════
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                        withAnimation(.spring(response: 0.7, dampingFraction: 0.82)) {
                            photoSwipeOffset = 0
                        }
                        isPhotoSwiping = false
                        isPhotoAnimatingOut = false
                        photoAnimatingOutIndex = nil

                        // Deselect old photo
                        resetTilt(index: oldIndex)
                        selectedPhotoIndex = nextIndex
                        isSwipingPhoto = false
                        swipePhotoScale = 1

                        // Show delete button after settle
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                if selectedPhotoIndex == nextIndex, deletingPhotoID == nil {
                                    showDeleteButton = true
                                }
                            }
                        }
                    }
                }
        )
    }

    // MARK: - Smoky Dissolve overlay — matches selected photo exactly, including in-flight TILT
    private var cameraDissolveOverlay: some View {
        Group {
            if deletingPhotoID != nil, let img = deletingImage {
                let expandedH: CGFloat = 32 * 3.8
                let selectedScale: CGFloat = ((isLandscape ? 211 : 235) - 24) / expandedH
                let delTiltX = tiltAngleX[deletingIndex ?? -1] ?? 0
                let delTiltY = tiltAngleY[deletingIndex ?? -1] ?? 0
                let delTiltScale: CGFloat = 1.0 + abs(delTiltX) * 0.003
                let delTiltShadow: CGFloat = abs(delTiltX) * 0.5
                let delTiltLiftY: CGFloat = -abs(delTiltX) * 0.3
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 46 * 3.8, height: expandedH)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.6), lineWidth: 2.0 / selectedScale)
                    )
                    // Same TILT transform as CameraPhotoItem — seamless handoff
                    .shadow(color: .black.opacity(0.4), radius: delTiltShadow, y: delTiltShadow * 0.5)
                    .scaleEffect(delTiltScale)
                    .offset(y: delTiltLiftY)
                    .rotation3DEffect(.degrees(delTiltX), axis: (x: 1, y: 0, z: 0), perspective: 0.35)
                    .rotation3DEffect(.degrees(delTiltY), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
                    .scaleEffect(selectedScale)
                    .blur(radius: deleteBlur)
                    .opacity(deleteOpacity)
                    .offset(y: deleteOffsetY)
                    .allowsHitTesting(false)
                    .zIndex(200)
            }
        }
    }

    private var captureAnimationOverlay: some View {
        let camW: CGFloat = isLandscape ? 304 : 338
        let camH: CGFloat = isLandscape ? 211 : 235
        let thumbScale: CGFloat = 46.0 / camW
        return VStack(spacing: 0) {
            if animatingPhotoID != nil, let img = animatingPhotoImage {
                let isFinal = animatingPhotoPhase == 1
                let containerScale: CGFloat = isFinal ? thumbScale : 0.1
                let imageScale: CGFloat = isFinal ? 1.0 : 1.2
                let opacity: Double = isFinal ? 1.0 : 0.2
                let cr: CGFloat = isFinal ? 5 : (isLandscape ? 33 : 37)

                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(imageScale)
                    .frame(width: camW, height: camH)
                    .clipShape(RoundedRectangle(cornerRadius: cr))
                    .overlay(
                        RoundedRectangle(cornerRadius: cr)
                            .stroke(Color.white.opacity(0.8), lineWidth: isFinal ? 1.0 / thumbScale : 4)
                    )
                    .scaleEffect(containerScale)
                    .rotationEffect(.degrees(animatingPhotoRotation))
                    .offset(x: animatingPhotoOffsetX, y: animatingPhotoOffsetY)
                    .opacity(opacity)
                    .allowsHitTesting(false)
                    .zIndex(100)
            }
        }
    }

    private var cameraButton: some View {
        let cameraVisible = cameraButtonBlurIn && !showingExpandedPhotos && photoStorage.photos.count < PhotoStorage.maxPhotos
        return Button(action: { capturePhoto() }) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .frame(width: 66, height: 166)
                    .glassEffect(.regular, in: .rect(cornerRadius: 24))
                    .tint(.clear)
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    let t = animationClock.elapsed * 0.3
                    ZStack {
                        Circle()
                            .fill(Color(hex: "3497FF").opacity(0.85))
                            .blur(radius: 18)
                            .frame(width: 112, height: 112)
                            .offset(x: w * 0.5 + CGFloat(sin(t * 0.5)) * w * 0.4 - 56,
                                    y: h * 0.5 + CGFloat(cos(t * 0.4)) * h * 0.35 - 56)
                        Circle()
                            .fill(Color(hex: "FFC46D").opacity(0.85))
                            .frame(width: 124, height: 124)
                            .blur(radius: 18)
                            .offset(x: w * 0.5 + CGFloat(sin(t * 0.4 + 2)) * w * 0.35 - 62,
                                    y: h * 0.5 + CGFloat(cos(t * 0.35 + 2)) * h * 0.3 - 62)
                        Circle()
                            .fill(Color(hex: "FF825C").opacity(0.85))
                            .frame(width: 102, height: 102)
                            .blur(radius: 18)
                            .offset(x: w * 0.5 + CGFloat(sin(t * 0.6 + 4)) * w * 0.38 - 51,
                                    y: h * 0.5 + CGFloat(cos(t * 0.45 + 4)) * h * 0.35 - 51)
                    }
                }
                .frame(width: 57, height: 158)
                .clipShape(.rect(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.white.opacity(0.2), lineWidth: 1.6))
                Image(systemName: "camera.fill")
                    .font(.system(size: 27))
                    .foregroundStyle(.white)
            }
        }
        .scaleEffect(isCapturePressed ? 0.88 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isCapturePressed)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isCapturePressed = pressing
        }, perform: {})
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .padding(.trailing, 10)
        .blur(radius: cameraVisible ? 0 : 12)
        .opacity(cameraVisible ? 1 : 0)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: cameraButtonBlurIn)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: showingExpandedPhotos)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: photoStorage.photos.count)
    }

    // MARK: - GPS Status Badge
    @State private var gpsGlowPhase: CGFloat = 0  // 0 = 脈動起點（出現），1 = 擴散到最外圍

    private var gpsStatusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(gpsColor)
                .frame(width: 8, height: 8)
                .animation(.easeInOut(duration: 0.5), value: gpsColor)
                .phaseAnimator([false, true]) { content, phase in
                    content
                        .scaleEffect(phase ? 0.9 : 0.8)
                } animation: { _ in
                    .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
                }

            ZStack {
                Text("VADY").hidden()
                    .font(.system(size: 12, weight: .medium))
                Text(gpsLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .animation(.easeInOut(duration: 0.5), value: gpsLabel)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .overlay(alignment: .leading) {
            // 光暈：從圓點位置向外擴散，覆蓋膠囊後淡出
            GeometryReader { geo in
                let capsuleWidth = geo.size.width
                // 圓點中心距離 leading edge = 18 (padding) + 4 (半徑)
                let dotCenterX: CGFloat = 22
                // 需要放大多少倍才能覆蓋整個膠囊
                let requiredScale = max(capsuleWidth * 1.5 / 8.0, 20)
                Circle()
                    .fill(gpsColor.opacity(0.5))
                    .frame(width: 8, height: 8)
                    .scaleEffect(gpsGlowPhase * requiredScale)
                    .opacity(gpsGlowPhase < 0.8 ? 0.5 : 0.5 * (1 - (gpsGlowPhase - 0.8) / 0.2))
                    .position(x: dotCenterX, y: geo.size.height / 2)
                    .allowsHitTesting(false)
            }
        }
        .clipShape(.rect(cornerRadius: 22))
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .onChange(of: locationManager.gpsQuality) { _, _ in
            // GPS 狀態變化觸發光暈脈動：出現 → 擴散 → 淡出
            withAnimation(.easeOut(duration: 1.8)) {
                gpsGlowPhase = 1
            }
            // 動畫結束後重置，準備下一次觸發
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) {
                gpsGlowPhase = 0
            }
        }
        .onTapGesture {
            gpsTapCount += 1
            gpsTapResetTimer?.invalidate()
            if gpsTapCount >= 5 {
                gpsTapCount = 0
                withAnimation(.easeInOut(duration: 0.3)) {
                    hkDetailMode.toggle()
                }
            } else {
                gpsTapResetTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
                    gpsTapCount = 0
                }
            }
        }
    }

    private var gpsColor: Color {
        let base: Color
        switch locationManager.gpsQuality {
        case .good: base = .green
        case .poor: base = .yellow
        case .bad: base = .red
        case .unknown: base = .gray
        }
        // 黑武士模式：降低飽和度，用金色調
        if darkKnightMode {
            return Color(hex: "FFC46D") ?? base
        }
        return base
    }

    private var gpsLabel: String {
        switch locationManager.gpsQuality {
        case .good: return String(localized: "GPS Ready")
        case .poor: return String(localized: "GPS Weak")
        case .bad: return String(localized: "GPS Lost")
        case .unknown: return String(localized: "GPS Waiting")
        }
    }
    
    // MARK: - Entrance Effect
    private func triggerEntranceEffect() {
        let startTime = Date()
        Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { timer in
            MainActor.assumeIsolated {
                let t = Date().timeIntervalSince(startTime)
                let duration: Double = 3.0
                if t < duration {
                    let u = t / duration
                    animationClock.speedMultiplier = 1 + (5.0 - 1) * pow(1 - u, 2)
                } else {
                    animationClock.speedMultiplier = 1.0
                    timer.invalidate()
                }
            }
        }
    }
    
    // MARK: - TILT center-lift trigger
    /// Triggers a center-lift animation on the selected photo.
    /// Phase 1: center rises sharply (like grabbing the middle of a towel).
    /// Phase 2: corners catch up — paper settles flat with a bounce.
    private func triggerTiltEffect(index: Int) {
        // Phase 1: gentle lift — slower response so it enlarges gradually
        withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) {
            tiltAngleX[index] = -18
            tiltAngleY[index] = Double.random(in: -8...8)
        }
        // Phase 2: settle flat — longer response for a leisurely bounce
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                self.tiltAngleX[index] = 0
                self.tiltAngleY[index] = 0
            }
        }
    }

    private func resetTilt(index: Int) {
        tiltAngleX[index] = 0
        tiltAngleY[index] = 0
    }

    // MARK: - Smoky Dissolve delete — dissolve → 0.5s → remove + auto-select next
    private func triggerSmokyDissolve(index: Int) {
        guard index < photoStorage.photos.count else { return }
        let photo = photoStorage.photos[index]
        let targetID = photo.id
        // Snapshot the image — deletePhoto evicts cache AND deletes file
        deletingImage = photo.image
        deletingPhotoID = targetID
        deletingIndex = index
        showDeleteButton = false
        // Do NOT reset tilt — the overlay reads live values and settles naturally

        // Start dissolve animation
        withAnimation(.easeInOut(duration: 0.85)) {
            deleteBlur = 20
            deleteOpacity = 0
            deleteOffsetY = 25
        }

        // After 0.5s — dissolve is ~87% done (opacity ≈ 0.13)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                // Remove photo from storage
                photoStorage.deletePhoto(photo)
                // Remove this photo's parking info contribution
                self.parkingPhotoContributions.removeValue(forKey: targetID)
                self.mergeAndDisplayParkingInfo()
                self.saveParkingContributions()
                // Re-index tilt dicts
                let idx = index
                var newTiltAngleX: [Int: Double] = [:]
                var newTiltAngleY: [Int: Double] = [:]
                for (k, v) in tiltAngleX where k < idx {
                    newTiltAngleX[k] = v
                }
                for (k, v) in tiltAngleX where k > idx {
                    newTiltAngleX[k - 1] = v
                }
                for (k, v) in tiltAngleY where k < idx {
                    newTiltAngleY[k] = v
                }
                for (k, v) in tiltAngleY where k > idx {
                    newTiltAngleY[k - 1] = v
                }
                tiltAngleX = newTiltAngleX
                tiltAngleY = newTiltAngleY
                // Auto-select the next photo (the one that shifts into the deleted slot)
                if photoStorage.photos.isEmpty {
                    selectedPhotoIndex = nil
                    showingExpandedPhotos = false
                } else {
                    selectedPhotoIndex = min(idx, photoStorage.photos.count - 1)
                }
            }
            // TILT flourish on the auto-selected photo
            if !photoStorage.photos.isEmpty {
                let newIdx = min(index, photoStorage.photos.count - 1)
                triggerTiltEffect(index: newIdx)
                // Show delete button after selection settles
                showDeleteButton = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        if selectedPhotoIndex != nil, deletingPhotoID == nil {
                            showDeleteButton = true
                        }
                    }
                }
            }
            // Clean up dissolve state
            deletingPhotoID = nil
            deletingIndex = nil
            deletingImage = nil
            deleteBlur = 0
            deleteOpacity = 1.0
            deleteOffsetY = 0
        }
    }
}

extension Notification.Name {
    static let captureParkingPhoto = Notification.Name("captureParkingPhoto")
    static let timePhasePreviewChanged = Notification.Name("timePhasePreviewChanged")
}

// MARK: - Camera Preview
struct CameraPreviewView: UIViewRepresentable {
    var isLandscape: Bool = false
    var sessionRunning: Bool = true
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black

        #if targetEnvironment(simulator)
        let label = UILabel()
        label.text = "📷"
        label.font = .systemFont(ofSize: 48)
        label.textAlignment = .center
        label.frame = view.bounds
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(label)
        return view
        #else
        let session = AVCaptureSession()
        session.sessionPreset = .iFrame1280x720

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return view
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        let output = AVCapturePhotoOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
        }

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        let camW: CGFloat = isLandscape ? 304 : 338
        let camH: CGFloat = isLandscape ? 211 : 235
        previewLayer.cornerRadius = isLandscape ? 33 : 37
        previewLayer.masksToBounds = true
        previewLayer.frame = CGRect(x: 0, y: 0, width: camW, height: camH)

        // 横屏时设置真正的横屏输出方向（不再旋转）
        if isLandscape, let connection = previewLayer.connection {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .landscapeRight
            }
        }

        view.layer.addSublayer(previewLayer)
        view.clipsToBounds = true

        context.coordinator.session = session
        context.coordinator.previewLayer = previewLayer
        context.coordinator.output = output
        context.coordinator.isLandscape = isLandscape

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }

        return view
        #endif
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.isLandscape = isLandscape
        // Stop/start session based on active state
        if sessionRunning {
            if let session = context.coordinator.session, !session.isRunning {
                DispatchQueue.global(qos: .userInitiated).async {
                    session.startRunning()
                }
            }
        } else {
            if let session = context.coordinator.session, session.isRunning {
                DispatchQueue.global(qos: .userInitiated).async {
                    session.stopRunning()
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject {
        var session: AVCaptureSession?
        var previewLayer: AVCaptureVideoPreviewLayer?
        var output: AVCapturePhotoOutput?
        var isLandscape: Bool = false

        override init() {
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleCapture),
                name: .captureParkingPhoto,
                object: nil
            )
        }

        @objc private func handleCapture() {
            capturePhoto()
        }

        func capturePhoto() {
            guard let output = output else { return }
            // 横屏时设置拍照输出方向
            if let connection = output.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = isLandscape ? .landscapeRight : .portrait
                }
            }
            let settings = AVCapturePhotoSettings()
            output.capturePhoto(with: settings, delegate: CameraPhotoDelegate.shared)
        }
    }
}

class CameraPhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    static let shared = CameraPhotoDelegate()
    var photoCaptured: ((UIImage) -> Void)?

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .parkingPhotoCaptured,
                object: image
            )
        }
    }
}

extension Notification.Name {
    static let parkingPhotoCaptured = Notification.Name("parkingPhotoCaptured")
}
// MARK: - Camera Photo Item
struct CameraPhotoItem: View {
    let photo: ParkingPhoto
    let index: Int
    let totalCount: Int
    let isExpanded: Bool
    let isSelected: Bool
    var tiltX: Double = 0
    var tiltY: Double = 0
    var isLandscape: Bool = false
    var swipeOffset: CGFloat = 0  // Horizontal offset during swipe gesture
    var isSwiping: Bool = false  // Whether currently being swiped (old, kept for compat)
    var isAnimatingOut: Bool = false  // Whether animating to bottom after release
    var swipePhotoScale: CGFloat = 1  // Explicit scale for swiping photo
    var isSwipingPhoto: Bool = false  // Whether photo is actively being swiped out
    var entranceScale: CGFloat = 1   // 入場動畫縮放（新照片用）

    private let baseW: CGFloat = 46
    private let baseH: CGFloat = 32
    private let expandedW: CGFloat = 46 * 3.8
    private let expandedH: CGFloat = 32 * 3.8
    private var thumbOffsetX: CGFloat {
        -(cameraWidth / 2 - 20 - 46 / 2)
    }
    private var thumbOffsetY: CGFloat {
        -(cameraHeight / 2 - 18 - 32 / 2)
    }
    private var cameraWidth: CGFloat { isLandscape ? 304 : 338 }
    private var cameraHeight: CGFloat { isLandscape ? 211 : 235 }

    // TILT helpers — center-lift effect
    private var tiltScale: CGFloat {
        1.0 + abs(tiltX) * 0.003
    }
    private var tiltShadow: CGFloat {
        abs(tiltX) * 0.5
    }
    private var tiltLiftY: CGFloat {
        -abs(tiltX) * 0.3
    }

    var body: some View {
        if let img = photo.image {
            let photoW = isExpanded ? expandedW : baseW
            let photoH = isExpanded ? expandedH : baseH
            let selectedScale: CGFloat = (cameraHeight - 24) / expandedH
            // Swipe scale: if this photo is being swiped, use explicit swipePhotoScale
            let isThisSwiping = isSelected && isSwipingPhoto
            let photoScale: CGFloat = {
                if isThisSwiping { return swipePhotoScale }
                let base = isSelected ? selectedScale : (isExpanded ? 0.85 : 1.0)
                return base * entranceScale
            }()

            let finalOffsetX: CGFloat = {
                if isSelected {
                    return swipeOffset
                }
                if isExpanded {
                    let raw = CGFloat(photo.offsetX) * 22
                    let maxX: CGFloat = (cameraWidth - expandedW) / 2 - 12
                    return max(-maxX, min(maxX, raw))
                }
                return thumbOffsetX + CGFloat(photo.offsetX)
            }()
            let finalOffsetY: CGFloat = {
                if isSelected { return 0 }
                if isExpanded {
                    let raw = CGFloat(photo.offsetY) * 12
                    let maxY: CGFloat = (235 - expandedH) / 2 - 5
                    return max(-maxY, min(maxY, raw))
                }
                return thumbOffsetY + CGFloat(photo.offsetY)
            }()
            let finalRotation: CGFloat = {
                if isSelected { return 0 }
                if isExpanded {
                    let normX = max(-1, min(1, CGFloat(photo.offsetX) / 6))
                    return normX * 12
                }
                return CGFloat(photo.rotation)
            }()

            let borderW: CGFloat = isSelected ? 2.0 / selectedScale : (isExpanded ? 1.5 : 1.0)
            let borderOpacity: Double = 0.6
            let cr: CGFloat = isSelected ? 12 : (isExpanded ? 5 * 3.8 : 5)
            // Z-index logic: use index-based ordering (index = stack order)
            let zIdx: Double = {
                if isAnimatingOut {
                    return 0  // Photo is animating to bottom — always lowest
                }
                if isSelected {
                    return 100  // Selected photo on top
                }
                return Double(index)  // Normal stack order
            }()

            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: photoW, height: photoH)
                .clipShape(RoundedRectangle(cornerRadius: cr))
                .contentShape(RoundedRectangle(cornerRadius: cr))
                .overlay(
                    RoundedRectangle(cornerRadius: cr)
                        .stroke(Color.white.opacity(borderOpacity), lineWidth: borderW)
                )
                // Center-lift TILT: shadow grows, scale rises, slight upward offset
                .shadow(color: .black.opacity(0.4), radius: tiltShadow, y: tiltShadow * 0.5)
                .scaleEffect(tiltScale)
                .offset(y: tiltLiftY)
                .rotation3DEffect(.degrees(tiltX), axis: (x: 1, y: 0, z: 0), perspective: 0.35)
                .rotation3DEffect(.degrees(tiltY), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
                // Existing transforms
                .rotationEffect(.degrees(finalRotation))
                .offset(x: finalOffsetX, y: finalOffsetY)
                .scaleEffect(photoScale)
                .zIndex(zIdx)
                .animation(.spring(response: 0.45, dampingFraction: 0.82).delay(Double(totalCount - 1 - index) * 0.06), value: isExpanded)
                .animation(.spring(response: 0.4, dampingFraction: 0.82).delay(Double(totalCount - 1 - index) * 0.06), value: isSelected)
        }
    }
}

// MARK: - Custom TextView
struct EnterDismissTextView: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = UIFont.systemFont(ofSize: 16)
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        
        let isDark = context.environment.colorScheme == .dark
        if text.isEmpty {
            textView.text = placeholder
            textView.textColor = isDark ? .white.withAlphaComponent(0.3) : .black.withAlphaComponent(0.3)
        } else {
            textView.textColor = isDark ? .white : .black
        }
        
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        let isDark = context.environment.colorScheme == .dark
        if !context.coordinator.isEditing {
            if text.isEmpty {
                uiView.text = placeholder
                uiView.textColor = isDark ? .white.withAlphaComponent(0.3) : .black.withAlphaComponent(0.3)
            } else {
                uiView.text = text
                uiView.textColor = isDark ? .white : .black
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: EnterDismissTextView
        var isEditing = false
        
        init(_ parent: EnterDismissTextView) {
            self.parent = parent
        }
        
        func textViewDidBeginEditing(_ textView: UITextView) {
            isEditing = true
            let isDark = textView.traitCollection.userInterfaceStyle == .dark
            if textView.text == parent.placeholder {
                textView.text = ""
                textView.textColor = isDark ? .white : .black
            }
        }
        
        func textViewDidEndEditing(_ textView: UITextView) {
            isEditing = false
            let isDark = textView.traitCollection.userInterfaceStyle == .dark
            if textView.text.isEmpty {
                textView.text = parent.placeholder
                textView.textColor = isDark ? .white.withAlphaComponent(0.3) : .black.withAlphaComponent(0.3)
            }
        }
        
        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }
        
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n" {
                textView.resignFirstResponder()
                return false
            }
            return true
        }
    }
}

struct AnimatedCheckmarkView: View {
    @State private var animationProgress: CGFloat = 0
    
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 8, y: 22))
            path.addLine(to: CGPoint(x: 18, y: 32))
            path.addLine(to: CGPoint(x: 36, y: 12))
        }
        .trim(from: 0, to: animationProgress)
        .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        .frame(width: 44, height: 44)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5)) {
                animationProgress = 1.0
            }
        }
    }
}

// MARK: - Spot Editor Sheet
struct SpotEditorSheet: View {
    @Binding var spotNumber: String
    @Binding var areaCode: String
    @Binding var floorText: String
    var onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var floorIndex: Int = 0

    var body: some View {
        NavigationStack {
            List {
                Section(header: Label("車位資訊", systemImage: "car.fill")) {
                    HStack {
                        Text("車位")
                            .frame(width: 50, alignment: .leading)
                        TextField("例如 A12", text: $spotNumber)
                            .textInputAutocapitalization(.characters)
                    }
                    HStack {
                        Text("區域")
                            .frame(width: 50, alignment: .leading)
                        TextField("例如 B區", text: $areaCode)
                            .textInputAutocapitalization(.characters)
                    }
                }

                Section(header: Label("樓層", systemImage: "building.2")) {
                    HStack {
                        Text("樓層文字")
                            .frame(width: 70, alignment: .leading)
                        TextField("例如 B2", text: $floorText)
                            .textInputAutocapitalization(.characters)
                    }

                    HStack {
                        Text("樓層指數")
                            .frame(width: 70, alignment: .leading)
                        Stepper("\(floorIndex)", value: $floorIndex, in: -10...50)
                    }
                }
            }
            .navigationTitle("修改車位資訊")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("確認") {
                        floorText = floorText.isEmpty ? "\(floorIndex)" : floorText
                        onSave()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                let parsed = Self.parseFloorText(floorText)
                floorIndex = parsed
            }
        }
        .presentationDetents([.medium])
    }

    private static func parseFloorText(_ text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespaces).uppercased()
        if trimmed == "G" || trimmed == "GF" || trimmed == "LG" { return 0 }
        if trimmed.hasPrefix("B") {
            let num = trimmed.dropFirst()
            if let n = Int(num) { return -n }
        }
        if let n = Int(trimmed) { return n }
        return 0
    }
}

// MARK: - Blur Transition
private struct BlurModifier: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View {
        content.blur(radius: radius)
    }
}

extension AnyTransition {
    static func blurReplace(active: AnyTransition = .opacity, combinedWith extra: AnyTransition = .identity) -> AnyTransition {
        .modifier(active: BlurModifier(radius: 12), identity: BlurModifier(radius: 0))
            .combined(with: active)
            .combined(with: extra)
    }

    static var blurFade: AnyTransition {
        .opacity.combined(with: .modifier(
            active: BlurModifier(radius: 8),
            identity: BlurModifier(radius: 0)
        ))
    }
}

// MARK: - Vehicle Data Model
struct VehicleBrand: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let models: [String]
    let color: Color
    let iconName: String
}

struct VehiclePickerView: View {
    @Binding var selectedBrand: String
    @Binding var selectedModel: String
    @Binding var selectedColor: Color
    @Environment(\.dismiss) private var dismiss
    @State private var selectedBrandIndex: Int = 0
    @State private var selectedModelIndex: Int = 0

    let brands: [VehicleBrand] = [
        // 德系
        VehicleBrand(name: "BMW", models: ["X1", "X3", "X5", "X7", "3 Series", "5 Series", "7 Series", "M3", "M4", "M5"], color: Color(red: 0.0, green: 0.4, blue: 0.8), iconName: "suv.side.fill"),
        VehicleBrand(name: "Mercedes-Benz", models: ["A-Class", "C-Class", "E-Class", "S-Class", "GLC", "GLE", "GLS", "AMG GT", "EQS"], color: Color(red: 0.0, green: 0.2, blue: 0.4), iconName: "suv.side.fill"),
        VehicleBrand(name: "Audi", models: ["A3", "A4", "A6", "A8", "Q3", "Q5", "Q7", "Q8", "e-tron", "RS6"], color: Color(red: 0.1, green: 0.1, blue: 0.1), iconName: "suv.side.fill"),

        // 中國新勢力
        VehicleBrand(name: "小米", models: ["SU7", "SU7 Pro", "SU7 Max", "YU7"], color: Color(red: 1.0, green: 0.4, blue: 0.0), iconName: "suv.side.fill"),
        VehicleBrand(name: "蔚來", models: ["ET5", "ET7", "ES6", "ES7", "ES8", "EC6", "EC7", "EP9"], color: Color(red: 0.0, green: 0.6, blue: 0.9), iconName: "suv.side.fill"),
        VehicleBrand(name: "小鵬", models: ["P7", "P7+", "G6", "G9", "X9", "MONA M03"], color: Color(red: 0.0, green: 0.8, blue: 0.4), iconName: "suv.side.fill"),
        VehicleBrand(name: "理想", models: ["L6", "L7", "L8", "L9", "MEGA"], color: Color(red: 0.2, green: 0.6, blue: 1.0), iconName: "suv.side.fill"),

        // 日系
        VehicleBrand(name: "豐田", models: ["埃爾法", "威爾法", "Camry", "Corolla", "RAV4", "Land Cruiser", "Prius", "Supra", "86"], color: Color(red: 0.8, green: 0.0, blue: 0.0), iconName: "suv.side.fill"),
        VehicleBrand(name: "本田", models: ["Accord", "Civic", "CR-V", "HR-V", "Pilot", "NSX", "Type R"], color: Color(red: 0.7, green: 0.0, blue: 0.0), iconName: "suv.side.fill"),
        VehicleBrand(name: "日產", models: ["GT-R", "370Z", "Altima", "Maxima", "Pathfinder", "Patrol", "Ariya"], color: Color(red: 0.9, green: 0.0, blue: 0.0), iconName: "suv.side.fill"),
        VehicleBrand(name: "馬自達", models: ["MX-5", "Mazda3", "Mazda6", "CX-5", "CX-30", "CX-50", "CX-90"], color: Color(red: 0.8, green: 0.2, blue: 0.0), iconName: "suv.side.fill"),
        VehicleBrand(name: "斯巴魯", models: ["WRX", "BRZ", "Outback", "Forester", "Crosstrek", "Ascent"], color: Color(red: 0.0, green: 0.3, blue: 0.7), iconName: "suv.side.fill"),

        // 英系
        VehicleBrand(name: "Mini", models: ["Cooper", "Cooper S", "Clubman", "Countryman", "John Cooper Works", "Electric"], color: Color(red: 0.0, green: 0.5, blue: 0.0), iconName: "suv.side.fill"),
        VehicleBrand(name: "Land Rover", models: ["Defender", "Discovery", "Range Rover", "Range Rover Sport", "Range Rover Evoque", "Velar"], color: Color(red: 0.0, green: 0.4, blue: 0.3), iconName: "suv.side.fill"),
        VehicleBrand(name: "Jaguar", models: ["F-Type", "XF", "XJ", "F-Pace", "E-Pace", "I-Pace"], color: Color(red: 0.6, green: 0.0, blue: 0.0), iconName: "suv.side.fill"),

        // 美系
        VehicleBrand(name: "Ford", models: ["野馬 Mustang", "F-150", "Bronco", "Explorer", "Mach-E", "GT"], color: Color(red: 0.0, green: 0.3, blue: 0.8), iconName: "suv.side.fill"),
        VehicleBrand(name: "Chevrolet", models: ["Corvette", "Camaro", "Silverado", "Tahoe", "Suburban", "Bolt"], color: Color(red: 0.8, green: 0.7, blue: 0.0), iconName: "suv.side.fill"),
        VehicleBrand(name: "Tesla", models: ["Model 3", "Model Y", "Model S", "Model X", "Cybertruck", "Roadster"], color: Color(red: 0.8, green: 0.0, blue: 0.0), iconName: "suv.side.fill"),

        // 中國傳統
        VehicleBrand(name: "廣汽埃安", models: ["Aion S", "Aion S Plus", "Aion V", "Aion Y", "Aion LX", "Hyper SSR"], color: Color(red: 0.0, green: 0.6, blue: 0.8), iconName: "suv.side.fill"),
        VehicleBrand(name: "比亞迪", models: ["漢", "唐", "宋", "秦", "海豚", "海鷗", "仰望 U8"], color: Color(red: 0.0, green: 0.4, blue: 0.6), iconName: "suv.side.fill"),

        // 韓系
        VehicleBrand(name: "現代", models: ["IONIQ 5", "IONIQ 6", "Tucson", "Santa Fe", "Palisade", "N"], color: Color(red: 0.0, green: 0.3, blue: 0.6), iconName: "suv.side.fill"),
        VehicleBrand(name: "起亞", models: ["EV6", "EV9", "Sportage", "Sorento", "Telluride", "Stinger"], color: Color(red: 0.8, green: 0.0, blue: 0.2), iconName: "suv.side.fill"),
    ]

    var body: some View {
        NavigationStack {
            List {
                // Brand selection
                Section(header: Text("選擇品牌")) {
                    ForEach(Array(brands.enumerated()), id: \.element.id) { index, brand in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedBrandIndex = index
                                selectedModelIndex = 0
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(brand.color)
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Image(systemName: brand.iconName)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundStyle(.white)
                                    )
                                Text(brand.name)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedBrandIndex == index {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(brand.color)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Model selection
                Section(header: Text("選擇型號")) {
                    ForEach(Array(brands[selectedBrandIndex].models.enumerated()), id: \.element) { index, model in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedModelIndex = index
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Text(model)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedModelIndex == index {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(brands[selectedBrandIndex].color)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("選擇車輛")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("確認") {
                        selectedBrand = brands[selectedBrandIndex].name
                        selectedModel = brands[selectedBrandIndex].models[selectedModelIndex]
                        selectedColor = brands[selectedBrandIndex].color
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                // Set initial selection based on current values
                if let brandIndex = brands.firstIndex(where: { $0.name == selectedBrand }) {
                    selectedBrandIndex = brandIndex
                    if let modelIndex = brands[brandIndex].models.firstIndex(of: selectedModel) {
                        selectedModelIndex = modelIndex
                    }
                }
            }
        }
    }
}
