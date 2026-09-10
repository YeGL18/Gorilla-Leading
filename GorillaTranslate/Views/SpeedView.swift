import SwiftUI
import MapKit
import CoreMotion

struct SpeedView: View {
    @EnvironmentObject private var locationManager: LocationManager
    @StateObject private var timePhaseManager = TimePhaseManager()
    @StateObject private var sfxPlayer = SFXPlayer()
    @StateObject private var tiltMotion = TiltParallaxMotion()
    @StateObject private var gForceMotion = GForceParallaxMotion()
    @AppStorage("parallaxMode") private var parallaxMode: ParallaxMode = .tilt
    @State private var showParallaxToggle = false
    @AppStorage("sfxAccelerationEnabled") private var sfxAccelerationEnabled: Bool = true

    /// 當前視差 X 值（-1…1），根據模式切換來源
    private var parallaxX: Double {
        parallaxMode == .gforce ? gForceMotion.gForceX : tiltMotion.tiltX
    }
    /// 當前視差 Y 值（-1…1），根據模式切換來源
    private var parallaxY: Double {
        parallaxMode == .gforce ? gForceMotion.gForceY : tiltMotion.tiltY
    }

    /// G 值模式下視差效果倍數（比傾斜模式更強）
    private var parallaxMultiplier: Double {
        parallaxMode == .gforce ? 1.8 : 1.0
    }

    /// 膠囊彈出時模糊陰影倍數
    private var blurShadowMultiplier: Double {
        showParallaxToggle ? 1.6 : 1.0
    }
    @AppStorage("colorSchemeIndex") private var colorSchemeIndex: Int = 0
    @AppStorage("orbMasterEnabled") private var orbMasterEnabled: Bool = true
    @AppStorage("orbBackgroundSpeed") private var orbBackgroundSpeed: Bool = true
    @AppStorage("useTimeBasedOrb") private var useTimeBasedOrb: Bool = false
    @AppStorage("darkKnightMode") private var darkKnightMode: Bool = false
    @AppStorage("mapStyleIndex") private var mapStyleIndex: Int = 0
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var accelArmedFromStop: Bool = true
    @State private var lastSpeedSample: Double = 0
    @State private var lastSpeedSampleAt: Date = Date()
    @State private var accelerationCooldownUntil: Date = .distantPast

    /// GPS 失聯時保留最後已知時速
    @State private var lastKnownSpeed: Double = 0
    /// GPS 失聯動畫狀態（用於透明度漸變）
    @State private var gpsLostAnim: Bool = false

    /// 呼吸動畫：true/false 交替驅動透明度脈動
    @State private var breatheIn = false

    let showMap: Bool
    let animationClock: AnimationClock
    @Binding var mapCamera: MKMapCamera?

    // 專注模式
    @Binding var focusMode: FocusModeLevel?
    @Binding var focusFrameRate: FocusFrameRate
    var onEnterFocus: (FocusModeLevel, FocusFrameRate) -> Void
    var onExitFocus: () -> Void
    @State private var showFocusSheet = false

