import SwiftUI
import MapKit
import CoreMotion

struct SpeedView: View {
    @EnvironmentObject private var locationManager: LocationManager
    @StateObject private var timePhaseManager = TimePhaseManager()
    @StateObject private var sfxPlayer = SFXPlayer()
    @StateObject private var tiltMotion = TiltParallaxMotion()
    @AppStorage("sfxAccelerationEnabled") private var sfxAccelerationEnabled: Bool = true
    @AppStorage("colorSchemeIndex") private var colorSchemeIndex: Int = 0
    @AppStorage("orbMasterEnabled") private var orbMasterEnabled: Bool = true
    @AppStorage("orbBackgroundSpeed") private var orbBackgroundSpeed: Bool = true
    @AppStorage("useTimeBasedOrb") private var useTimeBasedOrb: Bool = false
    @AppStorage("mapStyleIndex") private var mapStyleIndex: Int = 0
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var accelArmedFromStop: Bool = true
    @State private var lastSpeedSample: Double = 0
    @State private var lastSpeedSampleAt: Date = Date()
    @State private var accelerationCooldownUntil: Date = .distantPast

    let showMap: Bool
    let animationClock: AnimationClock
    @Binding var mapCamera: MKMapCamera?

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
            } else {
                AnimatedBackground(clock: animationClock, colorSchemeIndex: colorSchemeIndex, isVoiceRecording: false, orbEnabled: orbMasterEnabled && orbBackgroundSpeed, useTimeBasedOrb: orbMasterEnabled && orbBackgroundSpeed && useTimeBasedOrb, phaseManager: timePhaseManager)
                    .ignoresSafeArea()
            }

            DotMatrixWebView(speed: Binding(
                get: { locationManager.speed },
                set: { _ in }
            ))
            .ignoresSafeArea(edges: .all)
            // 陀螺儀視差（深層）：圓點平面朝傾斜反方向擺動並做 3D 透視旋轉，
            // 同前景文字形成前後深度。canvas 本身已 scale(1.15)，旋轉不會露邊。
            .rotation3DEffect(.degrees(tiltMotion.tiltX * 7), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
            .rotation3DEffect(.degrees(tiltMotion.tiltY * 7), axis: (x: 1, y: 0, z: 0), perspective: 0.35)
            .offset(x: tiltMotion.tiltX * -12, y: tiltMotion.tiltY * -12)

            GeometryReader { geo in
                let landscape = geo.size.width > geo.size.height
                let textColor: Color = colorScheme == .dark ? .white : .black
                let speedText = "\(Int(locationManager.speed))"
                ZStack {
                    // 模糊光晕层（3层，越远越淡）— 陀螺儀視差中景：跟隨傾斜擺動，幅度少於清晰層
                    ForEach([20, 10, 4], id: \.self) { blurRadius in
                        let opacity = blurRadius == 20 ? 0.08 : blurRadius == 10 ? 0.12 : 0.2
                        VStack(spacing: 4) {
                            Spacer()
                            Text(speedText)
                                .font(.system(size: 96, weight: .heavy, design: .rounded))
                                .foregroundColor(textColor.opacity(opacity))
                            Text("km/h")
                                .font(.title3)
                                .foregroundColor(textColor.opacity(opacity * 0.6))
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .blur(radius: CGFloat(blurRadius))
                        .offset(x: tiltMotion.tiltX * 14, y: tiltMotion.tiltY * 14)
                    }
                    // 清晰文字层 — 陀螺儀視差前景：2D 位移，幅度最大
                    VStack(spacing: 4) {
                        Spacer()
                        Text(speedText)
                            .font(.system(size: 96, weight: .heavy, design: .rounded))
                            .foregroundColor(textColor.opacity(0.6))
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.15), value: Int(locationManager.speed))
                        Text("km/h")
                            .font(.title3)
                            .foregroundColor(textColor.opacity(0.6))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(x: tiltMotion.tiltX * 24, y: tiltMotion.tiltY * 24)
                }
                .offset(y: landscape ? 20 : 0)
            }
        }
        .statusBarHidden(true)
        .onAppear {
            timePhaseManager.start()
            tiltMotion.start()
        }
        .onDisappear {
            timePhaseManager.stop()
            tiltMotion.stop()
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
final class TiltParallaxMotion: ObservableObject {
    /// -1…1：+ = 右邊傾低
    @Published private(set) var tiltX: Double = 0
    /// -1…1：+ = 頂部向後傾（相對於基準姿態）
    @Published private(set) var tiltY: Double = 0

    private let motion = CMMotionManager()
    private var baselineY: Double?
    private var warmupSamples: [Double] = []

    /// 靈敏度：約 25° 傾斜 = 滿幅
    private let gain = 2.2
    /// 每幀 lerp 比例（60Hz），令移動順滑唔會抖
    private let smoothing = 0.15

    func start() {
        guard motion.isDeviceMotionAvailable else { return }
        baselineY = nil
        warmupSamples.removeAll()
        motion.deviceMotionUpdateInterval = 1.0 / 60.0
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] deviceMotion, _ in
            guard let self, let deviceMotion else { return }
            let g = deviceMotion.gravity

            // 首 30 個樣本（約 0.5 秒）建立基準
            if self.baselineY == nil {
                self.warmupSamples.append(g.y)
                if self.warmupSamples.count >= 30 {
                    self.baselineY = self.warmupSamples.reduce(0, +) / Double(self.warmupSamples.count)
                }
                return
            }

            let targetX = Self.clamp(g.x * self.gain)
            let targetY = Self.clamp((g.y - (self.baselineY ?? g.y)) * self.gain)
            self.tiltX += (targetX - self.tiltX) * self.smoothing
            self.tiltY += (targetY - self.tiltY) * self.smoothing
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        baselineY = nil
        warmupSamples.removeAll()
        tiltX = 0
        tiltY = 0
    }

    private static func clamp(_ v: Double) -> Double { max(-1, min(1, v)) }
}
