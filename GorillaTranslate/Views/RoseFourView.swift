import SwiftUI

struct RoseFourView: View {
    var loop: Double = 1.0  // 1.0 = normal speed, higher = faster
    var opacity: Double = 1.0
    var blurRadius: Double = 0.0
    
    private let particleCount = 78
    private let trailSpan: Double = 0.32
    private let durationMs: Double = 5400
    private let rotationDurationMs: Double = 28000
    private let pulseDurationMs: Double = 4500
    private let strokeWidth: Double = 2.0
    private let roseA: Double = 9.2
    private let roseABoost: Double = 0.6
    private let roseBreathBase: Double = 0.72
    private let roseBreathBoost: Double = 0.28
    private let roseScale: Double = 3.25
    
    @State private var animationTime: Double = 0
    @State private var lastUpdateTime: Date = .now
    @State private var timer: Timer?
    
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            
            ZStack {
                let detailScale = getDetailScale(time: animationTime)
                let rotation = getRotation(time: animationTime)
                
                Path { path in
                    let steps = 120
                    for index in 0...steps {
                        let progress = Double(index) / Double(steps)
                        let point = rosePoint(progress: progress, detailScale: detailScale)
                        let screenX = center.x + (point.x - 50) / 50 * size * 0.45
                        let screenY = center.y + (point.y - 50) / 50 * size * 0.45
                        
                        if index == 0 {
                            path.move(to: CGPoint(x: screenX, y: screenY))
                        } else {
                            path.addLine(to: CGPoint(x: screenX, y: screenY))
                        }
                    }
                }
                .stroke(Color.white.opacity(0.15), lineWidth: strokeWidth)
                .rotationEffect(.degrees(rotation))
                
                ForEach(0..<particleCount, id: \.self) { index in
                    let progress = normalizeProgress(animationTime / durationMs)
                    let particle = getParticle(index: index, progress: progress, detailScale: detailScale)
                    let screenX = center.x + (particle.x - 50) / 50 * size * 0.45
                    let screenY = center.y + (particle.y - 50) / 50 * size * 0.45
                    
                    Circle()
                        .fill(Color.white)
                        .frame(width: particle.radius * 2, height: particle.radius * 2)
                        .position(x: screenX, y: screenY)
                        .opacity(particle.opacity)
                        .rotationEffect(.degrees(rotation))
                }
            }
        }
        .opacity(opacity)
        .blur(radius: blurRadius)
        .onAppear {
            lastUpdateTime = .now
            timer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [self] _ in
                let now = Date()
                let delta = now.timeIntervalSince(self.lastUpdateTime) * self.loop
                self.lastUpdateTime = now
                self.animationTime += delta * 1000
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
    
    private func normalizeProgress(_ progress: Double) -> Double {
        return ((progress.truncatingRemainder(dividingBy: 1.0)) + 1.0).truncatingRemainder(dividingBy: 1.0)
    }
    
    private func getDetailScale(time: Double) -> Double {
        let pulseProgress = (time.truncatingRemainder(dividingBy: pulseDurationMs)) / pulseDurationMs
        let pulseAngle = pulseProgress * .pi * 2
        return 0.52 + ((sin(pulseAngle + 0.55) + 1) / 2) * 0.48
    }
    
    private func getRotation(time: Double) -> Double {
        return -((time.truncatingRemainder(dividingBy: rotationDurationMs)) / rotationDurationMs) * 360
    }
    
    private func rosePoint(progress: Double, detailScale: Double) -> CGPoint {
        let t = progress * .pi * 2
        let a = roseA + detailScale * roseABoost
        let r = a * (roseBreathBase + detailScale * roseBreathBoost) * cos(4 * t)
        let x = 50 + cos(t) * r * roseScale
        let y = 50 + sin(t) * r * roseScale
        return CGPoint(x: x, y: y)
    }
    
    private func getParticle(index: Int, progress: Double, detailScale: Double) -> (x: Double, y: Double, radius: Double, opacity: Double) {
        let tailOffset = Double(index) / Double(particleCount - 1)
        let particleProgress = normalizeProgress(progress - tailOffset * trailSpan)
        let point = rosePoint(progress: particleProgress, detailScale: detailScale)
        let fade = pow(1 - tailOffset, 0.56)
        return (
            x: point.x,
            y: point.y,
            radius: 0.9 + fade * 2.7,
            opacity: 0.04 + fade * 0.96
        )
    }
}

#Preview {
    RoseFourView()
        .frame(width: 100, height: 100)
        .background(Color.black)
}
