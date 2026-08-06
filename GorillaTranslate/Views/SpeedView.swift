import SwiftUI
import MapKit

struct SpeedView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var timePhaseManager = TimePhaseManager()
    @StateObject private var sfxPlayer = SFXPlayer()
    @AppStorage("sfxAccelerationEnabled") private var sfxAccelerationEnabled: Bool = true
    @AppStorage("colorSchemeIndex") private var colorSchemeIndex: Int = 0
    @AppStorage("orbMasterEnabled") private var orbMasterEnabled: Bool = true
    @AppStorage("orbBackgroundSpeed") private var orbBackgroundSpeed: Bool = true
    @AppStorage("useTimeBasedOrb") private var useTimeBasedOrb: Bool = false
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
                ReadOnlyMapView(camera: highAltitudeCamera)
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
                }
                .allowsHitTesting(false)
            } else {
                AnimatedBackground(clock: animationClock, colorSchemeIndex: colorSchemeIndex, isVoiceRecording: false, orbEnabled: orbMasterEnabled && orbBackgroundSpeed, useTimeBasedOrb: orbMasterEnabled && orbBackgroundSpeed && useTimeBasedOrb, phaseManager: timePhaseManager)
                    .ignoresSafeArea()
            }

            DotMatrixWebView(speed: Binding(
                get: { locationManager.speed },
                set: { _ in }
            ))
            .ignoresSafeArea(edges: .all)

            GeometryReader { geo in
                let landscape = geo.size.width > geo.size.height
                let textColor: Color = colorScheme == .dark ? .white : .black
                let speedText = "\(Int(locationManager.speed))"
                ZStack {
                    // 模糊光晕层（3层，越远越淡）
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
                    }
                    // 清晰文字层
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
                }
                .offset(y: landscape ? 20 : 0)
            }
        }
        .statusBarHidden(true)
        .onAppear {
            timePhaseManager.start()
        }
        .onDisappear {
            timePhaseManager.stop()
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
