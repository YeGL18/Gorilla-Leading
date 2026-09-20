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

    private var vlmLoadingPlayer: AVAudioPlayer?
    private var vlmDonePlayer: AVAudioPlayer?
    private var vlmLoadingDelegate: VLMLoadingDelegate?
    /// true = 播完當前循環後停止（唔再循環）
    private var vlmLoadingStopAfterCurrent = false

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
            accelerationPlayer = loadPlayer(name: "sfx_acceleration_overlay", volume: min(1.0, baseVolume * 1.5))
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
        // 避免 main thread 阻塞：setCategory + setActive 都放 background
        DispatchQueue.global(qos: .userInitiated).async {
            try? session.setCategory(.playback, mode: .default, options: [])
            try? session.setActive(true, options: [])
            DispatchQueue.main.async {
                if let url = self.resolveURL(name: "gorilla_launch") {
                    let p = try? AVAudioPlayer(contentsOf: url)
                    p?.delegate = nil
                    p?.volume = self.baseVolume
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
        }
    }

    func playAccelerationBurst(burstDuration: TimeInterval = 2.4, fadeInDuration: TimeInterval = 0.5, fadeOutDuration: TimeInterval = 0.9) {
        guard burstDuration > 0 else { return }
        configureAudioSession()
        
        if accelerationPlayer == nil {
            accelerationPlayer = loadPlayer(name: "sfx_acceleration_overlay", volume: baseVolume * 1.5)
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
        let targetVolume = min(1.0, baseVolume * 1.5)
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
            player.volume = min(1.0, self.baseVolume * 1.5)
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

    private func playOnceWithFadeIn(_ player: inout AVAudioPlayer?, fallbackName: String, volumeMultiplier: Float = 1.0, fadeDuration: TimeInterval = 0.3) {
        configureAudioSession()
        let vol = baseVolume * volumeMultiplier
        if player == nil {
            player = loadPlayer(name: fallbackName, volume: 0)
        }
        guard let p = player else { return }
        p.stop()
        p.currentTime = 0
        p.volume = 0
        p.prepareToPlay()
        p.play()
        p.setVolume(vol, fadeDuration: fadeDuration)
    }
    
    private func configureAudioSession() {
        DispatchQueue.global(qos: .userInitiated).async {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try? session.setActive(true, options: [])
        }
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

    // MARK: - 樓層探測音效

    private var floorCurveAppearPlayer: AVAudioPlayer?
    private var floorCurveLockedPlayer: AVAudioPlayer?

    func playFloorCurveAppear() {
        playOnceWithFadeIn(&floorCurveAppearPlayer, fallbackName: "sfx_floor_curve_appear", volumeMultiplier: 1.5, fadeDuration: 0.3)
    }

    func playFloorCurveLocked() {
        playOnceWithFadeIn(&floorCurveLockedPlayer, fallbackName: "sfx_floor_curve_locked", volumeMultiplier: 1.5, fadeDuration: 0.4)
    }

    // MARK: - VLM 識別音效

    /// 開始循環播放 loading 音效
    func playVLMLoading() {
        configureAudioSession()
        vlmLoadingStopAfterCurrent = false
        if vlmLoadingPlayer == nil {
            vlmLoadingPlayer = loadPlayer(name: "gorilla_ai_loading", volume: baseVolume)
        }
        guard let p = vlmLoadingPlayer else { return }
        p.numberOfLoops = -1  // 無限循環
        // 設定 delegate 回調：播完時重置狀態
        if vlmLoadingDelegate == nil {
            vlmLoadingDelegate = VLMLoadingDelegate()
        }
        vlmLoadingDelegate?.onFinished = { [weak self] in
            guard let self else { return }
            // 如果係要停止（播完最後一次），唔好重設循環
            if self.vlmLoadingStopAfterCurrent {
                self.vlmLoadingStopAfterCurrent = false
            } else {
                self.vlmLoadingPlayer?.numberOfLoops = -1  // 重置為循環（下次用）
            }
        }
        p.delegate = vlmLoadingDelegate
        p.currentTime = 0
        p.volume = baseVolume
        p.prepareToPlay()
        p.play()
    }

    /// 停止 loading 音效：淡出 0.3 秒後停止
    func stopVLMLoadingGracefully() {
        vlmLoadingStopAfterCurrent = true
        guard let p = vlmLoadingPlayer, p.isPlaying else { return }
        let startVolume = p.volume
        let fadeDuration = 0.3
        let fadeStartTime = Date()
        let fadeTimer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { timer in
            let elapsed = Date().timeIntervalSince(fadeStartTime)
            let progress = min(elapsed / fadeDuration, 1.0)
            p.volume = startVolume * Float(1.0 - progress)
            if progress >= 1.0 {
                timer.invalidate()
                p.stop()
                p.currentTime = 0
                p.volume = startVolume
                p.numberOfLoops = -1  // 重置為循環（下次用）
            }
        }
        RunLoop.main.add(fadeTimer, forMode: .common)
    }

    /// 立即停止 loading 音效
    func stopVLMLoadingImmediately() {
        vlmLoadingStopAfterCurrent = false
        vlmLoadingPlayer?.stop()
        vlmLoadingPlayer?.currentTime = 0
    }

    /// 播放一次 done 音效（loading 淡出 0.2s，done 延遲 0.2s）
    func playVLMDone() {
        // loading 淡出 0.2 秒
        let loadingPlayer = vlmLoadingPlayer
        let startVolume = loadingPlayer?.volume ?? 0
        let fadeDuration = 0.2
        let fadeStartTime = Date()
        vlmLoadingStopAfterCurrent = false
        let fadeTimer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { timer in
            let elapsed = Date().timeIntervalSince(fadeStartTime)
            let progress = min(elapsed / fadeDuration, 1.0)
            loadingPlayer?.volume = startVolume * Float(1.0 - progress)
            if progress >= 1.0 {
                timer.invalidate()
                loadingPlayer?.stop()
                loadingPlayer?.currentTime = 0
                loadingPlayer?.volume = startVolume
            }
        }
        RunLoop.main.add(fadeTimer, forMode: .common)

        // done 音效延遲 0.2 秒播放
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            self.configureAudioSession()
            if self.vlmDonePlayer == nil {
                self.vlmDonePlayer = self.loadPlayer(name: "gorilla_ai_done", volume: self.baseVolume)
            }
            guard let p = self.vlmDonePlayer else { return }
            p.numberOfLoops = 0
            p.currentTime = 0
            p.volume = self.baseVolume
            p.prepareToPlay()
            p.play()
        }
    }
}

// MARK: - Loading 音效播完回調

/// 獨立 delegate helper：避免 SFXPlayer 同時繼承 NSObject 同 ObservableObject
private final class VLMLoadingDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinished: (() -> Void)?
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinished?()
    }
}
