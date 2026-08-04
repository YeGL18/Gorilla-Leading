import SwiftUI
import FoundationModels
import Speech
import Accelerate
import MapKit
import AVFoundation
import WidgetKit

struct ContentView: View {
    private struct CapsuleDragState: Equatable {
        var mode: Int = 0
        var offset: CGFloat = 0
        var active: Bool = false
    }

    @StateObject private var viewModel = TranslationViewModel()
    @StateObject private var historyManager = HistoryManager()
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @StateObject private var animationClock = AnimationClock()
    @StateObject private var timePhaseManager = TimePhaseManager()
    @StateObject private var photoStorage = PhotoStorage()
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var destinationManager: DestinationManager
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var showingLanguagePicker = false
    @State private var selectingSource = true
    @State private var isRecording = false
    @State private var selectedTab: Int = 1
    @State private var hasPlayedEntrance = false
    @State private var isVoiceRecording = false
    @State private var revealedCount = 0
    @State private var sparklePhase = false
    @FocusState private var isInputFocused: Bool
    @State private var isKeyboardVisible = false
    @State private var showMap = false
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
    @State private var isParkingMemoryExpanded = false
    @State private var etaText: String?
    @State private var isLandscape = false
    @State private var drivingDistanceText: String?
    @State private var capsuleScale: CGFloat = 1.0
    @State private var capsuleOnRight: Bool = false
    @State private var orbOpacity: Double = 1.0
    @GestureState private var capsuleDragState: CapsuleDragState = CapsuleDragState()
    @State private var capsuleSettleHeight: CGFloat? = nil
    @State private var capsuleSettleWorkItem: DispatchWorkItem?
    @State private var capsuleAppeared = false
    @State private var roseLoopSpeed: Double = 1.0
    @State private var roseOpacity: Double = 1.0
    @State private var roseBlurRadius: Double = 0.0
    @State private var addressRevealProgress: Double = 0.0
    @State private var parkingEntryTime: Date = Date()
    @State private var parkingTimer: Timer?
    @State private var parkingElapsed: TimeInterval = 0
    @State private var parkingCountdown: Int?
    @State private var departureTimer: Timer?
    @State private var departureElapsedTimer: Timer?
    @State private var capsuleUpdateTimer: Timer?
    @State private var stationaryTimer: Timer?
    @State private var stationaryStartTime: Date?
    @State private var stationaryElapsed: TimeInterval = 0
    @State private var showCheckmarkAnimation = false
    @State private var departureTimerID: UUID?
    @State private var departureElapsed: TimeInterval = 0
    @State private var manualDeparted = false
    @State private var parkingDeparted = false
    @State private var hasDeparted = false
    @State private var parkingStartTime: Date = Date()
    @State private var capsuleDuration: TimeInterval = 0
    @State private var lastKnownArrivalDate: Date?
    @State private var timerRunning = false
    @State private var animatingPhotoID: UUID?
    @State private var animatingPhotoImage: UIImage?
    @State private var isCapturing = false
    @State private var showingExpandedPhotos = false
    @State private var selectedPhotoIndex: Int?
    @State private var showDeleteButton = false
    @State private var isCapturePressed = false
    @State private var showingAddDestination = false
    @State private var showingRoute = false
    @State private var routePolyline: MKPolyline?
    @State private var routeAnimationPolyline: MKPolyline?
    @State private var departureTime: Date?
    @State private var showDepartedLabel = false
    @State private var followHeading = true
    @State private var stationaryTrackingTrigger = 0
    @State private var northOverrideTrackingToken = 0
    @State private var showSpeedInfo = false
    @State private var speedInfoTimer: Timer?
    @State private var randomInfoTimer: Timer?
    @State private var lastGPSLocation: CLLocation?
    @State private var lastMovementTime: Date?
    @State private var timeAdjustText: String?
    @State private var timeAdjustAccumulated: Int = 0
    @State private var drivingETASeconds: TimeInterval?
    @State private var visitStatus: String = "已停留"
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
            if !departed {
                _parkingStartTime = State(initialValue: savedTime)
                _parkingEntryTime = State(initialValue: savedTime)
                _hasDeparted = State(initialValue: false)
                _capsuleDuration = State(initialValue: Date().timeIntervalSince(savedTime))
                _parkingElapsed = State(initialValue: Date().timeIntervalSince(savedTime))
                _timerRunning = State(initialValue: false)
                _lastKnownArrivalDate = State(initialValue: defaults.object(forKey: "lastKnownArrivalDate") as? Date)
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
        TabView(selection: $selectedTab) {
            SpeedView(showMap: showMap, animationClock: animationClock, mapCamera: $mapCamera)
                .environment(\.colorScheme, effectiveColorScheme)
                .tabItem {
                    Label("Speed", systemImage: "speedometer")
                }
                .tag(0)
            
            NavigationStack {
                homeContent
                    .animation(.easeInOut(duration: 0.25), value: isKeyboardVisible)
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isKeyboardVisible = true
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isKeyboardVisible = false
                        }
                    }
            }
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }
            .tag(1)
            .onAppear {
                animationClock.start()
                guard !hasPlayedEntrance else { return }
                hasPlayedEntrance = true
                triggerEntranceEffect()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.easeOut(duration: 1.2)) {
                        capsuleAppeared = true
                    }
                }
            }
            
            SettingsView()
                .environment(\.colorScheme, effectiveColorScheme)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(2)
        }
        .preferredColorScheme(resolvedColorScheme)
        .onAppear {
            animationClock.start()
            timePhaseManager.start()
            UIApplication.shared.isIdleTimerDisabled = true
            if !timerRunning && lastKnownArrivalDate != nil {
                startPersistentTimer()
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .parkingPhotoCaptured)) { notification in
            if let photo = notification.object as? UIImage {
                guard photoStorage.photos.count < PhotoStorage.maxPhotos else { return }
                if let saved = photoStorage.savePhoto(photo) {
                    startCaptureAnimation(photo: photo)
                }
            }
        }
        .onReceive(locationManager.$lastLocation) { location in
            guard let location = location else { return }
            timePhaseManager.fetchSunTimes(for: location.coordinate)
        }
        .onReceive(locationManager.$lastLocation) { location in
            guard let location = location else { return }
            guard showingRoute, let polyline = routePolyline else { return }
            guard locationManager.speed >= 15 else { return }
            if isRerouting { return }
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
            guard !manualDeparted else { return }

            if lastVisit.departureDate != nil {
                // 到訪結束：自動停止計時
                if timerRunning && lastKnownArrivalDate == lastVisit.arrivalDate {
                    timerRunning = false
                    parkingTimer?.invalidate()
                    parkingTimer = nil
                    hasDeparted = true
                    departureTime = lastVisit.departureDate
                    showDepartedLabel = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
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
                    departureElapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                        guard hasDeparted, let d = departureTime else { return }
                        let e = Date().timeIntervalSince(d)
                        DispatchQueue.main.async {
                            departureElapsed = e
                        }
                    }
                }
            } else {
                // 新的到訪：自動開始計時
                let newArrival = lastVisit.arrivalDate
                if lastKnownArrivalDate != newArrival && !hasDeparted {
                    lastKnownArrivalDate = newArrival
                    parkingEntryTime = newArrival
                    parkingStartTime = newArrival
                    capsuleDuration = 0
                    parkingElapsed = 0
                    hasDeparted = false
                    timerRunning = false
                    departureElapsedTimer?.invalidate()
                    departureElapsedTimer = nil
                    startPersistentTimer()
                }
            }
        }
        .onChange(of: isParkingMemoryExpanded) { _, expanded in
            if expanded {
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
            }
        }
        .onChange(of: selectedPhotoIndex) { _, newIndex in
            if newIndex != nil {
                showDeleteButton = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showDeleteButton = true
                    }
                }
            } else {
                showDeleteButton = false
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
                        }
                    } else {
                        roseLoopSpeed = 1.0
                        roseOpacity = 1.0
                        roseBlurRadius = 0
                        withAnimation(.easeInOut(duration: 0.25)) {
                            addressRevealProgress = 0
                        }
                    }
                }
            ZStack {
            if showMap {
                VignetteMapView(savedRegion: $mapRegion, savedCamera: $mapCamera, firstFlyTrigger: $firstMapFlyTrigger, stationaryTrackingTrigger: stationaryTrackingTrigger, northOverrideTrackingToken: northOverrideTrackingToken, routeOverlay: routePolyline, routeAnimationOverlay: routeAnimationPolyline, followHeading: followHeading, routePriorityToken: routePriorityToken, routePriorityAnchor: routePriorityAnchor, routeOverlayToken: routeOverlayToken, routeOverlayAnimationToken: routeOverlayAnimationToken)
                    .ignoresSafeArea()
            } else {
                AnimatedBackground(clock: animationClock, colorSchemeIndex: colorSchemeIndex, isVoiceRecording: isVoiceRecording, orbEnabled: orbMasterEnabled && orbBackgroundHome, useTimeBasedOrb: orbMasterEnabled && orbBackgroundHome && useTimeBasedOrb, phaseManager: timePhaseManager)
                    .ignoresSafeArea()
            }

            ZStack {
                VStack(spacing: 0) {
                    HStack(alignment: .center) {
                        Text("Gorilla Leading")
                            .font(.largeTitle.bold())
                            .foregroundStyle(adaptiveTextColor())
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

                    let buttonOffset: CGFloat = !isLandscape ? (isParkingMemoryExpanded ? -408 : (isCapsuleExpanded ? -140 : 0)) : 0
                    let landscapeButtonOffset: CGFloat = (isLandscape && showMap) ? 20 : 0
                    HStack {
                        VStack(spacing: 10) {
                            if showMap {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        followHeading.toggle()
                                    }
                                } label: {
                                    Image(systemName: followHeading ? "location.north.fill" : "location.north")
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundStyle(followHeading ? adaptiveTextColor() : adaptiveTextColor(opacity: 0.5))
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.glass)
                                .transition(.blurReplace())
                            }

                            Menu {
                                Button {
                                    showingAddDestination = true
                                } label: {
                                    Label("新增目的地", systemImage: "plus")
                                }

                                if !destinationManager.destinations.isEmpty {
                                    Divider()
                                    ForEach(destinationManager.destinations) { destination in
                                        Button {
                                            destinationManager.selectDestination(destination)
                                            if isCapsuleExpanded {
                                                refreshETA()
                                            }
                                            if showingRoute {
                                                recalculateRoute()
                                            }
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
                                    showMap.toggle()
                                }
                            }) {
                                Image(systemName: showMap ? "map.fill" : "map")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(adaptiveTextColor())
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.glass)
                        }
                        .padding(.leading, 16)
                        .padding(.bottom, 72)
                        .offset(y: buttonOffset + landscapeButtonOffset)

                        Spacer()
                    }
                }
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
                            guard isLandscape && (isCapsuleExpanded || isParkingMemoryExpanded) else { return }
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
        .sheet(isPresented: $showingLanguagePicker) {
            LanguagePickerView(
                languages: Language.allCases,
                selectedLanguage: selectingSource ? viewModel.sourceLanguage : viewModel.targetLanguage,
                onSelect: { language in
                    if selectingSource {
                        viewModel.sourceLanguage = language
                    } else {
                        viewModel.targetLanguage = language
                    }
                    showingLanguagePicker = false
                },
                isPresented: $showingLanguagePicker
            )
        }
        .sheet(isPresented: $showingAddDestination) {
            AddDestinationView()
                .environmentObject(destinationManager)
                .environmentObject(locationManager)
        }
        }
    }

    // MARK: - Address Capsule
    private var addressCapsule: some View {
        let baseHeight: CGFloat = isParkingMemoryExpanded ? 450 : (isCapsuleExpanded ? 182 : 44)
        let capsuleHeight: CGFloat = {
            if isParkingMemoryExpanded {
                return isLandscape ? 296 : 450
            }
            let raw: CGFloat
            if capsuleDragState.active {
                if capsuleDragState.mode == -1 {
                    raw = 44 + min(capsuleDragState.offset, 138)
                } else if capsuleDragState.mode == 1 {
                    raw = 182 - min(capsuleDragState.offset, 138)
                } else {
                    raw = baseHeight
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
                if isParkingMemoryExpanded { return 560 }
                if isCapsuleExpanded { return 370 }
            }
            return isCapsuleExpanded ? 370 : (270 + 100 * dragProgress)
        }()

        return ZStack {
            if isParkingMemoryExpanded {
                parkingMemoryContent
                    .transition(.opacity)
            } else if isCapsuleExpanded {
                expandedContent
                    .id(parkingStartTime)
                    .transition(.opacity)
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
                        if showSpeedInfo {
                            HStack(spacing: 16) {
                                Text("\(Int(locationManager.speed)) km/h")
                                    .font(.body.bold())
                                    .foregroundStyle(adaptiveTextColor())
                                    .contentTransition(.numericText())
                                    .animation(.easeInOut(duration: 0.15), value: Int(locationManager.speed))
                                if let eta = drivingETASeconds {
                                    Text(formatCompactETA(eta))
                                        .font(.body.bold())
                                        .foregroundStyle(adaptiveTextColor())
                                        .contentTransition(.numericText())
                                }
                            }
                            .transition(.blurReplace())
                        } else {
                            Text(locationManager.currentAddress)
                                .font(.body.bold())
                                .foregroundStyle(adaptiveTextColor())
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                                .transition(.blurReplace())
                        }
                    }
                    .opacity(addressReveal)
                    .blur(radius: 20 * (1 - addressReveal))
                    .animation(.easeInOut(duration: 0.3), value: showSpeedInfo)
                }
            }
        }
        .frame(width: capsuleWidth)
        .frame(height: capsuleHeight)
        .background {
            orbBackground
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 34))
        .clipShape(.rect(cornerRadius: 34))
        .contentShape(Rectangle())
        .scaleEffect(capsuleScale)
        .animation(capsuleDragState.active ? nil : .spring(response: 0.4, dampingFraction: 0.85), value: isCapsuleExpanded)
        .animation(capsuleDragState.active ? nil : .spring(response: 0.4, dampingFraction: 0.85), value: isParkingMemoryExpanded)
        .animation(.easeInOut(duration: 0.4), value: orbOpacity)
        .gesture(
            DragGesture()
                .updating($capsuleDragState) { value, state, _ in
                    guard !isParkingMemoryExpanded else { return }
                    let dy = value.translation.height
                    if state.mode == 0 {
                        if !isCapsuleExpanded, dy < 0 {
                            state.mode = -1
                        } else if isCapsuleExpanded, dy > 0 {
                            state.mode = 1
                        } else {
                            state.active = false
                            state.offset = 0
                            return
                        }
                    }
                    state.active = state.mode != 0
                    if state.mode == -1 {
                        let next = min(-dy, 138)
                        state.offset = max(state.offset, max(0, next))
                    } else if state.mode == 1 {
                        let next = min(dy, 138)
                        state.offset = max(state.offset, max(0, next))
                    } else {
                        state.offset = 0
                    }
                }
                .onChanged { _ in
                    capsuleSettleWorkItem?.cancel()
                    capsuleSettleWorkItem = nil
                    capsuleSettleHeight = nil
                }
                .onEnded { value in
                    let dy = value.translation.height
                    let predictedDY = value.predictedEndTranslation.height
                    let threshold: CGFloat = 50
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
            guard !capsuleDragState.active, capsuleSettleHeight == nil else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                isCapsuleExpanded.toggle()
                isParkingMemoryExpanded = false
                orbOpacity = isCapsuleExpanded ? 0.5 : 1.0
                if !isCapsuleExpanded {
                    capsuleOnRight = false
                }
            }
            if isCapsuleExpanded {
                updateVisitStatus()
                refreshETA()
            }
        }
        .onReceive(locationManager.$visits) { _ in
            if isCapsuleExpanded {
                updateVisitStatus()
            }
        }
        .onChange(of: showDepartedLabel) { _, _ in
            if isCapsuleExpanded {
                updateVisitStatus()
            }
        }
        .onChange(of: visitStatus) { oldStatus, newStatus in
            guard hasDeparted else {
                stopStationaryTimer()
                return
            }
            if newStatus == "已停留", oldStatus != "已停留" {
                stationaryTrackingTrigger &+= 1
                northOverrideTrackingToken &+= 1
                startStationaryTimer()
            } else if newStatus != "已停留", oldStatus == "已停留" {
                stopStationaryTimer()
            }
        }
        .onChange(of: hasDeparted) { _, departed in
            if !departed {
                stopStationaryTimer()
            }
        }
        .onChange(of: isCapsuleExpanded) { _, expanded in
            if expanded {
                startCapsuleUpdateTimer()
                stopRandomInfoTimer()
            } else {
                stopCapsuleUpdateTimer()
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

    private var orbBackgroundColor: Color {
        let opacity = effectiveOrbOpacity
        if opacity <= 0 { return Color.black.opacity(0.92) }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        UIColor(Color.black.opacity(0.4)).getRed(&r, green: &g, blue: &b, alpha: nil)
        var rr = r, gg = g, bb = b
        let orbColors: [(UIColor, Double)] = [
            (UIColor(hex: "BEBC3F"), 0.3),
            (UIColor(hex: "5CAEB7"), 0.3),
            (UIColor(hex: "0098FF"), 0.3)
        ]
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

    private var orbBackground: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let t = animationClock.elapsed
            let orbScale = sqrt(h / 44.0)

            ZStack {
                if effectiveOrbOpacity > 0 {
                    Color.black.opacity(0.4)
                }

                Circle()
                    .fill(Color(hex: "BEBC3F").opacity(0.3 * effectiveOrbOpacity))
                    .blur(radius: 20)
                    .frame(width: 200 * orbScale, height: 200 * orbScale)
                    .offset(
                        x: w * 0.5 + CGFloat(sin(t * 0.5)) * w * 0.35 - 100 * orbScale,
                        y: h * 0.5 + CGFloat(cos(t * 0.4)) * h * 0.35 - 100 * orbScale
                    )
                Circle()
                    .fill(Color(hex: "5CAEB7").opacity(0.3 * effectiveOrbOpacity))
                    .blur(radius: 20)
                    .frame(width: 220 * orbScale, height: 220 * orbScale)
                    .offset(
                        x: w * 0.5 + CGFloat(sin(t * 0.4 + 2)) * w * 0.3 - 110 * orbScale,
                        y: h * 0.5 + CGFloat(cos(t * 0.35 + 2)) * h * 0.3 - 110 * orbScale
                    )
                Circle()
                    .fill(Color(hex: "0098FF").opacity(0.3 * effectiveOrbOpacity))
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

    private var expandedContent: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 4) {
                        Text("\(distanceLabel):")
                            .font(.body.bold())
                            .foregroundStyle(adaptiveTextColor(opacity: 0.8))
                            .contentTransition(.opacity)
                            .animation(.easeInOut(duration: 0.3), value: distanceLabel)
                        Text(drivingDistanceText ?? "--")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(adaptiveTextColor())
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.3), value: drivingDistanceText)
                    }
                    HStack(spacing: 4) {
                        if visitStatus == "已離場" {
                            // 已离场时只显示标题，无冒号无时间
                            Text(visitStatus)
                                .font(.body.bold())
                                .foregroundStyle(adaptiveTextColor(opacity: 0.8))
                        } else {
                            // 其他状态显示标题+冒号+时间
                            Text("\(visitStatus):")
                                .font(.body.bold())
                                .foregroundStyle(adaptiveTextColor(opacity: 0.8))
                            Text(hasDeparted ? (visitStatus == "已停留" ? formatStationaryDuration() : formatDepartureDuration()) : formatCapsuleDuration())
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(adaptiveTextColor())
                                .contentTransition(.numericText())
                                .animation(.easeInOut(duration: 0.15), value: hasDeparted ? (visitStatus == "已停留" ? stationaryElapsed : departureElapsed) : capsuleDuration)
                        }
                    }
                }

                Spacer()

                VStack(spacing: 8) {
                    Button(action: {
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
                        Label("泊車記憶", systemImage: "car.fill")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.white)
                            .frame(width: 126, height: 54)
                            .glassEffect(.regular.tint(Color(hex: "46ADB8").opacity(0.8)), in: .capsule)
                    }
                    .opacity(timerRunning ? 1.0 : 0.5)

                    Button(action: {
                        if showingRoute {
                            withAnimation {
                                showingRoute = false
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
                            guard let destination = destinationManager.selectedDestination else { return }
                            guard let currentLocation = locationManager.lastLocation else { return }
                            let routeToken = UUID()
                            routePriorityToken = routeToken
                            routePriorityAnchor = currentLocation.coordinate
                            let overlayToken = UUID()
                            routeOverlayToken = overlayToken
                            routeOverlayAnimationToken = overlayToken
                            if !showMap {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    showMap = true
                                }
                            }
                            let request = MKDirections.Request()
                            request.source = MKMapItem(placemark: MKPlacemark(coordinate: currentLocation.coordinate))
                            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.coordinate))
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
                    }) {
                        Label("最優路線", systemImage: "map")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.white)
                            .frame(width: 126, height: 54)
                            .glassEffect(.regular.tint(Color(hex: "BCBA1E").opacity(0.8)), in: .capsule)
                    }
                    .opacity(showingRoute ? 1.0 : 0.5)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            Spacer(minLength: 0)

            HStack {
                HStack(spacing: 4) {
                    Text("\(Int(locationManager.speed))")
                        .font(.body.bold())
                        .foregroundStyle(adaptiveTextColor(opacity: 0.6))
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.15), value: Int(locationManager.speed))
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
                    .animation(.easeInOut(duration: 0.15), value: etaText ?? "--")
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
                // 横屏：左右排布，左边370保持原有内容，右边190放按钮
                HStack(alignment: .top, spacing: 0) {
                    // 左边：原有内容，370宽度居中
                    VStack(spacing: 0) {
                        // Row 1: Back button + Title
                        HStack {
                            Button(action: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                    isParkingMemoryExpanded = false
                                    orbOpacity = 1.0
                                    capsuleOnRight = false
                                    timeAdjustAccumulated = 0
                                    timeAdjustText = nil
                                    showingExpandedPhotos = false
                                    selectedPhotoIndex = nil
                                }
                            }) {
                                Image(systemName: "chevron.left.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(adaptiveTextColor(opacity: 0.8))
                            }
                            Text("泊車記憶")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(adaptiveTextColor())
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                        // Row 2: 入場時間 + 日期时间 + 加减按钮（同一行）
                        HStack {
                            Text("入場時間")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(adaptiveTextColor(opacity: 0.6))
                            let cal = Calendar.current
                            let d = cal.component(.day, from: parkingEntryTime)
                            let m = cal.component(.month, from: parkingEntryTime)
                            let y = cal.component(.year, from: parkingEntryTime)
                            let hr = cal.component(.hour, from: parkingEntryTime)
                            let mi = cal.component(.minute, from: parkingEntryTime)
                            Text(String(format: "%02d/%02d/%04d %02d:%02d", d, m, y, hr, mi))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(adaptiveTextColor())
                                .monospacedDigit()
                                .contentTransition(.numericText())
                                .animation(.easeInOut(duration: 0.15), value: parkingEntryTime)
                            Spacer()
                            // 加减按钮在最右，文字在加号右手边
                            HStack(spacing: 6) {
                                Button(action: {
                                    timeAdjustAccumulated -= 1
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        parkingEntryTime = parkingEntryTime.addingTimeInterval(-60)
                                    }
                                    showAdjustText()
                                }) {
                                    Image(systemName: "minus")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(adaptiveTextColor())
                                        .frame(width: 28, height: 28)
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
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(adaptiveTextColor())
                                        .frame(width: 28, height: 28)
                                        .glassEffect(.regular, in: .rect(cornerRadius: 8))
                                }
                                if let text = timeAdjustText {
                                    Text(text)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(adaptiveTextColor(opacity: 0.8))
                                        .transition(.opacity)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                        // Camera preview
                        cameraSection
                            .padding(.top, 10)
                            .padding(.leading, -1)
                    }
                    .frame(width: 370)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 16)

                    // 右边：按钮区域（190pt），底部与相机预览框底部对齐
                    VStack(spacing: 16) {
                        // 離場 button
                        Button(action: {
                            startDepartureCountdown()
                        }) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 25)
                                    .fill(Color(hex: "D2251F"))
                                    .frame(width: 161, height: 70)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 25)
                                            .stroke(Color.white.opacity(0.8), lineWidth: 4)
                                    )
                                if let countdown = parkingCountdown {
                                    Text("\(countdown)")
                                        .font(.system(size: 40, weight: .bold))
                                        .foregroundStyle(.white)
                                        .contentTransition(.numericText())
                                        .animation(.easeInOut(duration: 0.15), value: parkingCountdown)
                                } else if parkingDeparted {
                                    AnimatedCheckmarkView()
                                } else {
                                    Text("離場")
                                        .font(.system(size: 22, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                        }

                        // 入场计时
                        ZStack {
                            GeometryReader { geo in
                                let w = geo.size.width
                                let h = geo.size.height
                                let t = animationClock.elapsed * 0.3

                                ZStack {
                                    Circle()
                                        .fill(Color(hex: "46ADB8").opacity(0.5))
                                        .blur(radius: 16)
                                        .frame(width: 100, height: 100)
                                        .offset(
                                            x: w * 0.5 + CGFloat(sin(t * 0.5)) * w * 0.35 - 50,
                                            y: h * 0.5 + CGFloat(cos(t * 0.4)) * h * 0.35 - 50
                                        )
                                    Circle()
                                        .fill(Color(hex: "0098FF").opacity(0.5))
                                        .blur(radius: 16)
                                        .frame(width: 110, height: 110)
                                        .offset(
                                            x: w * 0.5 + CGFloat(sin(t * 0.4 + 2)) * w * 0.3 - 55,
                                            y: h * 0.5 + CGFloat(cos(t * 0.35 + 2)) * h * 0.3 - 55
                                        )
                                    Circle()
                                        .fill(Color(hex: "BCBAE1").opacity(0.5))
                                        .blur(radius: 16)
                                        .frame(width: 90, height: 90)
                                        .offset(
                                            x: w * 0.5 + CGFloat(sin(t * 0.6 + 4)) * w * 0.33 - 45,
                                            y: h * 0.5 + CGFloat(cos(t * 0.45 + 4)) * h * 0.33 - 45
                                        )
                                }
                            }
                            .frame(width: 161, height: 70)
                            .clipShape(.rect(cornerRadius: 25))
                            .glassEffect(.regular, in: .rect(cornerRadius: 25))
                            .overlay(
                                RoundedRectangle(cornerRadius: 25)
                                    .stroke(Color.white.opacity(0.8), lineWidth: 4)
                            )
                            VStack(spacing: 2) {
                                Text("入場計時")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                    .padding(.trailing, 28)
                                Text(formatParkingElapsed())
                                    .font(.system(size: 32, weight: .bold))
                                    .foregroundStyle(.white)
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                                    .animation(.easeInOut(duration: 0.15), value: parkingElapsed)
                            }
                        }
                    }
                    .frame(width: 190)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 16)
                }
            } else {
                // 竖屏：原有布局
                // Back button + Title
                HStack {
                    Button(action: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            isParkingMemoryExpanded = false
                            orbOpacity = 1.0
                            capsuleOnRight = false
                            timeAdjustAccumulated = 0
                            timeAdjustText = nil
                            showingExpandedPhotos = false
                            selectedPhotoIndex = nil
                        }
                    }) {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(adaptiveTextColor(opacity: 0.8))
                    }
                    Text("泊車記憶")
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
                            Text("入場時間")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(adaptiveTextColor(opacity: 0.6))
                            if let text = timeAdjustText {
                                Text(text)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(adaptiveTextColor(opacity: 0.8))
                                    .transition(.opacity)
                            }
                        }
                        let cal = Calendar.current
                        let d = cal.component(.day, from: parkingEntryTime)
                        let m = cal.component(.month, from: parkingEntryTime)
                        let y = cal.component(.year, from: parkingEntryTime)
                        let hr = cal.component(.hour, from: parkingEntryTime)
                        let mi = cal.component(.minute, from: parkingEntryTime)
                        Text(String(format: "%02d/%02d/%04d %02d:%02d", d, m, y, hr, mi))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(adaptiveTextColor())
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.15), value: parkingEntryTime)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        Button(action: {
                            timeAdjustAccumulated -= 1
                            withAnimation(.easeInOut(duration: 0.2)) {
                                parkingEntryTime = parkingEntryTime.addingTimeInterval(-60)
                            }
                            showAdjustText()
                        }) {
                            Image(systemName: "minus")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(adaptiveTextColor())
                                .frame(width: 32, height: 32)
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
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(adaptiveTextColor())
                                .frame(width: 32, height: 32)
                                .glassEffect(.regular, in: .rect(cornerRadius: 8))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                // Camera preview + photo button + thumbnails
                cameraSection
                    .padding(.top, 14)

                Spacer(minLength: 0)

                // Bottom: 離場 button + entry timer
                HStack(spacing: 14) {
                    // 離場 button
                    Button(action: {
                        startDepartureCountdown()
                    }) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 25)
                                .fill(Color(hex: "D2251F"))
                                .frame(width: 161, height: 87)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 25)
                                        .stroke(Color.white.opacity(0.8), lineWidth: 4)
                                )
                            if let countdown = parkingCountdown {
                                Text("\(countdown)")
                                    .font(.system(size: 48, weight: .bold))
                                    .foregroundStyle(.white)
                                    .contentTransition(.numericText())
                                    .animation(.easeInOut(duration: 0.15), value: parkingCountdown)
                            } else if parkingDeparted {
                                AnimatedCheckmarkView()
                            } else {
                                Text("離場")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }

                    // Entry timer with aurora gradient orb animation
                    ZStack {
                        GeometryReader { geo in
                            let w = geo.size.width
                            let h = geo.size.height
                            let t = animationClock.elapsed * 0.3

                            ZStack {
                                Circle()
                                    .fill(Color(hex: "46ADB8").opacity(0.5))
                                    .blur(radius: 16)
                                    .frame(width: 120, height: 120)
                                    .offset(
                                        x: w * 0.5 + CGFloat(sin(t * 0.5)) * w * 0.35 - 60,
                                        y: h * 0.5 + CGFloat(cos(t * 0.4)) * h * 0.35 - 60
                                    )
                                Circle()
                                    .fill(Color(hex: "0098FF").opacity(0.5))
                                    .blur(radius: 16)
                                    .frame(width: 130, height: 130)
                                    .offset(
                                        x: w * 0.5 + CGFloat(sin(t * 0.4 + 2)) * w * 0.3 - 65,
                                        y: h * 0.5 + CGFloat(cos(t * 0.35 + 2)) * h * 0.3 - 65
                                    )
                                Circle()
                                    .fill(Color(hex: "BCBAE1").opacity(0.5))
                                    .blur(radius: 16)
                                    .frame(width: 110, height: 110)
                                    .offset(
                                        x: w * 0.5 + CGFloat(sin(t * 0.6 + 4)) * w * 0.33 - 55,
                                        y: h * 0.5 + CGFloat(cos(t * 0.45 + 4)) * h * 0.33 - 55
                                    )
                            }
                        }
                        .frame(width: 161, height: 87)
                        .clipShape(.rect(cornerRadius: 25))
                        .glassEffect(.regular, in: .rect(cornerRadius: 25))
                        .overlay(
                            RoundedRectangle(cornerRadius: 25)
                                .stroke(Color.white.opacity(0.8), lineWidth: 4)
                        )
                        VStack(spacing: 2) {
                            Text("入場計時")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .padding(.trailing, 18)
                            Text(formatParkingElapsed())
                                .font(.system(size: 36, weight: .bold))
                                .foregroundStyle(.white)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                                .animation(.easeInOut(duration: 0.15), value: parkingElapsed)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
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
            return "\(mins)min"
        }
        let hrs = mins / 60
        let remainMins = mins % 60
        return remainMins > 0 ? "\(hrs)h\(remainMins)m" : "\(hrs)h"
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
        guard let destination = destinationManager.selectedDestination else { return }
        isRerouting = true
        lastRerouteRequestAt = Date()
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.coordinate))
        request.transportType = .automobile
        request.requestsAlternateRoutes = false
        let directions = MKDirections(request: request)
        directions.calculate { response, error in
            DispatchQueue.main.async {
                defer { isRerouting = false }
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
        d.set(timerRunning, forKey: "timerRunning")
        d.set(lastKnownArrivalDate, forKey: "lastKnownArrivalDate")
        d.synchronize()
        WidgetCenter.shared.reloadTimelines(ofKind: "ParkingTimerWidget")
    }

    private func startPersistentTimer() {
        guard !timerRunning else { return }
        timerRunning = true
        let d = Self.appGroupDefaults ?? .standard
        d.set(parkingStartTime, forKey: "parkingStartTime")
        d.set(hasDeparted, forKey: "hasDeparted")
        d.set(timerRunning, forKey: "timerRunning")
        d.set(lastKnownArrivalDate, forKey: "lastKnownArrivalDate")
        d.set(locationManager.currentAddress, forKey: "parkingEntryLocation")
        d.synchronize()
        parkingTimer?.invalidate()
        parkingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let entry = parkingEntryTime
            let start = parkingStartTime
            let e = Date().timeIntervalSince(entry)
            let d = Date().timeIntervalSince(start)
            DispatchQueue.main.async {
                parkingElapsed = e
                capsuleDuration = d
            }
            WidgetCenter.shared.reloadTimelines(ofKind: "ParkingTimerWidget")
        }
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
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
                departureElapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                    guard hasDeparted, let dep = departureTime else { return }
                    let e = Date().timeIntervalSince(dep)
                    DispatchQueue.main.async {
                        departureElapsed = e
                    }
                }
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

    private func startCapsuleUpdateTimer() {
        stopCapsuleUpdateTimer()
        capsuleUpdateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            DispatchQueue.main.async {
                updateVisitStatus()
                if locationManager.speed >= 5 {
                    refreshETA()
                }
            }
        }
    }

    private func stopCapsuleUpdateTimer() {
        capsuleUpdateTimer?.invalidate()
        capsuleUpdateTimer = nil
    }

    // MARK: - Random Speed Info Display
    private func startRandomInfoTimer() {
        stopRandomInfoTimer()
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
        let interval = Double.random(in: 20...60)
        randomInfoTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [self] _ in
            DispatchQueue.main.async {
                refreshETA()
                showSpeedInfo = true
                speedInfoTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [self] _ in
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showSpeedInfo = false
                        }
                        scheduleNextRandomInfo()
                    }
                }
            }
        }
    }

    private func showAdjustText() {
        adjustHideWorkItem?.cancel()
        withAnimation(.easeIn(duration: 0.15)) {
            timeAdjustText = "已調整\(timeAdjustAccumulated)分鐘"
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
        isCapturing = true
        NotificationCenter.default.post(name: .captureParkingPhoto, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.isCapturing = false
        }
        #endif
    }

    private func startCaptureAnimation(photo: UIImage) {
        let tempID = UUID()
        animatingPhotoID = tempID
        animatingPhotoImage = photo

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            animatingPhotoID = nil
            animatingPhotoImage = nil
        }
    }

    private func refreshETA() {
        guard let dest = destinationManager.selectedDestination,
              let loc = locationManager.manager.location else {
            etaText = nil
            drivingDistanceText = nil
            drivingETASeconds = nil
            return
        }
        destinationManager.calculateRoute(
            from: loc.coordinate,
            to: dest.coordinate
        ) { distance, time in
            DispatchQueue.main.async {
                if let distance = distance {
                    if distance < 1000 {
                        drivingDistanceText = "\(Int(distance)) m"
                    } else {
                        drivingDistanceText = String(format: "%.1f km", distance / 1000)
                    }
                } else {
                    drivingDistanceText = nil
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
                } else {
                    etaText = nil
                }
            }
        }
    }

    private func recalculateRoute() {
        guard let destination = destinationManager.selectedDestination,
              let currentLocation = locationManager.lastLocation else { return }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: currentLocation.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.coordinate))
        request.transportType = .automobile
        request.requestsAlternateRoutes = false
        let directions = MKDirections(request: request)
        directions.calculate { response, error in
            guard let route = response?.routes.first, error == nil else { return }
            DispatchQueue.main.async {
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
        guard let dest = destinationManager.selectedDestination else { return "離目的地距離" }
        let name = dest.name.lowercased()
        if name.contains("home") || name.contains("家") {
            return "離家距離"
        } else if name.contains("office") || name.contains("公司") {
            return "離公司距離"
        }
        return "離\(dest.name)距離"
    }

    private func updateVisitStatus() {
        guard let lastVisit = locationManager.visits.first else {
            visitStatus = "已停留"
            return
        }
        
        if hasDeparted {
            if showDepartedLabel {
                // 显示"已离场"期间
                visitStatus = "已離場"
            } else {
                // 离场后：根据GPS判断是"已开车"还是"已停留"
                let isMoving = locationManager.speed > 5  // 时速>5km/h认为在移动
                let gpsLocationChanged = isGPSLocationChanged()  // GPS位置有显著变化（>20米）
                
                if isMoving && gpsLocationChanged {
                    // 在移动 → 已开车
                    visitStatus = "已開車"
                    lastMovementTime = Date()  // 记录最后移动时间
                } else if let lastMove = lastMovementTime {
                    // 不在移动，检查是否已持续2分钟以上
                    let stationaryDuration = Date().timeIntervalSince(lastMove)
                    if stationaryDuration >= 120 {
                        // 静止超过2分钟 → 已停留
                        visitStatus = "已停留"
                    } else {
                        // 静止不到2分钟，保持"已开车"
                        visitStatus = "已開車"
                    }
                } else {
                    // 刚离场且没检测到移动 → 已停留
                    visitStatus = "已停留"
                }
            }
        } else if lastVisit.departureDate == nil {
            visitStatus = "已泊車"
        } else {
            let elapsed = Date().timeIntervalSince(lastVisit.departureDate!)
            if elapsed < 120 {
                visitStatus = "已開車"
            } else {
                visitStatus = "已停留"
            }
        }
    }
    
    // 检查GPS位置是否有显著变化（>20米）
    private func isGPSLocationChanged() -> Bool {
        guard let currentLocation = locationManager.manager.location,
              let lastLocation = lastGPSLocation else {
            lastGPSLocation = locationManager.manager.location
            return false
        }
        
        let distance = currentLocation.distance(from: lastLocation)
        lastGPSLocation = currentLocation
        
        return distance > 20  // 超过20米算显著变化
    }
    
    // MARK: - Camera Section
    private var cameraSection: some View {
        ZStack(alignment: .topLeading) {
            CameraPreviewView(isLandscape: isLandscape)
                .frame(width: 338, height: 190)
                .clipShape(RoundedRectangle(cornerRadius: 37))
                .overlay(
                    RoundedRectangle(cornerRadius: 37)
                        .stroke(Color.white.opacity(0.8), lineWidth: 4)
                )

            cameraDimOverlay
            cameraPhotoStack
            captureAnimationOverlay
            cameraButton

            // Delete button on selected photo (positioned at photo's top-left corner)
            if let idx = selectedPhotoIndex, idx < photoStorage.photos.count, showDeleteButton {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                        let photo = photoStorage.photos[idx]
                        photoStorage.deletePhoto(photo)
                        if photoStorage.photos.isEmpty {
                            selectedPhotoIndex = nil
                            showingExpandedPhotos = false
                        } else if idx >= photoStorage.photos.count {
                            selectedPhotoIndex = photoStorage.photos.count - 1
                        }
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(.ultraThinMaterial, in: .circle)
                        .glassEffect(.regular, in: .circle)
                }
                .position(x: 72, y: 34)
                .transition(.opacity)
            }

            // Thumbnail-only tap area for expanding (top-left, matching thumb position)
            if !showingExpandedPhotos {
                Color.clear
                    .frame(width: 80, height: 70)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                            showingExpandedPhotos = true
                            selectedPhotoIndex = nil
                        }
                    }
            }
        }
        .frame(width: 338, height: 190)
    }

    private var cameraDimOverlay: some View {
        Group {
            if showingExpandedPhotos {
                let dimOpacity = selectedPhotoIndex != nil ? 0.65 : 0.45
                Color.black.opacity(dimOpacity)
                    .frame(width: 338, height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 37))
                    .animation(.easeInOut(duration: 0.3), value: selectedPhotoIndex)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                            if selectedPhotoIndex != nil {
                                selectedPhotoIndex = nil
                            } else {
                                showingExpandedPhotos = false
                                selectedPhotoIndex = nil
                            }
                        }
                    }
            }
        }
    }

    private var cameraPhotoStack: some View {
        let photos = photoStorage.photos
        let count = photos.count
        return ZStack {
            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                CameraPhotoItem(
                    photo: photo,
                    index: index,
                    totalCount: count,
                    isExpanded: showingExpandedPhotos,
                    isSelected: selectedPhotoIndex == index
                )
                .onTapGesture {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                        if showingExpandedPhotos {
                            selectedPhotoIndex = (selectedPhotoIndex == index) ? nil : index
                        }
                    }
                }
            }
        }
        .frame(width: 338, height: 190, alignment: .center)
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    guard showingExpandedPhotos, photos.count > 1 else { return }
                    let horizontal = value.translation.width
                    guard abs(horizontal) > abs(value.translation.height) else { return }
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                        if horizontal < 0 {
                            // Swipe left → next photo (wraps to first)
                            if let cur = selectedPhotoIndex {
                                selectedPhotoIndex = (cur + 1) % photos.count
                            } else {
                                selectedPhotoIndex = 0
                            }
                        } else {
                            // Swipe right → previous photo (wraps to last)
                            if let cur = selectedPhotoIndex {
                                selectedPhotoIndex = (cur - 1 + photos.count) % photos.count
                            } else {
                                selectedPhotoIndex = photos.count - 1
                            }
                        }
                    }
                }
        )
    }

    private var captureAnimationOverlay: some View {
        Group {
            if animatingPhotoID != nil, let img = animatingPhotoImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 338, height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 37))
                    .scaleEffect(0.2)
                    .offset(x: -130, y: -70)
                    .rotationEffect(.degrees(photoStorage.photos.last?.rotation ?? 0))
                    .allowsHitTesting(false)
                    .zIndex(100)
            }
        }
    }

    private var cameraButton: some View {
        Button(action: { capturePhoto() }) {
            ZStack {
                RoundedRectangle(cornerRadius: 25)
                    .frame(width: 65, height: 164)
                    .glassEffect(.regular, in: .rect(cornerRadius: 25))
                    .tint(.clear)
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    let t = animationClock.elapsed * 0.3
                    ZStack {
                        Circle()
                            .fill(Color(hex: "3497FF").opacity(0.85))
                            .blur(radius: 16)
                            .frame(width: 100, height: 100)
                            .offset(x: w * 0.5 + CGFloat(sin(t * 0.5)) * w * 0.4 - 50,
                                    y: h * 0.5 + CGFloat(cos(t * 0.4)) * h * 0.35 - 50)
                        Circle()
                            .fill(Color(hex: "FFC46D").opacity(0.85))
                            .frame(width: 110, height: 110)
                            .blur(radius: 16)
                            .offset(x: w * 0.5 + CGFloat(sin(t * 0.4 + 2)) * w * 0.35 - 55,
                                    y: h * 0.5 + CGFloat(cos(t * 0.35 + 2)) * h * 0.3 - 55)
                        Circle()
                            .fill(Color(hex: "FF825C").opacity(0.85))
                            .frame(width: 90, height: 90)
                            .blur(radius: 16)
                            .offset(x: w * 0.5 + CGFloat(sin(t * 0.6 + 4)) * w * 0.38 - 45,
                                    y: h * 0.5 + CGFloat(cos(t * 0.45 + 4)) * h * 0.35 - 45)
                    }
                }
                .frame(width: 57, height: 156)
                .clipShape(.rect(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.white, lineWidth: 1.6))
                Image(systemName: "camera.fill")
                    .font(.system(size: 24))
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
        .blur(radius: showingExpandedPhotos || photoStorage.photos.count >= PhotoStorage.maxPhotos ? 12 : 0)
        .opacity(showingExpandedPhotos || photoStorage.photos.count >= PhotoStorage.maxPhotos ? 0 : 1)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: showingExpandedPhotos)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: photoStorage.photos.count)
    }

    // MARK: - GPS Status Badge
    private var gpsStatusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(gpsColor)
                .frame(width: 8, height: 8)
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
            }
        }
        .animation(.easeInOut(duration: 0.5), value: locationManager.gpsQuality)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private var gpsColor: Color {
        switch locationManager.gpsQuality {
        case .good: return .green
        case .poor: return .yellow
        case .bad: return .red
        case .unknown: return .gray
        }
    }

    private var gpsLabel: String {
        switch locationManager.gpsQuality {
        case .good: return "GPS Ready"
        case .poor: return "GPS Weak"
        case .bad: return "GPS Lost"
        case .unknown: return "GPS Waiting"
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
    
    // MARK: - Translate + Save
    func translate() {
        if isRecording {
            speechRecognizer.stopRecording()
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.6)) {
                isRecording = false
                isVoiceRecording = false
            }
            triggerVoiceStopEffect()
            if !speechRecognizer.transcribedText.isEmpty {
                viewModel.inputText = speechRecognizer.transcribedText
            }
        }
        let input = viewModel.inputText
        isInputFocused = false
        viewModel.translate()
        triggerTranslateStartEffect()
        
        Task {
            for await _ in viewModel.$isTranslating.values {
                if !viewModel.isTranslating {
                    triggerTranslateStopEffect()
                    guard !viewModel.outputText.isEmpty else { break }
                    historyManager.add(
                        inputText: input,
                        outputText: viewModel.outputText,
                        sourceLanguage: viewModel.sourceLanguage.displayName,
                        targetLanguage: viewModel.targetLanguage.displayName
                    )
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.prepare()
                    generator.impactOccurred()
                    break
                }
            }
        }
    }
    
    // MARK: - Speed Effects
    @State private var translateSpeedTimer: Timer?
    
    private func triggerTranslateStartEffect() {
        translateSpeedTimer?.invalidate()
        voiceSpeedTimer?.invalidate()
        let startTime = Date()
        translateSpeedTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { timer in
            MainActor.assumeIsolated {
                let t = Date().timeIntervalSince(startTime)
                if t < 1.4 {
                    let u = t / 1.4
                    animationClock.speedMultiplier = 1 + (4.0 - 1) * (1 - pow(1 - u, 2))
                } else {
                    animationClock.speedMultiplier = 4.0
                    timer.invalidate()
                }
            }
        }
    }
    
    private func triggerTranslateStopEffect() {
        translateSpeedTimer?.invalidate()
        let startSpeed = animationClock.speedMultiplier
        let startTime = Date()
        translateSpeedTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { timer in
            MainActor.assumeIsolated {
                let t = Date().timeIntervalSince(startTime)
                if t < 2.0 {
                    let u = t / 2.0
                    animationClock.speedMultiplier = startSpeed + (1.0 - startSpeed) * pow(u, 1.5)
                } else {
                    animationClock.speedMultiplier = 1.0
                    timer.invalidate()
                }
            }
        }
    }
    
    @State private var voiceSpeedTimer: Timer?

    private func triggerVoiceStartEffect() {
        voiceSpeedTimer?.invalidate()
        translateSpeedTimer?.invalidate()
        let startTime = Date()
        voiceSpeedTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            MainActor.assumeIsolated {
                let t = Date().timeIntervalSince(startTime)
                if t < 0.8 {
                    let u = t / 0.8
                    animationClock.speedMultiplier = 1 + (0.5 - 1) * pow(u, 1.5)
                } else if self.isRecording {
                    let level = self.speechRecognizer.audioLevel
                    animationClock.speedMultiplier = 0.5 + level * 7.5
                } else {
                    timer.invalidate()
                }
            }
        }
    }

    private func triggerVoiceStopEffect() {
        voiceSpeedTimer?.invalidate()
        let startSpeed = animationClock.speedMultiplier
        let startTime = Date()
        voiceSpeedTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { timer in
            MainActor.assumeIsolated {
                let t = Date().timeIntervalSince(startTime)
                if t < 2.0 {
                    let u = t / 2.0
                    animationClock.speedMultiplier = startSpeed + (1.0 - startSpeed) * pow(u, 1.5)
                } else {
                    animationClock.speedMultiplier = 1.0
                    timer.invalidate()
                }
            }
        }
    }
    
    // MARK: - Speech Recognition
    func toggleRecording() {
        if isRecording {
            speechRecognizer.stopRecording()
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.6)) {
                isRecording = false
                isVoiceRecording = false
            }
            triggerVoiceStopEffect()
            if !speechRecognizer.transcribedText.isEmpty {
                viewModel.inputText = speechRecognizer.transcribedText
            }
        } else {
            isInputFocused = false
            speechRecognizer.startRecording(locale: viewModel.sourceLanguage.speechLocale) { text in
                viewModel.inputText = text
            }
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.6)) {
                isRecording = true
                isVoiceRecording = true
            }
            triggerVoiceStartEffect()
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
        previewLayer.cornerRadius = 37
        previewLayer.masksToBounds = true
        previewLayer.frame = CGRect(x: 0, y: 0, width: 338, height: 190)
        
        // 横屏时旋转相机画面90度并放大填满
        if isLandscape {
            previewLayer.setAffineTransform(CGAffineTransform(rotationAngle: -.pi / 2).scaledBy(x: 1.8, y: 1.8))
        }
        
        view.layer.addSublayer(previewLayer)
        view.clipsToBounds = true

        context.coordinator.session = session
        context.coordinator.previewLayer = previewLayer
        context.coordinator.output = output

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }

        return view
        #endif
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject {
        var session: AVCaptureSession?
        var previewLayer: AVCaptureVideoPreviewLayer?
        var output: AVCapturePhotoOutput?

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
class SpeechRecognizer: ObservableObject {
    @Published var transcribedText: String = ""
    @Published var audioLevel: Double = 0.0
    private var onPartialResult: ((String) -> Void)?
    
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var recognitionGeneration = 0
    
    func startRecording(locale: Locale = Locale(identifier: "en-US"), onUpdate: @escaping (String) -> Void) {
        self.onPartialResult = onUpdate
        
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    self?.startActualRecording(locale: locale)
                default:
                    print("Speech recognition not authorized")
                }
            }
        }
    }
    
    private func startActualRecording(locale: Locale) {
        guard let recognizer = SFSpeechRecognizer(locale: locale),
              recognizer.isAvailable else {
            print("Speech recognizer not available")
            return
        }
        
        self.speechRecognizer = recognizer
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to set up audio session: \(error)")
            return
        }
        
        recognitionGeneration += 1
        let gen = recognitionGeneration
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        
        recognitionRequest.shouldReportPartialResults = true
        
        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            guard gen == self.recognitionGeneration else { return }
            
            if let result = result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.transcribedText = text
                    self.onPartialResult?(text)
                }
            }
            
            if error != nil || (result?.isFinal ?? false) {
                self.stopRecording()
            }
        }
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.recognitionRequest?.append(buffer)
            
            if let channelData = buffer.floatChannelData {
                let frames = UInt(buffer.frameLength)
                var rms: Float = 0
                vDSP_rmsqv(channelData[0], 1, &rms, frames)
                let amplified = Double(min(rms * 50, 1.0))
                let smoothed = self.audioLevel * 0.6 + amplified * 0.4
                DispatchQueue.main.async {
                    self.audioLevel = smoothed
                }
            }
        }
        
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }
    
    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        onPartialResult = nil
    }
    
    func restartRecording(locale: Locale) {
        guard let recognizer = SFSpeechRecognizer(locale: locale),
              recognizer.isAvailable else {
            print("Speech recognizer not available for locale: \(locale)")
            return
        }
        
        recognitionGeneration += 1
        
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        let newRequest = SFSpeechAudioBufferRecognitionRequest()
        newRequest.shouldReportPartialResults = true
        recognitionRequest = newRequest
        
        let gen = recognitionGeneration
        recognitionTask = recognizer.recognitionTask(with: newRequest) { [weak self] result, error in
            guard let self = self else { return }
            guard gen == self.recognitionGeneration else { return }
            
            if let result = result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.transcribedText = text
                    self.onPartialResult?(text)
                }
            }
            
            if error != nil || (result?.isFinal ?? false) {
                self.stopRecording()
            }
        }
        
        self.speechRecognizer = recognizer
    }
}

