import SwiftUI

/// 全屏光效視圖（微弧形頂部）
struct CapsuleLightEffect: View {
    let progress: CGFloat
    let capsuleBottomOffset: CGFloat
    var isFadingOut: Bool = false
    var fadeOutProgress: CGFloat = 0

    /// 超級柔和嘅 easing（S 曲線）
    private var easedProgress: CGFloat {
        let p = min(max(progress, 0), 1)
        return p * p * p * (p * (p * 6 - 15) + 10)
    }

    /// 光帶亮度
    private var lightOpacity: CGFloat {
        if isFadingOut {
            return max(0, 1 - fadeOutProgress * fadeOutProgress)
        }
        return min(1, easedProgress * 3)
    }

    /// 起點 Y（膠囊底部）
    private var startY: CGFloat {
        UIScreen.main.bounds.height - capsuleBottomOffset
    }

    /// 終點 Y（膠囊頂部 + 100pt）
    private var endY: CGFloat {
        startY - 182 - 100
    }

    /// Y 偏移量（從0開始，往上移動為負值）
    private var yOffset: CGFloat {
        let travel = startY - endY
        return -travel * easedProgress
    }

    var body: some View {
        let screenW = UIScreen.main.bounds.width
        let screenH = UIScreen.main.bounds.height

        ZStack {
            // === 底層：超寬超大擴散光暈 ===
            ArcLightShape(arcHeight: screenH * 0.1)
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.36, green: 0.68, blue: 0.72).opacity(0.05 * Double(easedProgress)),
                            Color.clear,
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: screenW * 0.7
                    )
                )
                .frame(width: screenW * 2.0, height: screenH * 1.0)
                .blur(radius: 100)
                .position(x: screenW / 2, y: startY + screenH * 0.4)
                .offset(y: yOffset)

            // === 中層：柔和大範圍光帶（微弧形）===
            ArcLightShape(arcHeight: screenH * 0.14)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color(red: 0.36, green: 0.68, blue: 0.72).opacity(0.55), location: 0),
                            .init(color: Color(red: 0.36, green: 0.68, blue: 0.72).opacity(0.3), location: 0.12),
                            .init(color: Color(red: 0.36, green: 0.68, blue: 0.72).opacity(0.1), location: 0.3),
                            .init(color: Color(red: 0.36, green: 0.68, blue: 0.72).opacity(0.03), location: 0.5),
                            .init(color: .clear, location: 0.7),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: screenW * 1.6, height: screenH * 0.75)
                .blur(radius: 45)
                .position(x: screenW / 2, y: startY + screenH * 0.3)
                .offset(y: yOffset)

            // === 頂層：光帶前緣（微弧形）===
            ArcLightShape(arcHeight: screenH * 0.08)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color(red: 0.5, green: 0.9, blue: 0.95).opacity(0.5), location: 0),
                            .init(color: Color(red: 0.4, green: 0.8, blue: 0.85).opacity(0.25), location: 0.15),
                            .init(color: Color(red: 0.36, green: 0.68, blue: 0.72).opacity(0.08), location: 0.4),
                            .init(color: .clear, location: 0.65),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: screenW * 1.4, height: screenH * 0.35)
                .blur(radius: 30)
                .position(x: screenW / 2, y: startY + screenH * 0.08)
                .offset(y: yOffset)

            // === 最亮核心：微弧形橢圓 ===
            ArcLightShape(arcHeight: screenH * 0.05)
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.5, green: 0.9, blue: 0.95).opacity(0.35),
                            Color(red: 0.36, green: 0.68, blue: 0.72).opacity(0.15),
                            Color.clear,
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: screenW * 0.4
                    )
                )
                .frame(width: screenW * 1.1, height: 200)
                .blur(radius: 24)
                .position(x: screenW / 2, y: startY)
                .offset(y: yOffset)
        }
        .opacity(Double(lightOpacity))
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

// MARK: - 微弧形形狀（頂部向上彎）
struct ArcLightShape: Shape {
    var arcHeight: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        path.move(to: CGPoint(x: 0, y: h))
        path.addLine(to: CGPoint(x: 0, y: arcHeight))
        path.addQuadCurve(
            to: CGPoint(x: w, y: arcHeight),
            control: CGPoint(x: w / 2, y: 0)
        )
        path.addLine(to: CGPoint(x: w, y: h))
        path.closeSubpath()

        return path
    }
}