    var body: some View {
        ZStack {
            if showMap {
                ZStack {
                    ReadOnlyMapView(camera: highAltitudeCamera, mapStyleIndex: mapStyleIndex)
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
                                .init(color: .black.opacity(0.75), location: 1)
                            ]),
                            center: .center,
                            startRadius: min(w, h) * 0.25,
                            endRadius: max(w, h) * 0.65
                        )
                        .ignoresSafeArea()
                    }
                    .allowsHitTesting(false)
                }
            } else if darkKnightMode {
                Color.black.ignoresSafeArea()
            } else {
                AnimatedBackground(clock: animationClock, colorSchemeIndex: colorSchemeIndex, isVoiceRecording: false, orbEnabled: orbMasterEnabled && orbBackgroundSpeed, useTimeBasedOrb: orbMasterEnabled && orbBackgroundSpeed && useTimeBasedOrb, phaseManager: timePhaseManager)
                    .ignoresSafeArea()
            }

            GeometryReader { dotGeo in
                // canvas 以 1.4 倍畫面尺寸居中（唔係放大：圓點大小／密度不變，
                // 數量多咗近一倍），四邊各留 20% 緩衝 ——
                // 視差旋轉＋位移任何角度都唔會露邊。
                DotMatrixWebView(speed: Binding(
                    get: { locationManager.speed },
                    set: { _ in }
                ), canvasScale: 1.0)
                .frame(width: dotGeo.size.width * 1.4, height: dotGeo.size.height * 1.4)
                .position(x: dotGeo.size.width / 2, y: dotGeo.size.height / 2)
            }
            .ignoresSafeArea(edges: .all)
            // 陀螺儀視差（深層）：圓點平面朝傾斜反方向擺動並做 3D 透視旋轉，
            // 同前景文字形成前後深度。G 值模式效果更強。
            .rotation3DEffect(.degrees(parallaxX * 12 * parallaxMultiplier), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
            .rotation3DEffect(.degrees(parallaxY * 12 * parallaxMultiplier), axis: (x: 1, y: 0, z: 0), perspective: 0.35)
            .offset(x: parallaxX * -20 * parallaxMultiplier, y: parallaxY * -20 * parallaxMultiplier)

            GeometryReader { geo in
                let landscape = geo.size.width > geo.size.height
                let textColor: Color = colorScheme == .dark ? .white : .black
                let speedText = "\(Int(lastKnownSpeed))"
                let speedOpacity: Double = gpsLostAnim ? 0.3 : 1.0
                ZStack {
                    // 模糊光晕层（3层，越远越淡）— 陀螺儀視差中景：跟隨傾斜擺動，幅度少於清晰層
                    // 膠囊彈出時模糊陰影更強
                    ForEach([20, 10, 4], id: \.self) { blurRadius in
                        let baseOpacity = blurRadius == 20 ? 0.08 : blurRadius == 10 ? 0.12 : 0.2
                        let opacity = baseOpacity * blurShadowMultiplier
                        let adjustedBlur = CGFloat(blurRadius) * blurShadowMultiplier
                        VStack(spacing: 4) {
                            Spacer()
                            Text(speedText)
                                .font(.system(size: 96, weight: .heavy, design: .rounded))
                                .foregroundColor(textColor.opacity(opacity * speedOpacity))
                            Text("km/h")
                                .font(.title3)
                                .foregroundColor(textColor.opacity(opacity * 0.6 * speedOpacity))
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .blur(radius: adjustedBlur)
                        .offset(x: parallaxX * 14 * parallaxMultiplier, y: parallaxY * 14 * parallaxMultiplier + (showParallaxToggle ? -10 : 0))
                    }
                    // 清晰文字层 — 陀螺儀視差前景：2D 位移，幅度最大。G 值模式效果更強。
                    VStack(spacing: 4) {
                        Spacer()
                        Text(speedText)
                            .font(.system(size: 96, weight: .heavy, design: .rounded))
                            .foregroundColor(textColor.opacity(0.6 * speedOpacity))
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.25), value: Int(lastKnownSpeed))
                        Text("km/h")
                            .font(.title3)
                            .foregroundColor(textColor.opacity(0.6 * speedOpacity))
                        // 視差模式切換膠囊
                        if showParallaxToggle {
                            parallaxToggleCapsule
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(x: parallaxX * 24 * parallaxMultiplier, y: parallaxY * 24 * parallaxMultiplier)
                    // 雙擊時速數字：彈出視差模式切換膠囊
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showParallaxToggle.toggle()
                        }
                    }
                }
                .offset(y: landscape ? 20 : 0)
            }
        }
        .overlay(alignment: .bottomLeading) {
            focusModeButton
        }
        .sheet(isPresented: $showFocusSheet) {
            FocusModeSheet(initialLevel: focusMode, initialFrameRate: focusFrameRate) { level, fps in
                onEnterFocus(level, fps)
                showFocusSheet = false
            }
            .presentationDetents([.fraction(0.61), .large])
            .presentationDragIndicator(.visible)
        }
        .statusBarHidden(true)
        // 偵測螢幕方向變化，同步視差旋轉補償
        .background {
            GeometryReader { geo in
                let isLandscape = geo.size.width > geo.size.height
                // 橫屏時把 gravity 向量旋轉 ±90°，令視差方向跟螢幕一致
                Color.clear
                    .onAppear {
                        let angle: Double = isLandscape ? .pi / 2 : 0
                        tiltMotion.setScreenRotation(angle)
                        gForceMotion.setScreenRotation(angle)
                    }
                    .onChange(of: isLandscape) { _, newValue in
                        let angle: Double = newValue ? .pi / 2 : 0
                        tiltMotion.setScreenRotation(angle)
                        gForceMotion.setScreenRotation(angle)
                    }
            }
        }
        .onAppear {
            if orbMasterEnabled && orbBackgroundSpeed && useTimeBasedOrb {
                timePhaseManager.start()
            }
            startActiveParallax()
            syncParallaxFrameRate()
        }
        .onDisappear {
            timePhaseManager.stop()
            tiltMotion.stop()
            gForceMotion.stop()
        }
        // 視差取樣率跟背景動畫幀率對齊：進出專注模式／改幀率都即時生效
        .onChange(of: focusMode) { _, newMode in
            syncParallaxFrameRate()
            // 呼吸動畫：進入專注模式時啟動脈動，退出時停止
            if newMode != nil {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    breatheIn = true
                }
            } else {
                breatheIn = false
            }
        }
        .onChange(of: focusFrameRate) { _, _ in syncParallaxFrameRate() }
        .onChange(of: parallaxMode) { _, _ in startActiveParallax() }
        .onChange(of: locationManager.smoothedSpeed) { _, newSpeed in
            // GPS 正常時持續更新最後已知時速（用 Double 驅動平滑漸變）
            let gpsLost = locationManager.gpsQuality == .bad || locationManager.gpsQuality == .unknown
            if !gpsLost {
                withAnimation(.easeInOut(duration: 0.25)) {
                    lastKnownSpeed = max(0, newSpeed)
                }
            }
        }
        .onChange(of: locationManager.gpsQuality) { _, newQuality in
            let gpsLost = newQuality == .bad || newQuality == .unknown
            if !gpsLost {
                withAnimation(.easeInOut(duration: 0.25)) {
                    lastKnownSpeed = max(0, locationManager.smoothedSpeed)
                }
            }
            // GPS 狀態切換時播放透明度漸變動畫
            withAnimation(.easeInOut(duration: 0.5)) {
                gpsLostAnim = gpsLost
            }
        }
        .onReceive(locationManager.$speed) { newSpeed in
            guard sfxAccelerationEnabled else { return }
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

    // MARK: - 專注模式按鈕（左下角）

    private var focusModeButton: some View {
        let active = focusMode != nil
        let glowColor = focusMode?.color ?? .green
        let baseColor: Color = colorScheme == .dark ? .white : .black
        // 呼吸曲線：breatheIn=true 時亮、false 時暗
        let iconOpacity     = active ? (breatheIn ? 1.0 : 0.7) : 1.0
        let innerGlowAlpha  = active ? (breatheIn ? 0.85 : 0.3) : 0.0
        let outerGlowAlpha  = active ? (breatheIn ? 0.55 : 0.15) : 0.0
        let innerRadius     = active ? (breatheIn ? 7 : 4) : 0
        let outerRadius     = active ? (breatheIn ? 14 : 8) : 0
        return Button {
            if active {
                onExitFocus()
            } else {
                showFocusSheet = true
            }
        } label: {
            // 規格同主頁左側按鈕一致：44×44、icon 20pt、液態玻璃
            Image(systemName: active ? "leaf.fill" : "leaf")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(active ? glowColor.opacity(iconOpacity) : baseColor)
                .shadow(color: active ? glowColor.opacity(innerGlowAlpha) : .clear, radius: CGFloat(innerRadius))
                .shadow(color: active ? glowColor.opacity(outerGlowAlpha) : .clear, radius: CGFloat(outerRadius))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glass)
        // 長按：任何時候都打開選擇頁（方便專注中切換模式）
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4)
                .onEnded { _ in showFocusSheet = true }
        )
        .padding(.leading, 16)
        .padding(.bottom, 12)
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

    /// 陀螺儀視差取樣率 = 背景動畫幀率：專注模式開住就用所選幀率，
    /// 否則預設 60Hz，同動畫時鐘保持一致。
    private func syncParallaxFrameRate() {
        let fps: Double = focusMode != nil ? Double(focusFrameRate.rawValue) : 60
        tiltMotion.setUpdateRate(fps)
        gForceMotion.setUpdateRate(fps)
    }

    /// 根據當前模式啟動對應嘅 motion manager
    private func startActiveParallax() {
        if parallaxMode == .gforce {
            tiltMotion.stop()
            gForceMotion.start()
        } else {
            gForceMotion.stop()
            tiltMotion.start()
        }
    }

    private var highAltitudeCamera: MKMapCamera? {
        guard let location = locationManager.manager.location else { return nil }
        let camera = MKMapCamera()
        camera.centerCoordinate = location.coordinate
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
    /// -1…1：+ = 右轉 G-force
    @Published private(set) var gForceX: Double = 0
    /// -1…1：+ = 煞車 G-force（向前）
    @Published private(set) var gForceY: Double = 0

    private let motion = CMMotionManager()
    private var updateRate: Double = 60
    private var screenRotation: Double = 0

    /// 靈敏度：約 0.5g = 滿幅（激烈煞車／急轉彎）
    private let gain: Double = 2.0
    /// 每幀 lerp 比例（以 60Hz 為基準）
    private let smoothing: Double = 0.08
    /// 死區：低於此值嘅微小震動忽略
    private let deadband: Double = 0.06

    func start() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / updateRate
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] dm, _ in
            guard let self, let dm else { return }
            let ua = dm.userAcceleration

            // 將裝置坐標系嘅加速度旋轉到螢幕坐標系
            let cosR = cos(self.screenRotation)
            let sinR = sin(self.screenRotation)
            let ax = ua.x * cosR - ua.y * sinR   // 螢幕左右
            let ay = ua.x * sinR + ua.y * cosR   // 螢幕上下

            // 死區過濾
            let filteredX = abs(ax) < self.deadband ? 0 : ax
            let filteredY = abs(ay) < self.deadband ? 0 : ay

            // 增益 + 限制
            let targetX = Self.clamp(filteredX * self.gain)
            let targetY = Self.clamp(filteredY * self.gain)

            // 幀率補償 lerp
            let alpha = 1 - pow(1 - self.smoothing, 60.0 / self.updateRate)
            self.gForceX += (targetX - self.gForceX) * alpha
            self.gForceY += (targetY - self.gForceY) * alpha
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        gForceX = 0
        gForceY = 0
    }

    func setUpdateRate(_ fps: Double) {
        guard fps > 0, fps != updateRate else { return }
        updateRate = fps
        if motion.isDeviceMotionActive {
            motion.deviceMotionUpdateInterval = 1.0 / fps
        }
    }

    func setScreenRotation(_ radians: Double) {
        screenRotation = radians
    }

    private static func clamp(_ v: Double) -> Double { max(-1, min(1, v)) }
}

