import SwiftUI

struct TimeBasedOrbView: View {
    @ObservedObject var phaseManager: TimePhaseManager
    @ObservedObject var clock: AnimationClock
    var orbEnabled: Bool = true

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

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            let elapsed = clock.elapsed
            let colors = phaseManager.blendedColors
            let sun = phaseManager.sunPosition
            let starNight = starNightIntensity

            ZStack {
                // 渐变背景
                LinearGradient(
                    gradient: Gradient(colors: [
                        colors.background1,
                        colors.background2,
                        colors.background3
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
                if orbEnabled && sun.visible && colors.sunIndex >= 0 {
                    // 太阳光晕（大，高模糊）
                    Circle()
                        .fill(colors.sunColor)
                        .blur(radius: sun.blur * 1.5)
                        .frame(
                            width: 300 * sun.scale,
                            height: 300 * sun.scale
                        )
                        .offset(
                            x: (sun.x - 0.5) * w * 1.2,
                            y: (sun.y - 0.5) * h * 1.2
                        )
                        .opacity(0.4)

                    // 太阳本体（中等模糊）
                    Circle()
                        .fill(colors.sunColor)
                        .blur(radius: sun.blur)
                        .frame(
                            width: 180 * sun.scale,
                            height: 180 * sun.scale
                        )
                        .offset(
                            x: (sun.x - 0.5) * w * 1.2 + CGFloat(sin(elapsed * 0.8)) * 8,
                            y: (sun.y - 0.5) * h * 1.2 + CGFloat(cos(elapsed * 0.6)) * 6
                        )
                        .opacity(0.7)

                    // 太阳核心（小，低模糊，高亮度）
                    Circle()
                        .fill(colors.sunColor.opacity(0.9))
                        .blur(radius: sun.blur * 0.4)
                        .frame(
                            width: 60 * sun.scale,
                            height: 60 * sun.scale
                        )
                        .offset(
                            x: (sun.x - 0.5) * w * 1.2 + CGFloat(sin(elapsed * 1.0)) * 12,
                            y: (sun.y - 0.5) * h * 1.2 + CGFloat(cos(elapsed * 0.8)) * 10
                        )
                        .opacity(0.9)
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - 星空 + 呼吸
    @ViewBuilder
    private func starField(width: CGFloat, height: CGFloat, elapsed: Double, night: Double) -> some View {
        let starCount = 90
        ZStack {
            ForEach(Array(0..<starCount), id: \.self) { i in
                let pseudoSeed = Double(i) * 0.6180339887498949
                let (ux, uy) = fract(sin(pseudoSeed * 127.1) * 43758.5453123,
                                     sin(pseudoSeed * 311.7) * 43758.5453123)
                let (usize, ufreq) = fract(sin(pseudoSeed * 74.7) * 12345.6789,
                                           sin(pseudoSeed * 213.3) * 98765.4321)
                let yFrac = uy * 0.6667
                let verticalFade: Double = {
                    if yFrac <= 1.0 / 3.0 {
                        return 1.0
                    } else if yFrac < 2.0 / 3.0 {
                        let p = (yFrac - 1.0 / 3.0) / (1.0 / 3.0)
                        return 1.0 - p
                    } else {
                        return 0.0
                    }
                }()

                let sx = ux * width
                let sy = yFrac * height
                let baseR = (0.6 + usize * 1.8) * CGFloat(sqrt(max(0.0001, verticalFade)))
                let breathFreq = 0.45 + ufreq * 1.15
                let phaseRaw = (elapsed * breathFreq + pseudoSeed)
                let phase = fract(phaseRaw, 0).0
                let breath = 0.45 + 0.55 * (0.5 - 0.5 * cos(phase * 2 * Double.pi))
                let twinkle = 0.82 + 0.18 * sin(elapsed * 5.0 + pseudoSeed * 30.0)
                let opacity = min(1.0, breath * twinkle) * night * verticalFade

                if opacity > 0.001 {
                    Circle()
                        .fill(Color.white)
                        .frame(width: baseR * 2, height: baseR * 2)
                        .blur(radius: baseR > 1.6 ? 0.6 : 0.2)
                        .position(x: sx, y: sy)
                        .opacity(opacity)
                } else {
                    EmptyView()
                }
            }
        }
    }

    // MARK: - 偽隨機工具
    private func fract(_ a: Double, _ b: Double) -> (Double, Double) {
        let x = a - floor(a)
        let y = b - floor(b)
        return (x < 0 ? x + 1 : x, y < 0 ? y + 1 : y)
    }
}
