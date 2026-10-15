import Foundation
import QuartzCore
import SwiftUI

enum AnimationDiagnostics {
    // Both producers run on the main display-link run loop.
    nonisolated(unsafe) static var callback: ((String, Double, Double) -> Void)?
}

/// 驅動 orb 背景動畫嘅時鐘。用 CADisplayLink 同螢幕刷新同步，
/// 支援 60fps / 120fps（ProMotion）刷新率。
class AnimationClock: ObservableObject {
    @Published var elapsed: TimeInterval = 0
    var speedMultiplier: Double = 1.0
    private var lastDate: Date = .now
    private var displayLink: CADisplayLink?
    private var frameRate: Double = 60
    private var consumers: Set<UUID> = []

    func acquire(_ id: UUID) {
        consumers.insert(id)
        if displayLink == nil { start() }
    }

    func release(_ id: UUID) {
        consumers.remove(id)
        if consumers.isEmpty { stop() }
    }

    func start() {
        guard displayLink == nil else { return }
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
        AnimationDiagnostics.callback?("orbs", link.timestamp, max(link.duration, link.targetTimestamp - link.timestamp))
        let now = Date.now
        let delta = now.timeIntervalSince(lastDate) * speedMultiplier
        lastDate = now
        elapsed += delta
    }
}

// Ownership stays in the parent; only this small rendering surface observes ticks.
struct ClockDrivenContent<Content: View>: View {
    @ObservedObject var clock: AnimationClock
    var running = true
    @ViewBuilder var content: (TimeInterval) -> Content
    @Environment(\.scenePhase) private var scenePhase
    @State private var consumerID = UUID()

    var body: some View {
        content(clock.elapsed)
            .onAppear { sync() }
            .onChange(of: running) { _, _ in sync() }
            .onChange(of: scenePhase) { _, _ in sync() }
            .onDisappear { clock.release(consumerID) }
    }

    private func sync() {
        if running && scenePhase == .active { clock.acquire(consumerID) }
        else { clock.release(consumerID) }
    }
}

// Sweep at the original cadence; while the band is invisible, wake only for
// the next sweep instead of redrawing the same transparent layer every frame.
struct SheenTimelineSchedule: TimelineSchedule {
    private let sweepDuration = 5.0
    private let pauses = [2.2, 4.6, 1.4, 3.4, 2.8, 5.2, 1.8]

    func state(at date: Date) -> (phase: Double, sweeping: Bool, remaining: TimeInterval) {
        let cycle = sweepDuration * Double(pauses.count) + pauses.reduce(0, +)
        var elapsed = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
        if elapsed < 0 { elapsed += cycle }
        for pause in pauses {
            if elapsed < sweepDuration {
                return (elapsed / sweepDuration, true, sweepDuration - elapsed)
            }
            elapsed -= sweepDuration
            if elapsed < pause { return (1, false, pause - elapsed) }
            elapsed -= pause
        }
        return (0, true, sweepDuration)
    }

    func entries(from startDate: Date, mode: Mode) -> AnySequence<Date> {
        let interval = mode == .lowFrequency ? 1.0 / 30.0 : 1.0 / 120.0
        return AnySequence {
            var next = startDate
            return AnyIterator {
                let date = next
                let state = state(at: date)
                let step = state.sweeping ? min(interval, state.remaining) : state.remaining
                next = date.addingTimeInterval(max(step, 0.000_001))
                return date
            }
        }
    }
}