// MARK: - 視差模式

enum ParallaxMode: String {
    case tilt    // 傾斜（手機傾斜）
    case gforce  // G-force（車輛加速度）
}

// MARK: - 專注模式選擇頁

/// 每次㩒專注按鈕都喺呢度揀：模式（平衡／輕度／極致）＋背景動畫幀率（60/120fps）
struct FocusModeSheet: View {
    let initialLevel: FocusModeLevel?
    let initialFrameRate: FocusFrameRate
    var onEnter: (FocusModeLevel, FocusFrameRate) -> Void

    @State private var selectedLevel: FocusModeLevel = .balanced
    @State private var fpsSliderValue: Double = 60
    /// 圖標彈跳動畫觸發器：設為對應 level 後 0.15 秒自動歸 nil
    @State private var animatingLevel: FocusModeLevel?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "專注模式"))
                    .font(.title2.bold())
                Text(String(localized: "閂走時速顯示以外嘅功能，減少耗電同發熱"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(FocusModeLevel.allCases) { level in
                    modeCard(level)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(String(localized: "背景動畫幀率"))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(Int(fpsSliderValue)) fps")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.15), value: fpsSliderValue)
                    }
                    Slider(value: $fpsSliderValue, in: 60...120, step: 30) {
                        Text(String(localized: "背景動畫幀率"))
                    } minimumValueLabel: {
                        Text("60")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } maximumValueLabel: {
                        Text("120")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tint(selectedLevel.color)
                    Text(String(localized: "120 fps 只喺 ProMotion 機型有效，會稍微增加耗電"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 4)

                Button {
                    onEnter(selectedLevel, FocusFrameRate(rawValue: Int(fpsSliderValue)) ?? .fps60)
                } label: {
                    Text(String(localized: "進入專注模式"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(selectedLevel.color)
                .padding(.top, 6)
            }
            .padding(20)
        }
        .onAppear {
            if let lvl = initialLevel { selectedLevel = lvl }
            fpsSliderValue = Double(initialFrameRate.rawValue)
        }
    }

    private func modeCard(_ level: FocusModeLevel) -> some View {
        let selected = selectedLevel == level
        let c = level.color
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
                selectedLevel = level
                animatingLevel = level
            }
            // 0.15 秒後歸 nil，下次㩒可以再觸發彈跳
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    animatingLevel = nil
                }
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: level.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(selected ? c : Color.secondary)
                    .scaleEffect(animatingLevel == level ? 1.35 : 1.0)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(level.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(level.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? c : Color.secondary.opacity(0.4))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? c.opacity(0.1) : Color.gray.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? c.opacity(0.6) : Color.clear, lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
