import SwiftUI

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
    var onFadeOutStart: () -> Void
    var onFinish: () -> Void

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

    private let iconSize: CGFloat = 100
    private let blurRadius: CGFloat = 20

    // Phase 時間點（基礎速度）
    private let carAppearTime: Double = 0.4
    private let arrowMorphTime: Double = 1.6
    private let gorillaMorphTime: Double = 2.8
    private let fadeOutStartTime: Double = 4.2
    private let finishTime: Double = 5.0

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
        if name == "gorilla" {
            Text("🦍")
                .font(.system(size: iconSize))
        } else {
            Image(systemName: name)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Tap Acceleration

    private func handleTap() {
        let now = Date()
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

    // MARK: - Timer-Based Animation

    private func startSequence() {
        // 啟動計時器（每幀 ~16ms）
        activeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            elapsed += (1.0 / 60.0) * speedMultiplier
            checkPhases()
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
}
