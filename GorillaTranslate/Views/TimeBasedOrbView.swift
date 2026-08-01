import SwiftUI

struct TimeBasedOrbView: View {
    @ObservedObject var phaseManager: TimePhaseManager
    @ObservedObject var clock: AnimationClock
    var orbEnabled: Bool = true
    
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            let elapsed = clock.elapsed
            let colors = phaseManager.blendedColors
            let sun = phaseManager.sunPosition
            
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
}

#Preview {
    let phaseManager = TimePhaseManager()
    let clock = AnimationClock()
    
    return TimeBasedOrbView(phaseManager: phaseManager, clock: clock)
        .onAppear {
            clock.start()
            phaseManager.start()
        }
}
