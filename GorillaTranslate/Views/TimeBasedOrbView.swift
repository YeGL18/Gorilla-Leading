import SwiftUI

struct TimeBasedOrbView: View {
    @ObservedObject var phaseManager: TimePhaseManager
    let clock: AnimationClock
    var orbEnabled: Bool = true
    var orbSizeMultiplier: CGFloat = 1.0
    @Environment(\.scenePhase) private var scenePhase

    private var starNightIntensity: Double {
        // 日出前要消失得夠快；入夜前要遲先出、慢啲淡入
        let t = phaseManager.phaseTransitionProgress
        switch phaseManager.currentPhase {
        case .deepNight:
            // 呢段最長，滿 1.0；去到段尾（接 preDawn）先瀉去 0.4，為下一階段清零做準備
            if t < 0.85 { return 1.0 }
            let p = (t - 0.85) / 0.15
            return 1.0 - 0.6 * p
        case .preDawn:
            // 日出前極短：一開段即刻 0.4 → 0，唔等
            return 0.4 * (1.0 - t)
        case .sunrise:
            // 太陽一出：完全冇星
            return 0.0
        case .morning, .afternoon:
            return 0.0
        case .postSunset:
            // 入黃昏：頭 80% 時間完全冇星；尾 20% 先極淡淡入到 0.2
            if t < 0.8 { return 0.0 }
            let p = (t - 0.8) / 0.2
            return 0.2 * p
        case .sunset:
            // 日落段：主要淡入階段，0.2 → 1.0，比之前慢
            return 0.2 + 0.8 * t
        }
    }

    // 計算漸變中間色嘅位置（藍色佔比）
    // 早上 7-9 點：0.5（藍色佔 50%）
    // 9-11 點：0.5 → 0.9（藍色逐漸擴大到 90%）
    // 11-14 點：0.9（藍色佔 90%）
    // 14-16:30：0.9 → 0.5（回歸 50%）
    private var gradientMidPoint: CGFloat {
        let hour = phaseManager.currentHour

        guard hour >= 7 && hour < 16.5 else { return 0.5 }

        switch hour {
        case 7..<9:
            return 0.5
        case 9..<11:
            return 0.5 + (hour - 9) / 2 * 0.4
        case 11..<14:
            return 0.9
        case 14..<16.5:
            return 0.9 - (hour - 14) / 2.5 * 0.4
        default:
            return 0.5
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            let colors = phaseManager.blendedColors
            let sun = phaseManager.sunPosition
            let starNight = starNightIntensity
            let midStop = gradientMidPoint

            ClockDrivenContent(clock: clock) { elapsed in
            ZStack {
                // 渐变背景（動態調整藍色佔比）
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: colors.background1, location: 0),
                        .init(color: colors.background2, location: midStop),
                        .init(color: colors.background3, location: 1)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                // 星空：星點 + 呼吸（夜晚先顯）
                if starNight > 0.01 {
                    starField(width: w, height: h, elapsed: elapsed, night: starNight)
                        .allowsHitTesting(false)
                }

                // 背景光球 1（顶部，高模糊）
                Circle()
                    .fill(colors.background1)
                    .blur(radius: 120)
                    .frame(width: w * 1.2, height: h * 0.6)
                    .offset(
                        x: CGFloat(sin(elapsed * 0.3)) * w * 0.2,
                        y: -h * 0.15 + CGFloat(cos(elapsed * 0.25)) * h * 0.1
                    )
                    .opacity(orbEnabled ? 0.6 : 0)

                // 背景光球 2（底部，高模糊）
                Circle()
                    .fill(colors.background3)
                    .blur(radius: 120)
                    .frame(width: w * 1.2, height: h * 0.6)
                    .offset(
                        x: CGFloat(sin(elapsed * 0.35 + 2)) * w * 0.2,
                        y: h * 0.15 + CGFloat(cos(elapsed * 0.28 + 1)) * h * 0.1
                    )
                    .opacity(orbEnabled ? 0.6 : 0)

                // 太阳光球
                if orbEnabled && sun.visible && colors.sunOpacity > 0 {
                    // 太阳光晕（大，高模糊）
                    Circle()
                        .fill(colors.sunColor)
                        .blur(radius: sun.blur * 1.5)
                        .frame(
                            width: 300 * sun.scale * orbSizeMultiplier,
                            height: 300 * sun.scale * orbSizeMultiplier
                        )
                        .offset(
                            x: (sun.x - 0.5) * w * 1.2,
                            y: (sun.y - 0.5) * h * 1.2
                        )
                        .opacity(0.4 * colors.sunOpacity)

                    // 太阳本体（中等模糊）
                    Circle()
                        .fill(colors.sunColor)
                        .blur(radius: sun.blur)
                        .frame(
                            width: 180 * sun.scale * orbSizeMultiplier,
                            height: 180 * sun.scale * orbSizeMultiplier
                        )
                        .offset(
                            x: (sun.x - 0.5) * w * 1.2 + CGFloat(sin(elapsed * 0.8)) * 8,
                            y: (sun.y - 0.5) * h * 1.2 + CGFloat(cos(elapsed * 0.6)) * 6
                        )
                        .opacity(0.7 * colors.sunOpacity)

                    // 太阳核心（小，低模糊，高亮度）
                    Circle()
                        .fill(colors.sunColor.opacity(0.9))
                        .blur(radius: sun.blur * 0.4)
                        .frame(
                            width: 60 * sun.scale * orbSizeMultiplier,
                            height: 60 * sun.scale * orbSizeMultiplier
                        )
                        .offset(
                            x: (sun.x - 0.5) * w * 1.2 + CGFloat(sin(elapsed * 1.0)) * 12,
                            y: (sun.y - 0.5) * h * 1.2 + CGFloat(cos(elapsed * 0.8)) * 10
                        )
                        .opacity(0.9 * colors.sunOpacity)
                }
            }
            }
        }
        .ignoresSafeArea()
        .onAppear { phaseManager.start() }
        .onDisappear { phaseManager.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { phaseManager.start() }
            else { phaseManager.stop() }
        }
    }

    // MARK: - 星空 + 呼吸
    @ViewBuilder
    private func starField(width: CGFloat, height: CGFloat, elapsed: Double, night: Double) -> some View {
        OrbStarField(elapsed: elapsed, night: night)
            .frame(width: width, height: height)
    }

}

