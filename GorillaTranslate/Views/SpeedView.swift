import SwiftUI
import MapKit
import CoreMotion

struct SpeedView: View {
    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var timePhaseManager = TimePhaseManager()
    @StateObject private var sfxPlayer = SFXPlayer()
    @StateObject private var tiltMotion = TiltParallaxMotion()
    @StateObject private var gForceMotion = GForceParallaxMotion.shared
    @AppStorage("parallaxMode") private var parallaxMode: ParallaxMode = .tilt
    @State private var showParallaxToggle = false
    @AppStorage("sfxAccelerationEnabled") private var sfxAccelerationEnabled: Bool = false
    /// 時速數字底下嘅模糊光暈層
    @AppStorage("speedBlurEnabled") private var speedBlurEnabled: Bool = true
    /// 時速數字嘅陀螺儀傾斜 / G 值視差動畫
    @AppStorage("speedParallaxEnabled") private var speedParallaxEnabled: Bool = true
    /// 隱藏時速數字（數字原位隱形，其他照舊）
    @AppStorage("speedNumberHidden") private var speedNumberHidden: Bool = false
    @AppStorage(SpeedUnit.preferenceKey) private var speedUnitRaw = SpeedUnit.kilometresPerHour.rawValue
    private var speedUnit: SpeedUnit { .resolve(speedUnitRaw) }
    /// 卡爾曼濾波：開啟時時速數字逐格滾動插值
    @AppStorage("kalmanSmoothingEnabled") private var kalmanSmoothingEnabled: Bool = true

    /// 時速數字逐格滾動插值器（120Hz，獨立物件令只有數字 Text 重繪）
    @StateObject private var speedRoller = NumberRoller()
    @ObservedObject var acTelemetry: ACTelemetry
    var drivingState = false
    @AppStorage("acAutoConnectEnabled") private var acEnabled = false
    @State private var showSpeedSource = false
    @State private var showGameDetails = false
    @State private var instrumentsHidden = false
    @AppStorage("acComputerHost") private var acComputerHost = ""
    private var displaySpeed: Double {
        acTelemetry.isReceiving ? (acTelemetry.sample?.speed ?? 0) : locationManager.speed
    }

    /// 當前視差 X 值（-1…1），根據模式切換來源
    private var parallaxX: Double {
        if parallaxMode == .gforce, let force = acTelemetry.sample?.gForce, acTelemetry.isReceiving {
            return max(-1, min(1, force.lateral * 2))
        }
        return parallaxMode == .gforce ? gForceMotion.gForceX : tiltMotion.tiltX
    }
    /// 當前視差 Y 值（-1…1），根據模式切換來源
    private var parallaxY: Double {
        if parallaxMode == .gforce, let force = acTelemetry.sample?.gForce, acTelemetry.isReceiving {
            return max(-1, min(1, -force.longitudinal * 2))
        }
        return parallaxMode == .gforce ? gForceMotion.gForceY : tiltMotion.tiltY
    }

    /// G 值模式下視差效果倍數（比傾斜模式更強）
    private var parallaxMultiplier: Double {
        parallaxMode == .gforce ? 1.8 : 1.0
    }

    /// 膠囊彈出時模糊陰影倍數
    private var blurShadowMultiplier: Double {
        showParallaxToggle ? 1.6 : 1.0
    }

    /// 「圓點顏色」設定 → 圓點動畫 hex。
    /// 0=金黃（維持現有 #ffd700 照舊）、1=動態橙（30→120 km/h 橙→橙紅）、2-4=指定綠系。
    private var dotMatrixColorHex: String {
        colorGroup.dotColorHex(speed: displaySpeed, preset: orbColorPreset)
    }
    @AppStorage("colorSchemeIndex") private var colorSchemeIndex: Int = 0
    @AppStorage("orbMasterEnabled") private var orbMasterEnabled: Bool = true
    @AppStorage("orbColorPreset") private var orbColorPreset: Int = 0
    @AppStorage("orbOverlapGlowEnabled") private var orbOverlapGlowEnabled: Bool = true
    @AppStorage("orbBackgroundSpeed") private var orbBackgroundSpeed: Bool = true
    @AppStorage("useTimeBasedOrb") private var useTimeBasedOrb: Bool = false
    @AppStorage("darkKnightMode") private var legacyDarkKnightMode = false
    @AppStorage("colorGroupMode") private var colorGroupRaw = -1
    private var colorGroup: GorillaColorGroup {
        .resolve(raw: colorGroupRaw, legacyDarkKnight: legacyDarkKnightMode, legacyTimeBased: useTimeBasedOrb)
    }
    @AppStorage("mapStyleIndex") private var mapStyleIndex: Int = 0
    @AppStorage("capsuleDarkGlassEnabled") private var darkGlassEnabled = true
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var accelArmedFromStop: Bool = true
    @State private var lastSpeedSample: Double = 0
    @State private var lastSpeedSampleAt: Date = Date()
    @State private var accelerationCooldownUntil: Date = .distantPast

