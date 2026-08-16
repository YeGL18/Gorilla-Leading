import Foundation
import AVFoundation

@preconcurrency import AVFoundation

@MainActor
final class SFXPlayer: ObservableObject {
    private var stationaryPlayer: AVAudioPlayer?
    private var drivingPlayer: AVAudioPlayer?
    private var accelerationPlayer: AVAudioPlayer?
    private var accelerationStopWork: DispatchWorkItem?
    private var accelerationFadeStartWork: DispatchWorkItem?
    private var accelerationFadeTimer: Timer?
    private var accelerationFadeInTimer: Timer?
    
    private let baseVolume: Float = 1.0
    private var hasPrepared = false
    
    init() {}
    
    func prepare() {
        guard !hasPrepared else { return }
        hasPrepared = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            configureAudioSession()
            stationaryPlayer = loadPlayer(name: "sfx_enter_stationary", volume: baseVolume)
            drivingPlayer = loadPlayer(name: "sfx_enter_driving", volume: baseVolume)
            accelerationPlayer = loadPlayer(name: "sfx_acceleration_overlay", volume: min(1.0, baseVolume * 0.95))
        }
    }
    
    func playEnterStationary() {
        playOnce(&stationaryPlayer, fallbackName: "sfx_enter_stationary", volumeMultiplier: 1.5)
    }

    func playEnterDriving() {
        playOnce(&drivingPlayer, fallbackName: "sfx_enter_driving", volumeMultiplier: 1.5)
    }
    
    private static var launchPlayer: AVAudioPlayer?

    func playLaunchSound() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true, options: [])
        if let url = resolveURL(name: "gorilla_launch") {
            let p = try? AVAudioPlayer(contentsOf: url)
            p?.delegate = nil
            p?.volume = baseVolume
            p?.prepareToPlay()
            p?.play()
            SFXPlayer.launchPlayer = p // 防止被回收
            // 播放完畢後恢復 ambient session
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                SFXPlayer.launchPlayer = nil
                self.configureAudioSession()
            }
        }
    }

    func playAccelerationBurst(burstDuration: TimeInterval = 2.4, fadeInDuration: TimeInterval = 0.5, fadeOutDuration: TimeInterval = 0.9) {
        guard burstDuration > 0 else { return }
        configureAudioSession()
        
        if accelerationPlayer == nil {
            accelerationPlayer = loadPlayer(name: "sfx_acceleration_overlay", volume: min(1.0, baseVolume * 0.95))
        }
        
        guard let player = accelerationPlayer else { return }
        
        accelerationStopWork?.cancel()
        accelerationStopWork = nil
        accelerationFadeStartWork?.cancel()
        accelerationFadeStartWork = nil
        accelerationFadeTimer?.invalidate()
        accelerationFadeTimer = nil
        accelerationFadeInTimer?.invalidate()
        accelerationFadeInTimer = nil
        
        player.stop()
        player.currentTime = 0
        let targetVolume = min(1.0, baseVolume * 0.95)
        player.volume = fadeInDuration > 0 ? 0 : targetVolume
        player.prepareToPlay()
        player.play()
        
        if fadeInDuration > 0 {
            let start = Date()
            let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                let t = Date().timeIntervalSince(start)
                let u = min(max(t / fadeInDuration, 0), 1)
                let ease = u * u
                player.volume = targetVolume * Float(ease)
                if u >= 1 {
                    timer.invalidate()
                    self.accelerationFadeInTimer = nil
                }
            }
            accelerationFadeInTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        
        let fadeStart = max(0, burstDuration - fadeOutDuration)
        if fadeOutDuration > 0, fadeStart > 0 {
            let work = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                let start = Date()
                var startVolume: Float?
                let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] timer in
                    guard let self = self else {
                        timer.invalidate()
                        return
                    }
                    let t = Date().timeIntervalSince(start)
                    let u = min(max(t / fadeOutDuration, 0), 1)
                    if startVolume == nil {
                        startVolume = player.volume
                    }
                    let base = startVolume ?? player.volume
                    player.volume = base * Float(1 - u)
                    if u >= 1 {
                        timer.invalidate()
                        self.accelerationFadeTimer = nil
                    }
                }
                self.accelerationFadeTimer = timer
                RunLoop.main.add(timer, forMode: .common)
            }
            accelerationFadeStartWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + fadeStart, execute: work)
        }
        
        let stopWork = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            player.stop()
            player.currentTime = 0
            player.volume = min(1.0, self.baseVolume * 0.95)
            self.accelerationStopWork = nil
        }
        accelerationStopWork = stopWork
        DispatchQueue.main.asyncAfter(deadline: .now() + burstDuration, execute: stopWork)
    }
    
    private func playOnce(_ player: inout AVAudioPlayer?, fallbackName: String, volumeMultiplier: Float = 1.0) {
        configureAudioSession()
        let vol = baseVolume * volumeMultiplier
        if player == nil {
            player = loadPlayer(name: fallbackName, volume: vol)
        }
        guard let p = player else { return }
        p.stop()
        p.currentTime = 0
        p.volume = vol
        p.prepareToPlay()
        p.play()
    }
    
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true, options: [])
    }
    
    private func loadPlayer(name: String, volume: Float) -> AVAudioPlayer? {
        guard let url = resolveURL(name: name) else { return nil }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = 0
            p.volume = volume
            p.prepareToPlay()
            return p
        } catch {
            return nil
        }
    }
    
    private func resolveURL(name: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: "mp3", subdirectory: "Resources/Audio/SFX") {
            return url
        }
        if let url = Bundle.main.url(forResource: name, withExtension: "mp3", subdirectory: "Audio/SFX") {
            return url
        }
        return Bundle.main.url(forResource: name, withExtension: "mp3")
    }
}