struct OrbStarField: View {
    struct Star {
        let seed: Double
        let x: Double
        let y: Double
        let radius: Double
        let frequency: Double
        let fade: Double

        func opacity(at elapsed: Double, night: Double) -> Double {
            let raw = elapsed * frequency + seed
            let phase = raw - floor(raw)
            let breath = 0.45 + 0.55 * (0.5 - 0.5 * cos(phase * 2 * .pi))
            let twinkle = 0.82 + 0.18 * sin(elapsed * 5 + seed * 30)
            return min(1, breath * twinkle) * night * fade
        }
    }

    // Positions, sizes and frequencies never change with the animation clock.
    static let stars: [Star] = (0..<90).map { index in
        let seed = Double(index) * 0.6180339887498949
        func fraction(_ value: Double) -> Double { value - floor(value) }
        let x = fraction(sin(seed * 127.1) * 43758.5453123)
        let y = fraction(sin(seed * 311.7) * 43758.5453123) * 0.6667
        let size = fraction(sin(seed * 74.7) * 12345.6789)
        let frequency = fraction(sin(seed * 213.3) * 98765.4321)
        let fade = y <= 1.0 / 3 ? 1 : max(0, 1 - (y - 1.0 / 3) / (1.0 / 3))
        return Star(seed: seed, x: x, y: y, radius: (0.6 + size * 1.8) * sqrt(max(0.0001, fade)),
                    frequency: 0.45 + frequency * 1.15, fade: fade)
    }

    var elapsed: Double
    var night: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack {
            ForEach(0..<Self.stars.count, id: \.self) { index in
                let star = Self.stars[index]
                let opacity = star.opacity(at: elapsed, night: night)
                if opacity > 0.001 {
                    Circle().fill(.white).frame(width: star.radius * 2, height: star.radius * 2)
                        .blur(radius: star.radius > 1.6 ? 0.6 : 0.2)
                        .position(x: star.x * geometry.size.width, y: star.y * geometry.size.height)
                        .opacity(opacity)
                }
            }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