    /// GPS 失聯時保留最後已知時速
    @State private var lastKnownSpeed: Double = 0
    /// GPS 失聯動畫狀態（用於透明度漸變）
    @State private var gpsLostAnim: Bool = false
    let showMap: Bool
    var showSatellite: Bool = false
    var cycleMapPresentation: () -> Void = {}
    let animationClock: AnimationClock
    @Binding var mapCamera: MKMapCamera?
    let isDuoDevice: Bool
    let isDuoInnerDisplay: Bool
    let isDuoPartiallyOpen: Bool

    @State private var isLandscapeLayout = false

    var body: some View {
        ZStack {
            if showMap && !acTelemetry.isReceiving {
                ZStack {
                    GeometryReader { geo in
                        let useUpperHalf = isDuoPartiallyOpen && geo.size.width <= geo.size.height
                        ReadOnlyMapView(camera: highAltitudeCamera, mapStyleIndex: mapStyleIndex, showSatellite: showSatellite)
                            .frame(
                                width: geo.size.width,
                                height: useUpperHalf ? geo.size.height * 1.5 : geo.size.height
                            )
                            .offset(y: useUpperHalf ? -geo.size.height / 2 : 0)
                    }
                    .ignoresSafeArea()

                    // Minecraft green tint overlay
                    if mapStyleIndex == 1 && !showSatellite {
                        Color(red: 0.29, green: 0.48, blue: 0.18)
                            .opacity(0.3)
                            .blendMode(.multiply)
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                    }

                    GeometryReader { geo in
                        let w = geo.size.width
                        let h = geo.size.height
                        let useUpperHalf = isDuoPartiallyOpen && w <= h
                        RadialGradient(
                            gradient: Gradient(stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .clear, location: 0.45),
                                .init(color: .black.opacity(0.45), location: 0.7),
                                .init(color: .black.opacity(0.75), location: 1)
                            ]),
                            center: useUpperHalf ? UnitPoint(x: 0.5, y: 0.25) : .center,
                            startRadius: min(w, h) * 0.25,
                            endRadius: max(w, h) * 0.65
                        )
                        .ignoresSafeArea()
                    }
                    .allowsHitTesting(false)
                }
            } else if colorGroup == .darkKnight {
                Color.black.ignoresSafeArea()
            } else if colorGroup == .m3Concept {
                AnimatedBackground(clock: animationClock,
                    orbEnabled: colorGroup.orbsEnabled(master: orbMasterEnabled, surface: orbBackgroundSpeed),
                    orbSizeMultiplier: isDuoDevice ? 2.0 : 1.0, overlapGlowEnabled: orbOverlapGlowEnabled,
                    customOrbColors: M3ConceptPalette.homeOrbs, backgroundColorHex: M3ConceptPalette.black)
                    .ignoresSafeArea()
            } else {
                AnimatedBackground(clock: animationClock, colorSchemeIndex: colorSchemeIndex, isVoiceRecording: false, orbEnabled: orbMasterEnabled && orbBackgroundSpeed, useTimeBasedOrb: orbMasterEnabled && orbBackgroundSpeed && colorGroup == .timeBased, phaseManager: timePhaseManager, orbSizeMultiplier: isDuoDevice ? 2.0 : 1.0, orbColorPreset: orbColorPreset, overlapGlowEnabled: orbOverlapGlowEnabled)
                    .ignoresSafeArea()
            }

            GeometryReader { dotGeo in
                let useUpperHalf = isDuoPartiallyOpen && dotGeo.size.width <= dotGeo.size.height
                // canvas 以 1.4 倍畫面尺寸居中（唔係放大：圓點大小／密度不變，
                // 數量多咗近一倍），四邊各留 20% 緩衝 ——
                // 視差旋轉＋位移任何角度都唔會露邊。
                DotMatrixWebView(speed: Binding(
                    get: { displaySpeed },
                    set: { _ in }
                ), canvasScale: 1.0, dynamicColorHex: dotMatrixColorHex)
                .frame(width: dotGeo.size.width * 1.4, height: dotGeo.size.height * 1.4)
                .position(x: dotGeo.size.width / 2, y: dotGeo.size.height / 2)
                .offset(y: useUpperHalf ? -dotGeo.size.height / 4 : 0)
            }
            .ignoresSafeArea(edges: .all)
            .opacity(0.35)
            .allowsHitTesting(false)
            // 陀螺儀視差（深層）：圓點平面朝傾斜反方向擺動並做 3D 透視旋轉，
            // 同前景文字形成前後深度。G 值模式效果更強。
            .modifier(SpeedParallaxModifier(
                enabled: speedParallaxEnabled,
                parallaxX: parallaxX,
                parallaxY: parallaxY,
                multiplier: parallaxMultiplier
            ))