// MARK: - Camera Photo Item
struct CameraPhotoItem: View {
    let photo: ParkingPhoto
    let index: Int
    let totalCount: Int
    let isExpanded: Bool
    let isSelected: Bool

    private let baseW: CGFloat = 46
    private let baseH: CGFloat = 32
    private let expandedW: CGFloat = 46 * 3.8
    private let expandedH: CGFloat = 32 * 3.8
    private let thumbOffsetX: CGFloat = -(338 / 2 - 20 - 46 / 2)
    private let thumbOffsetY: CGFloat = -(190 / 2 - 18 - 32 / 2)

    var body: some View {
        if let img = photo.image {
            let photoW = isExpanded ? expandedW : baseW
            let photoH = isExpanded ? expandedH : baseH
            let selectedScale: CGFloat = (190 - 24) / expandedH
            let photoScale: CGFloat = isSelected ? selectedScale : (isExpanded ? 0.85 : 1.0)

            let finalOffsetX: CGFloat = {
                if isSelected { return 0 }
                if isExpanded {
                    let raw = CGFloat(photo.offsetX) * 22
                    let maxX: CGFloat = (338 - expandedW) / 2 - 12
                    return max(-maxX, min(maxX, raw))
                }
                return thumbOffsetX + CGFloat(photo.offsetX)
            }()
            let finalOffsetY: CGFloat = {
                if isSelected { return 0 }
                if isExpanded {
                    let raw = CGFloat(photo.offsetY) * 12
                    let maxY: CGFloat = (190 - expandedH) / 2 - 5
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
            let borderOpacity: Double = isSelected ? 1.0 : (isExpanded ? 0.6 : 0.8)
            let cr: CGFloat = isSelected ? 12 : (isExpanded ? 5 * 3.8 : 5)
            let zIdx: Double = isSelected ? 100 : Double(totalCount - index)

            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: photoW, height: photoH)
                .clipShape(RoundedRectangle(cornerRadius: cr))
                .overlay(
                    RoundedRectangle(cornerRadius: cr)
                        .stroke(Color.white.opacity(borderOpacity), lineWidth: borderW)
                )
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
}

#Preview {
    ContentView()
}
