import Foundation

class AnimationClock: ObservableObject {
    @Published var elapsed: TimeInterval = 0
    var speedMultiplier: Double = 1.0
    private var lastDate: Date = .now
    private var timer: Timer?

    func start() {
        lastDate = .now
        let newTimer = Timer(timeInterval: 0.016, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let now = Date.now
            let delta = now.timeIntervalSince(self.lastDate) * self.speedMultiplier
            self.lastDate = now
            self.elapsed += delta
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