            Color.clear.contentShape(Rectangle())
                .onTapGesture(perform: toggleInstruments)
                .accessibilityIdentifier("speedBlankSpace")

            if instrumentsHidden {
                GeometryReader { geo in
                    let layout = SpeedCardLayout(width: geo.size.width, height: geo.size.height, partiallyOpen: isDuoPartiallyOpen)
                    speedCardDisplay(compact: false)
                        .foregroundStyle(instrumentForeground)
                        .frame(width: layout.width, height: layout.height)
                        .allowsHitTesting(false)
                }
            } else {
                FixedSpeedDashboard(motion: gForceMotion, telemetry: acTelemetry,
                    partiallyOpen: isDuoPartiallyOpen, foreground: instrumentForeground,
                    accent: Color(hex: dotMatrixColorHex),
                    textColorOverride: usesGrayMapText ? instrumentForeground : nil,
                    driving: drivingState, onBlankTap: toggleInstruments) {
                        speedCardDisplay(compact: false)
                    }
                    .environment(\.colorScheme, usesGrayMapText ? .light : showMap || colorGroup == .m3Concept || colorGroup == .darkKnight ? .dark : colorScheme)
            }
        }
        .sheet(isPresented: $showGameDetails) {
            NavigationStack {
                ACTelemetryOverlay(telemetry: acTelemetry, detailsOnly: true)
                    .background(Color.black.ignoresSafeArea())
                    .navigationTitle("遊戲遙測")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("關閉", systemImage: "xmark") { showGameDetails = false }
                        }
                    }
            }
            .preferredColorScheme(.dark)
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSpeedSource) {
            ACConnectionSheet(host: $acComputerHost, gameMode: acEnabled, connect: {
                acEnabled = true
                acTelemetry.connect(host: acComputerHost)
            }, useGPS: {
                acEnabled = false
                acTelemetry.disconnect()
            })
            .presentationDetents([.medium, .large])
        }
        .onChange(of: acTelemetry.isReceiving) { _, _ in
            lastKnownSpeed = acTelemetry.isReceiving ? (acTelemetry.sample?.speed ?? 0) : max(0, locationManager.smoothedSpeed)
            speedRoller.setDisplay(displaySpeed)
            syncGpsLostState()
            startActiveParallax()
        }
        .onReceive(acTelemetry.$sample) { sample in
            if let sample { lastKnownSpeed = sample.speed }
        }
        .overlay {
            if !instrumentsHidden {
                GeometryReader { geo in
                    let landscape = geo.size.width > geo.size.height
                    let activeWidth = isDuoPartiallyOpen && landscape ? geo.size.width / 2 : geo.size.width
                    let activeHeight = isDuoPartiallyOpen && !landscape ? geo.size.height / 2 : geo.size.height
                    instrumentControls
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .frame(width: activeWidth, height: activeHeight, alignment: .bottomLeading)
                }
            }
        }
        .statusBarHidden(true)
        .toolbar(instrumentsHidden ? .hidden : .automatic, for: .tabBar)
        // 偵測螢幕方向變化，同步視差旋轉補償
        .background {
            GeometryReader { geo in
                let isLandscape = geo.size.width > geo.size.height
                // 橫屏時把 gravity 向量旋轉 ±90°，令視差方向跟螢幕一致
                Color.clear
                    .onAppear {
                        syncScreenRotation(landscape: isLandscape)
                        isLandscapeLayout = isLandscape
                    }
                    .onChange(of: isLandscape) { _, newValue in
                        syncScreenRotation(landscape: newValue)
                        isLandscapeLayout = newValue
                    }
            }
        }
        .onAppear {
            startActiveParallax()
            syncParallaxFrameRate()
            // 時速數字逐格滾動：卡爾曼開關開啟時以螢幕最高刷新率插值
            lastKnownSpeed = acTelemetry.isReceiving ? (acTelemetry.sample?.speed ?? 0) : max(0, locationManager.smoothedSpeed)
            speedRoller.setDisplay(lastKnownSpeed)
            speedRoller.targetProvider = { [lm = locationManager, telemetry = acTelemetry] in
                if telemetry.isReceiving { return telemetry.sample?.speed }
                // 失聯就回傳 nil 凍結顯示（隧道入面靠 lastLocation 年齡判定，
                // 唔係靠 gpsQuality——冇定位回調時 quality 唔會變）
                return lm.isGPSLost ? nil : lm.predictedSpeed()
            }
            if kalmanSmoothingEnabled {
                speedRoller.start()
            }
        }
        .onDisappear {
            timePhaseManager.stop()
            tiltMotion.stop()
            gForceMotion.stop()
            speedRoller.stop()
        }
        .onChange(of: kalmanSmoothingEnabled) { _, enabled in
            if enabled {
                speedRoller.start()
            } else {
                speedRoller.stop()
            }
        }
        .onChange(of: parallaxMode) { _, _ in startActiveParallax() }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            syncScreenRotation(landscape: isLandscapeLayout)
        }
        .onChange(of: speedParallaxEnabled) { _, enabled in
            startActiveParallax()
            syncParallaxFrameRate()
        }
        .onChange(of: locationManager.smoothedSpeed) { _, newSpeed in
            // GPS 正常時持續更新最後已知時速（用 Double 驅動平滑漸變）；
            // 失聯時唔更新 = 凍結喺最後已知時速
            if !locationManager.isGPSLost && !acTelemetry.isReceiving {
                withAnimation(.easeInOut(duration: 0.25)) {
                    lastKnownSpeed = max(0, newSpeed)
                }
            }
        }
        // GPS 失聯巡邏：隧道入面一個定位回調都冇，gpsQuality 唔會變、
        // smoothedSpeed 亦唔會變，所以要定時用「冇新 fix」年齡判定失聯，
        // 先可以喺冇 callback 嘅情況下照樣凍結顯示＋變暗
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                syncGpsLostState()
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            }
        }
        // 有新 fix 都校正一次：就算巡邏 timer 失效，
        // 開緊車有數據就唔會俾半透明狀態困住
        .onReceive(locationManager.$lastLocation) { _ in
            syncGpsLostState()
        }
        // 回前景：換個新巡邏 timer（舊嗰個懸停後可能已靜止）＋即刻校正一次；
        // 仲有 CADisplayLink／CoreMotion 懸停之後有機會唔再 fire
        // （orb 動畫靜止、滾動數字停），全部重新起過
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                timePhaseManager.stop()
                tiltMotion.stop()
                gForceMotion.stop()
                speedRoller.stop()
                return
            }
            guard phase == .active else { return }
            syncGpsLostState()
            if kalmanSmoothingEnabled {
                speedRoller.restart()
            }
            startActiveParallax()
            syncParallaxFrameRate()
        }
        .onReceive(locationManager.$speed) { newSpeed in
            guard sfxAccelerationEnabled, !acTelemetry.isReceiving else { return }
            let now = Date()
            let dt = now.timeIntervalSince(lastSpeedSampleAt)
            let prev = lastSpeedSample
            lastSpeedSampleAt = now
            lastSpeedSample = newSpeed
            
            if newSpeed <= 1 {
                accelArmedFromStop = true
                return
            }
            
            guard accelArmedFromStop else { return }
            guard now >= accelerationCooldownUntil else { return }
            guard dt > 0.05, dt < 2.0 else { return }
            
            let dv = newSpeed - prev
            guard dv > 3 else { return }
            
            let accel = dv / dt
            if newSpeed >= 6, accel >= 6 {
                accelArmedFromStop = false
                accelerationCooldownUntil = now.addingTimeInterval(1.6)
                sfxPlayer.playAccelerationBurst()
            }
        }
    }

    // MARK: - Computer telemetry switch

    private var computerControl: some View {
        let tint: Color = !acEnabled ? .green : acTelemetry.isReceiving ? .purple : .yellow
        return Button(action: toggleComputerConnection) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
        }
            .buttonStyle(.glass)
            .modifier(GorillaMapControlAppearance())
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.4)
                    .onEnded { _ in showSpeedSource = true }
            )
            .accessibilityIdentifier("computerTelemetrySwitch")
            .accessibilityLabel(String(localized: "電腦遙測"))
            .accessibilityValue(acEnabled ? acTelemetry.status : String(localized: "未連線"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { toggleComputerConnection() }
            .accessibilityAction(named: Text("連線設定")) { showSpeedSource = true }
    }

    private func toggleComputerConnection() {
        // A long press opens settings; releasing it must not also toggle connection.
        guard !showSpeedSource else { return }
        if !acEnabled && acComputerHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            showSpeedSource = true
        } else {
            acEnabled.toggle()
        }
    }

    private var instrumentControls: some View {
        HStack(spacing: 10) {
            Button(action: cycleMapPresentation) {
                Image(systemName: showSatellite ? "binoculars.fill" : showMap ? "map.fill" : "map")
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .modifier(GorillaMapControlAppearance())
            .accessibilityLabel("地圖")
            .accessibilityIdentifier("speedMapPresentationSwitch")
            computerControl
            if acEnabled {
                Button { showGameDetails = true } label: {
                    Image(systemName: "chart.bar.xaxis")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("遊戲遙測")
                .accessibilityIdentifier("acTelemetryDetails")
            }
        }
        .foregroundStyle(instrumentForeground)
    }

    private var usesGrayMapText: Bool {
        colorScheme == .light && showMap && !showSatellite && !darkGlassEnabled
    }

    private var instrumentForeground: Color {
        if usesGrayMapText { return Color(red: 0.33, green: 0.36, blue: 0.39) }
        if showMap && !acTelemetry.isReceiving { return .white }
        return colorGroup == .m3Concept ? Color(hex: M3ConceptPalette.paper)
            : colorScheme == .dark || colorGroup == .darkKnight ? .white : .black
    }

    private func speedCardDisplay(compact: Bool) -> some View {
        GeometryReader { geo in
        let motionPadding: CGFloat = speedParallaxEnabled ? 12 : 0
        let font: Font = .system(size: min(compact ? 72 : 96, max(20, (geo.size.height - 30 - 2 * motionPadding) / 1.25)), weight: .heavy, design: .rounded)
        return VStack(spacing: 2) {
            Spacer(minLength: 0)
            ZStack {
                if speedBlurEnabled {
                    ForEach([20, 10, 4], id: \.self) { radius in
                        SpeedDigitsText(roller: speedRoller, rolling: kalmanSmoothingEnabled,
                            fallback: lastKnownSpeed, unit: speedUnit, font: font,
                            color: instrumentForeground.opacity(0.12), hidden: speedNumberHidden)
                            .blur(radius: CGFloat(radius)).accessibilityHidden(true)
                    }
                }
                SpeedDigitsText(roller: speedRoller, rolling: kalmanSmoothingEnabled,
                    fallback: lastKnownSpeed, unit: speedUnit, font: font,
                    color: instrumentForeground.opacity(gpsLostAnim ? 0.3 : 1), hidden: speedNumberHidden)
                    .accessibilityIdentifier("speedDigits")
            }
            .modifier(SpeedParallaxModifier(
                enabled: speedParallaxEnabled,
                parallaxX: -parallaxX, parallaxY: -parallaxY,
                multiplier: parallaxMultiplier * (compact ? 0.75 : 1), verticalTravel: 6
            ))
            .padding(.vertical, motionPadding)
            Text(speedUnit.symbol).font(.system(size: geo.size.height < 100 ? 12 : 20)).opacity(speedNumberHidden ? 0 : 0.65)
                .accessibilityIdentifier("speedUnit")
            Spacer(minLength: 0)
            if showParallaxToggle && !instrumentsHidden { parallaxToggleCapsule }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onTapGesture(count: 2) { showParallaxToggle.toggle() }
        }
    }

    private func toggleInstruments() {
        withAnimation(.easeInOut(duration: 0.25)) {
            instrumentsHidden.toggle()
            showParallaxToggle = false
        }
    }

    // MARK: - 視差模式切換膠囊

    private var parallaxToggleCapsule: some View {
        HStack(spacing: 0) {
            ForEach([ParallaxMode.tilt, ParallaxMode.gforce], id: \.self) { mode in
                let isSelected = parallaxMode == mode
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        parallaxMode = mode
                    }
                    // 切換後延遲收起膠囊
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showParallaxToggle = false
                        }
                    }
                } label: {
                    Text(mode == .tilt ? String(localized: "傾斜") : String(localized: "G值"))
                        .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .overlay {
                                        Capsule()
                                            .fill(Color.white.opacity(0.15))
                                    }
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                }
        }
    }

    /// 校正 GPS 失聯顯示狀態（時速透明度＋凍結值）。
    /// 巡邏 timer、回前景、任何新定位都經呢度一次過同步，
    /// 唔會俾單一途徑失效就困住個顯示狀態。
    private func syncGpsLostState() {
        guard scenePhase == .active else { return }
        if acTelemetry.isReceiving {
            gpsLostAnim = false
            return
        }
        let lost = locationManager.isGPSLost
        if lost != gpsLostAnim {
            withAnimation(.easeInOut(duration: 0.5)) {
                gpsLostAnim = lost
            }
        }
        if !lost, lastKnownSpeed != max(0, locationManager.smoothedSpeed) {
            withAnimation(.easeInOut(duration: 0.25)) {
                lastKnownSpeed = max(0, locationManager.smoothedSpeed)
            }
        }
    }

    /// 視差 60Hz 足夠跟隨手部動作；圓點 canvas 仍獨立用螢幕刷新率。
    /// 降低 CoreMotion 喺主線程發佈數值造成嘅 SwiftUI 重算。
    private func syncParallaxFrameRate() {
        let fps = 60.0
        tiltMotion.setUpdateRate(fps)
        gForceMotion.setUpdateRate(30)
    }

    private func syncScreenRotation(landscape: Bool) {
        let orientation = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?.interfaceOrientation
        let angle: Double
        switch orientation {
        case .landscapeLeft: angle = .pi / 2
        case .landscapeRight: angle = -.pi / 2
        case .portraitUpsideDown: angle = .pi
        default: angle = landscape ? .pi / 2 : 0
        }
        tiltMotion.setScreenRotation(angle)
        gForceMotion.setScreenRotation(angle)
    }

    /// 根據當前模式啟動對應嘅 motion manager
    private func startActiveParallax() {
        guard scenePhase == .active else { return }
        if acTelemetry.isReceiving { gForceMotion.stop() }
        else { gForceMotion.start() }
        if speedParallaxEnabled && parallaxMode == .tilt { tiltMotion.start() }
        else { tiltMotion.stop() }
    }

    private var highAltitudeCamera: MKMapCamera? {
        let camera = MKMapCamera()
        camera.centerCoordinate = locationManager.mapReferenceLocation?.coordinate
            ?? CLLocationCoordinate2D(latitude: 22.3193, longitude: 114.1694)
        camera.centerCoordinateDistance = 80000
        return camera
    }
}

