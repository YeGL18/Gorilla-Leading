import SwiftUI

struct LaunchAnimationSettingsSection: View {
    @AppStorage("launchAnimationEnabled") private var enabled = true

    var body: some View {
        Toggle(isOn: $enabled) {
            Label("啟動動畫", systemImage: "play.rectangle.on.rectangle")
        }
        .accessibilityIdentifier("launchAnimationEnabled")
    }
}

// MARK: - Morphing Transition Modifier

struct MorphingTransitionModifier: ViewModifier, Animatable {
    var blurRadius: CGFloat
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    /// Bell curve: 0→1 at midpoint, 1→0 at endpoints
    private var blurProgress: CGFloat {
        return progress > 0.5 ? abs(1.0 - progress) : progress
    }

    func body(content: Content) -> some View {
        content
            .blur(radius: blurRadius * blurProgress)
            .compositingGroup()
            .visualEffect { content, proxy in
                content.layerEffect(
                    ShaderLibrary.alphaThreshold(),
                    maxSampleOffset: proxy.size
                )
            }
    }
}

extension View {
    func morphingTransition(blurRadius: CGFloat, progress: CGFloat) -> some View {
        modifier(MorphingTransitionModifier(blurRadius: blurRadius, progress: progress))
    }
}

// MARK: - Launch Animation View

struct LaunchAnimationView: View {
    var isDemoMode: Bool = false
    var onFadeOutStart: () -> Void
    var onFinish: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    @State private var toggle = false
    @State private var current: String = "car.fill"
    @State private var next: String = "car.fill"
    @State private var fadeOut = false
    @State private var carAppear = false

    // 加速系統
    @State private var speedMultiplier: Double = 1.0
    @State private var activeTimer: Timer?
    @State private var elapsed: Double = 0
    @State private var lastTapTime: Date = .distantPast
    @State private var rapidTapCount: Int = 0
    @State private var morphAnimation: Animation = .interpolatingSpring(stiffness: 50, damping: 15)

    // Demo 模式：退出計數
    @State private var demoExitTaps: [Date] = []

    private let iconSize: CGFloat = 100
    private let blurRadius: CGFloat = 20

    // Phase 時間點（基礎速度）
    private let carAppearTime: Double = 0.4
    private let arrowMorphTime: Double = 1.6
    private let gorillaMorphTime: Double = 2.8
    private let fadeOutStartTime: Double = 4.2
    private let finishTime: Double = 5.0

    // 應用相關圖標池
    private let demoIcons: [String] = [
        "car.fill",                // 泊車
        "location.north.fill",     // 導航
        "gorilla",                 // 🦍
        "map.fill",                // 地圖
        "mic.fill",                // 語音翻譯
        "photo.fill",              // 泊車記憶照片
        "clock.fill",              // 計時
        "steeringwheel",           // 駕駛
        "mappin.and.ellipse",      // 位置標記
        "text.book.closed.fill",   // 翻譯
        "arrow.triangle.turn.up.right.circle.fill", // 路線
        "waveform",                // 語音波形
        "brain.head.profile.fill", // AI 分析
        "sparkles"                 // AI 翻譯
    ]

