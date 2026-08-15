import Foundation
import QuartzCore

/// 驅動 orb 背景動畫嘅時鐘。用 CADisplayLink 同螢幕刷新同步，
/// 可以喺 60fps / 120fps（ProMotion）之間切換 —— 專注模式用。
class AnimationClock: ObservableObject {
    @Published var elapsed: TimeInterval = 0
    var speedMultiplier: Double = 1.0
    private var lastDate: Date = .now
    private var displayLink: CADisplayLink?
    private var frameRate: Double = 60

    func start() {
        restartDisplayLink()
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    /// 切換幀率（60／120），運行中即刻生效。
    /// 注意：iPhone 上要 Info.plist 設 CADisableMinimumFrameDurationOnPhone
    /// 先可以超過 60Hz。
    func setFrameRate(_ fps: Double) {
        guard fps != frameRate else { return }
        frameRate = fps
        if displayLink != nil {
            restartDisplayLink()
        }
    }

    private func restartDisplayLink() {
        displayLink?.invalidate()
        lastDate = .now
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(
            minimum: frameRate >= 120 ? 80 : 30,
            maximum: Float(frameRate),
            preferred: Float(frameRate)
        )
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = Date.now
        let delta = now.timeIntervalSince(lastDate) * speedMultiplier
        lastDate = now
        elapsed += delta
    }
}