// MARK: - 陀螺儀傾斜視差

/// 用 CoreMotion 嘅 gravity vector 讀取手機傾斜，輸出平滑後嘅 -1…1 傾斜值
/// 畀視差效果用。啟動後首半秒收集基準姿態，之後所有位移都係相對於
/// 用戶當時點樣揸住部機 —— 唔係絕對水平，車上斜住用都正常。
///
/// 自動歸零：如果部機連續 5 秒冇明顯移動（0.5 秒窗口內位移低於閾值），
/// 基準姿態會慢慢校準返去當前姿勢，視差效果隨之平滑歸零；
/// 一旦再次移動，立刻停止歸零、以新基準繼續正常響應。
final class TiltParallaxMotion: ObservableObject {
    /// -1…1：+ = 右邊傾低（相對於基準姿態）
    @Published private(set) var tiltX: Double = 0
    /// -1…1：+ = 頂部向後傾（相對於基準姿態）
    @Published private(set) var tiltY: Double = 0

    private let motion = CMMotionManager()
    private var baselineX: Double = 0
    private var baselineY: Double = 0
    private var warmupSamples: [(x: Double, y: Double)] = []
    private var warmedUp = false

    /// 靜止偵測用嘅近 0.5 秒樣本緩衝
    private var recentSamples: [(t: TimeInterval, x: Double, y: Double)] = []
    /// 進入靜止狀態嘅時刻；nil = 而家有明顯移動
    private var stillSince: TimeInterval?