    var body: some View {
        ZStack {
            // 圖標容器
            ZStack {
                if toggle {
                    iconView(name: next)
                } else {
                    iconView(name: current)
                }
            }
            .opacity(carAppear ? 1 : 0)
            .blur(radius: carAppear ? 0 : 20)
            .morphingTransition(blurRadius: blurRadius, progress: toggle ? 1 : 0)
            .opacity(fadeOut ? 0 : 1)
            .animation(morphAnimation, value: toggle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Centre in the full window, including asymmetric camera/status and
        // toolbar safe areas on Duo, rather than in its remaining content area.
        .ignoresSafeArea(.container, edges: .all)
        .contentShape(Rectangle())
        .onTapGesture {
            handleTap()
        }
        .onAppear {
            startSequence()
        }
        .onDisappear {
            activeTimer?.invalidate()
        }
    }

    // MARK: - Icon Rendering

    @ViewBuilder
    private func iconView(name: String) -> some View {
        // 啟動動畫 & 彩蛋均跟隨系統深淺色
        let iconColor = colorScheme == .dark ? Color.white : Color.black
        if name == "gorilla" {
            Text("🦍")
                .font(.system(size: iconSize))
        } else {
            Image(systemName: name)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(iconColor)
        }
    }

    /// 安全產生隨機圖標（確保不重複當前顯示的）
    private func randomIcon(differentFrom avoid: String) -> String {
        var pick: String
        repeat { pick = demoIcons.randomElement()! } while pick == avoid
        return pick
    }

    // MARK: - Tap Acceleration

    private func handleTap() {
        let now = Date()

        if isDemoMode {
            // Demo 模式：5次快速點擊（1.5s 內）退出
            demoExitTaps.append(now)
            demoExitTaps = demoExitTaps.filter { now.timeIntervalSince($0) < 1.5 }

            if demoExitTaps.count >= 5 {
                exitDemo()
                return
            }

            // 也支持加速效果
            let timeSinceLastTap = now.timeIntervalSince(lastTapTime)
            lastTapTime = now
            speedMultiplier = min(speedMultiplier * 2.0, 10.0)
            morphAnimation = .interpolatingSpring(stiffness: 200, damping: 25)

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [self] in
                if Date().timeIntervalSince(lastTapTime) >= 1.8 {
                    speedMultiplier = 1.0
                    morphAnimation = .interpolatingSpring(stiffness: 50, damping: 15)
                }
            }
            return
        }

        let timeSinceLastTap = now.timeIntervalSince(lastTapTime)
        lastTapTime = now

        // 0.3s 內連續點擊 → 快速點擊計數
        if timeSinceLastTap < 0.3 {
            rapidTapCount += 1
        } else {
            rapidTapCount = 1
        }

        // 5次快速點擊 → 直接跳到結尾
        if rapidTapCount >= 5 {
            jumpToEnd()
            return
        }

        // 每次點擊加速2.5x，最高15x
        speedMultiplier = min(speedMultiplier * 2.5, 15.0)

        // 加速時 morph 變快
        morphAnimation = .interpolatingSpring(stiffness: 200, damping: 25)

        // 1.5秒無點擊 → 恢復正常速度
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
            if Date().timeIntervalSince(lastTapTime) >= 1.4 {
                speedMultiplier = 1.0
                morphAnimation = .interpolatingSpring(stiffness: 50, damping: 15)
            }
        }
    }

    private func jumpToEnd() {
        if isDemoMode {
            exitDemo()
            return
        }
        activeTimer?.invalidate()
        current = "gorilla"
        next = "gorilla"
        toggle = false
        carAppear = true
        onFadeOutStart()
        withAnimation(.easeOut(duration: 0.3)) {
            fadeOut = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            onFinish()
        }
    }

    // MARK: - Demo Mode Exit

    private func exitDemo() {
        activeTimer?.invalidate()
        withAnimation(.easeOut(duration: 0.5)) {
            fadeOut = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            onFinish()
        }
    }

    // MARK: - Timer-Based Animation

    @State private var demoNextMorphAt: Double = 0
    @State private var demoInitialized = false

    private func startSequence() {
        if isDemoMode {
            startDemoSequence()
        } else {
            startLaunchSequence()
        }
    }

    private func startLaunchSequence() {
        activeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            elapsed += (1.0 / 60.0) * speedMultiplier
            checkPhases()
        }
    }

    private func startDemoSequence() {
        // 初始化第一個隨機圖標
        let first = demoIcons.randomElement() ?? "car.fill"
        current = first
        next = first

        activeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            elapsed += (1.0 / 60.0) * speedMultiplier
            checkDemoPhases()
        }
    }

    private func checkPhases() {
        // 車圖標出現
        if elapsed >= carAppearTime && !carAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                carAppear = true
            }
        }

        // 車 → 箭頭
        if elapsed >= arrowMorphTime && current == "car.fill" {
            if toggle {
                current = "location.north.fill"
            } else {
                next = "location.north.fill"
            }
            withAnimation(morphAnimation) {
                toggle.toggle()
            }
        }

        // 箭頭 → 大猩猩
        if elapsed >= gorillaMorphTime && next != "gorilla" && current != "gorilla" {
            if toggle {
                current = "gorilla"
            } else {
                next = "gorilla"
            }
            withAnimation(morphAnimation) {
                toggle.toggle()
            }
        }

        // 大猩猩淡出 + 背景模糊
        if elapsed >= fadeOutStartTime && !fadeOut {
            onFadeOutStart()
            withAnimation(.easeIn(duration: 0.6)) {
                fadeOut = true
            }
        }

        // 完成
        if elapsed >= finishTime {
            activeTimer?.invalidate()
            onFinish()
        }
    }

    // MARK: - Demo Mode Phase Logic

    private func checkDemoPhases() {
        // 初始出現
        if elapsed >= 0.4 && !carAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                carAppear = true
            }
            demoNextMorphAt = 1.2
        }

        // 隨機切換圖標
        if carAppear && elapsed >= demoNextMorphAt {
            let displayedIcon = toggle ? next : current
            let newIcon = randomIcon(differentFrom: displayedIcon)

            if toggle {
                current = newIcon
            } else {
                next = newIcon
            }
            withAnimation(morphAnimation) {
                toggle.toggle()
            }
            // 隨機間隔 1.0~2.0 秒（基礎速度）
            let interval = 1.0 + Double.random(in: 0...1.0)
            demoNextMorphAt = elapsed + interval
        }
    }
}