    /// 陀螺儀取樣率 —— 同背景動畫幀率對齊（預設 60Hz）
    private var updateRate: Double = 60

    /// 螢幕相對裝置嘅旋轉角（弧度）：橫屏 = ±π/2，豎屏 = 0
    private var screenRotation: Double = 0

    /// 靈敏度：約 25° 傾斜 = 滿幅
    private let gain = 2.2
    /// 每幀 lerp 比例（以 60Hz 為基準），令移動順滑唔會抖
    private let smoothing = 0.15
    /// 靜止偵測窗口：同 0.5 秒前嘅樣本比較
    private let stillWindow: TimeInterval = 0.5
    /// 窗口內位移低於呢個值（約 2.6°）視為冇郁
    private let stillThreshold = 0.045
    /// 連續靜止幾耐之後開始歸零
    private let recenterDelay: TimeInterval = 5.0
    /// 歸零時基準向當前姿態靠攏嘅每幀比例（約 1-2 秒內完成）
    private let recenterRate = 0.03

    func start() {
        guard motion.isDeviceMotionAvailable else { return }
        warmedUp = false
        warmupSamples.removeAll()
        recentSamples.removeAll()
        stillSince = nil
        motion.deviceMotionUpdateInterval = 1.0 / updateRate
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] deviceMotion, _ in
            guard let self, let deviceMotion else { return }
            let g = deviceMotion.gravity
            let now = Date().timeIntervalSinceReferenceDate

            // 將裝置坐標系嘅 gravity 旋轉到螢幕坐標系：
            // 豎屏時 screenRotation = 0（不變），橫屏時 ±π/2
            let cosR = cos(self.screenRotation)
            let sinR = sin(self.screenRotation)
            let gx = g.x * cosR - g.y * sinR   // 螢幕左右
            let gy = g.x * sinR + g.y * cosR   // 螢幕上下

            // 首 30 個樣本（約 0.5 秒）建立基準
            if !self.warmedUp {
                self.warmupSamples.append((gx, gy))
                if self.warmupSamples.count >= 30 {
                    let n = Double(self.warmupSamples.count)
                    self.baselineX = self.warmupSamples.map(\.x).reduce(0, +) / n
                    self.baselineY = self.warmupSamples.map(\.y).reduce(0, +) / n
                    self.warmedUp = true
                    self.stillSince = now
                }
                return
            }

            // 靜止偵測：同 0.5 秒前嘅樣本比，位移細 = 冇郁
            self.recentSamples.append((now, gx, gy))
            while let first = self.recentSamples.first, now - first.t > self.stillWindow {
                self.recentSamples.removeFirst()
            }
            if let oldest = self.recentSamples.first {
                let drift = sqrt(pow(gx - oldest.x, 2) + pow(gy - oldest.y, 2))
                if drift > self.stillThreshold {
                    self.stillSince = nil
                } else if self.stillSince == nil {
                    self.stillSince = now
                }
            }

            // 連續 5 秒冇郁 → 基準慢慢校準返去當前姿態，視差平滑歸零
            if let since = self.stillSince, now - since >= self.recenterDelay {
                self.baselineX += (gx - self.baselineX) * self.recenterRate
                self.baselineY += (gy - self.baselineY) * self.recenterRate
            }

            // 幀率補償：任何取樣率下 lerp 時間常數同 60Hz 一致，手感不變
            let alpha = 1 - pow(1 - self.smoothing, 60.0 / self.updateRate)
            let targetX = Self.clamp((gx - self.baselineX) * self.gain)
            let targetY = Self.clamp((gy - self.baselineY) * self.gain)
            self.tiltX += (targetX - self.tiltX) * alpha
            self.tiltY += (targetY - self.tiltY) * alpha
        }
    }

    /// 設定陀螺儀取樣率（同背景動畫幀率對齊），運行中即時生效。
    func setUpdateRate(_ fps: Double) {
        guard fps > 0, fps != updateRate else { return }
        updateRate = fps
        if motion.isDeviceMotionActive {
            motion.deviceMotionUpdateInterval = 1.0 / fps
        }
    }

    /// 設定螢幕旋轉角度（弧度），令視差方向跟隨螢幕方向而非裝置坐標系。
    /// 豎屏 = 0，橫屏（home 鍵右）= π/2，橫屏（home 鍵左）= -π/2
    func setScreenRotation(_ radians: Double) {
        screenRotation = radians
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        warmedUp = false
        warmupSamples.removeAll()
        recentSamples.removeAll()
        stillSince = nil
        tiltX = 0
        tiltY = 0
    }

    private static func clamp(_ v: Double) -> Double { max(-1, min(1, v)) }
}

// MARK: - G-force 視差動畫

/// 用 CoreMotion 嘅 userAcceleration 讀取車輛動態 G-force（加速／減速／轉彎），
/// 輸出平滑後嘅 -1…1 值畀視差效果用。
///
/// 方向映射（跟車輛慣性一致）：
///   - 煞車 → gForceY 正（畫面向前傾）
///   - 加速 → gForceY 負（畫面向後傾）
///   - 左轉 → gForceX 負（畫面向左傾）
///   - 右轉 → gForceX 正（畫面向右傾）
final class GForceParallaxMotion: ObservableObject {
    static let shared = GForceParallaxMotion()
    @Published private(set) var reading: SpeedGForce?
    /// -1…1：+ = 右轉 G-force
    @Published private(set) var gForceX: Double = 0
    /// -1…1：+ = 煞車 G-force（向前）
    @Published private(set) var gForceY: Double = 0

    private let motion = CMMotionManager()
    private var updateRate: Double = 30
    private var screenRotation: Double = 0

    /// 靈敏度：約 0.5g = 滿幅（激烈煞車／急轉彎）
    private let gain: Double = 2.0
    /// 每幀 lerp 比例（以 60Hz 為基準）
    private let smoothing: Double = 0.08
    private var forceFilter = SpeedGForceFilter()
    private var lastPublishedTime: TimeInterval?
    private var consumers: Set<String> = []

    func start(consumer: String = "speed") {
        consumers.insert(consumer)
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        // Filter before publishing at the UI rate to avoid aliasing engine vibration.
        motion.deviceMotionUpdateInterval = 1.0 / 120
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] dm, _ in
            guard let self else { return }
            guard let dm else { self.resetReadings(); return }
            let ua = dm.userAcceleration
            let projected = SpeedGForce.project(acceleration: SIMD3(ua.x, ua.y, ua.z),
                gravity: SIMD3(dm.gravity.x, dm.gravity.y, dm.gravity.z), rotation: self.screenRotation,
                angularVelocity: SIMD3(dm.rotationRate.x, dm.rotationRate.y, dm.rotationRate.z))
            let filtered = self.forceFilter.update(projected, at: dm.timestamp)
            let elapsed = self.lastPublishedTime.map { dm.timestamp - $0 } ?? (1 / self.updateRate)
            guard elapsed >= 1 / self.updateRate - 0.001 else { return }
            self.lastPublishedTime = dm.timestamp
            self.reading = filtered
            let targetX = Self.clamp((filtered?.lateral ?? 0) * self.gain)
            let targetY = Self.clamp(-(filtered?.longitudinal ?? 0) * self.gain)
            let alpha = 1 - pow(1 - self.smoothing, 60 * elapsed)
            self.gForceX += (targetX - self.gForceX) * alpha
            self.gForceY += (targetY - self.gForceY) * alpha
        }
    }

    func stop(consumer: String = "speed") {
        consumers.remove(consumer)
        guard consumers.isEmpty else { return }
        motion.stopDeviceMotionUpdates()
        resetReadings()
    }

    private func resetReadings() {
        forceFilter = SpeedGForceFilter()
        lastPublishedTime = nil
        reading = nil
        gForceX = 0
        gForceY = 0
    }

    func setUpdateRate(_ fps: Double) {
        guard fps > 0, fps != updateRate else { return }
        updateRate = fps
    }

    func setScreenRotation(_ radians: Double) {
        if radians != screenRotation { resetReadings() }
        screenRotation = radians
    }

    private static func clamp(_ v: Double) -> Double { max(-1, min(1, v)) }
}

// MARK: - 視差模式

enum ParallaxMode: String {
    case tilt    // 傾斜（手機傾斜）
    case gforce  // G-force（車輛加速度）
}


// MARK: - 時速數字（逐格滾動插值）

/// 時速數字 Text：卡爾曼開關開啟時由 NumberRoller 以螢幕最高刷新率
/// 逐格滾動插值（數字 1→2→3→… 逐格滾上去，同「卡爾曼濾波測試」頁一致），
/// 關閉時跟隨顯示值直接跳變（保留 0.25s 漸變）。
/// 獨立葉子 View：滾動時只有呢個 Text 重繪，唔會重算成個 SpeedView。
///
/// 數字顯示要穩定唔抖：font 用 monospacedDigit（每個數字位闊度一致，
/// 數字轉變唔會成串「微微位移」），而且唔加 .numericText() 轉場 ——
/// NumberRoller 本身已經逐格滾緊，再疊轉場會令每個整數變化都打斷重播，
/// 數字會喺原位不停抖（每次轉邊個位、向邊個方向都唔同：上下／左下右上）。
private struct SpeedDigitsText: View {
    @ObservedObject var roller: NumberRoller
    /// true = 逐格滾動插值；false = 直接跳變
    let rolling: Bool
    /// 滾動關閉時顯示嘅值
    let fallback: Double
    let unit: SpeedUnit
    var font: Font = .system(size: 96, weight: .heavy, design: .rounded)
    let color: Color
    /// 隱藏時速數字（原位隱形，佈局照舊）
    let hidden: Bool

    private var value: Int { Int(unit.value(fromKmh: rolling ? roller.display : fallback)) }

    var body: some View {
        Text("\(value)")
            .font(font.monospacedDigit())
            .lineLimit(1).minimumScaleFactor(0.45)
            .foregroundColor(color)
            .opacity(hidden ? 0 : 1)
    }
}

// MARK: - 時速數字視差條件修飾器


private struct SpeedParallaxModifier: ViewModifier {
    let enabled: Bool
    let parallaxX: Double
    let parallaxY: Double
    let multiplier: Double
    var verticalTravel: Double = 20

    func body(content: Content) -> some View {
        if enabled {
            content
                .rotation3DEffect(.degrees(parallaxX * 12 * multiplier), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
                .rotation3DEffect(.degrees(parallaxY * 12 * multiplier), axis: (x: 1, y: 0, z: 0), perspective: 0.35)
                .offset(x: parallaxX * -20 * multiplier, y: parallaxY * -verticalTravel * multiplier)
                .transaction { $0.animation = nil }
        } else {
            content
        }
    }
}
