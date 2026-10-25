import Foundation
import AVFoundation
import CoreHaptics
import UIKit

@preconcurrency import AVFoundation

enum SFXPreferences {
    static let launchKey = "launchSoundVersion"
    static let movementKey = "movementSoundVersion"
    static let parkingReminderFile = "sfx_parking_time_notifi.caf"

    static func launchName(defaults: UserDefaults = .standard) -> String {
        defaults.integer(forKey: launchKey) == 1 ? "gorilla_launch2" : "gorilla_launch"
    }

    static func movementVersion(defaults: UserDefaults = .standard) -> Int {
        (defaults.object(forKey: movementKey) as? Int) == 0 ? 0 : 1
    }

    static func movementNames(version: Int) -> (stationary: String, driving: String) {
        version == 0
            ? ("sfx_enter_stationary", "sfx_enter_driving")
            : ("sfx_enter_stationary_v2", "sfx_enter_driving_v2")
    }
}

enum AudioHapticEnvelope {
    static func intensity(decibels: Float, volume: Float) -> Float {
        guard decibels.isFinite, volume.isFinite else { return 0 }
        let amplitude = max(0, pow(10, min(0, decibels) / 20) - 0.004)
        return min(0.65, sqrt(amplitude) * 0.65 * min(1, max(0, volume)))
    }
}

@MainActor
final class SFXPlayer: ObservableObject {
    private var stationaryPlayer: AVAudioPlayer?
    private var drivingPlayer: AVAudioPlayer?
    private var loadedMovementVersion: Int?
    private var launchPreviewPlayer: AVAudioPlayer?
    private var parkingReminderPreviewPlayer: AVAudioPlayer?
    private var accelerationPlayer: AVAudioPlayer?
    private var meterDestinationPlayer: AVAudioPlayer?
    private var destinationPredictPlayer: AVAudioPlayer?
    private var accelerationStopWork: DispatchWorkItem?
    private var accelerationFadeStartWork: DispatchWorkItem?
    private var accelerationFadeTimer: Timer?
    private var accelerationFadeInTimer: Timer?

    private var vlmLoadingPlayer: AVAudioPlayer?
    private var vlmDonePlayer: AVAudioPlayer?
    private let vlmHaptics = AudioEnvelopeHaptics()
    private var vlmFadeTimer: Timer?
    private var vlmDoneWork: DispatchWorkItem?
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
            prepareMovementPlayers()
            accelerationPlayer = loadPlayer(name: "sfx_acceleration_overlay", volume: min(1.0, baseVolume * 1.5))
        }
    }
    
    func playEnterStationary() {
        prepareMovementPlayers()
        drivingPlayer?.stop()
        let names = SFXPreferences.movementNames(version: loadedMovementVersion ?? 1)
        playOnce(&stationaryPlayer, fallbackName: names.stationary, volumeMultiplier: 1.5)
    }

    func playEnterDriving() {
        prepareMovementPlayers()
        stationaryPlayer?.stop()
        let names = SFXPreferences.movementNames(version: loadedMovementVersion ?? 1)
        playOnce(&drivingPlayer, fallbackName: names.driving, volumeMultiplier: 1.5)
    }

    private func prepareMovementPlayers() {
        let version = SFXPreferences.movementVersion()
        guard loadedMovementVersion != version else { return }
        stationaryPlayer?.stop()
        drivingPlayer?.stop()
        let names = SFXPreferences.movementNames(version: version)
        stationaryPlayer = loadPlayer(name: names.stationary, volume: baseVolume)
        drivingPlayer = loadPlayer(name: names.driving, volume: baseVolume)
        loadedMovementVersion = version
    }

    func previewLaunchSound() {
        launchPreviewPlayer?.stop()
        launchPreviewPlayer = nil
        playOnce(&launchPreviewPlayer, fallbackName: SFXPreferences.launchName())
    }

    func previewParkingReminder() {
        playOnce(&parkingReminderPreviewPlayer, fallbackName: "sfx_parking_time_notifi", fileExtension: "caf")
    }

    func stopPreviews() {
        launchPreviewPlayer?.stop()
        parkingReminderPreviewPlayer?.stop()
        stationaryPlayer?.stop()
        drivingPlayer?.stop()
    }

    func playMeterDestinationNotice() {
        playOnce(&meterDestinationPlayer, fallbackName: "sfx_meter_destination")
    }

    /// 預測目的地提示音：彈出確認卡／自動切換 toast 時播放
    func playDestinationPredict() {
        playOnce(&destinationPredictPlayer, fallbackName: "sfx_destination_predict")
    }
    
    private static var launchPlayer: AVAudioPlayer?

    func playLaunchSound() {
        let session = AVAudioSession.sharedInstance()
        // 避免 main thread 阻塞：setCategory + setActive 都放 background
        DispatchQueue.global(qos: .userInitiated).async {
            try? session.setCategory(.playback, mode: .default, options: [])
            try? session.setActive(true, options: [])
            DispatchQueue.main.async {
                if let url = self.resolveURL(name: SFXPreferences.launchName()) {
                    let p = try? AVAudioPlayer(contentsOf: url)
                    p?.delegate = nil
                    p?.volume = self.baseVolume
                    p?.prepareToPlay()
                    p?.play()
                    SFXPlayer.launchPlayer = p // 防止被回收
                    // 播放完畢後恢復 ambient session
                    DispatchQueue.main.asyncAfter(deadline: .now() + (p?.duration ?? 3) + 0.1) {
                        guard SFXPlayer.launchPlayer === p else { return }
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
    
    private func playOnce(_ player: inout AVAudioPlayer?, fallbackName: String, volumeMultiplier: Float = 1.0, fileExtension: String = "mp3") {
        configureAudioSession()
        let vol = baseVolume * volumeMultiplier
        if player == nil {
            player = loadPlayer(name: fallbackName, volume: vol, fileExtension: fileExtension)
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
    
    private func loadPlayer(name: String, volume: Float, fileExtension: String = "mp3") -> AVAudioPlayer? {
        guard let url = resolveURL(name: name, fileExtension: fileExtension) else { return nil }
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
    
    private func resolveURL(name: String, fileExtension: String = "mp3") -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: fileExtension, subdirectory: "Resources/Audio/SFX") {
            return url
        }
        if let url = Bundle.main.url(forResource: name, withExtension: fileExtension, subdirectory: "Audio/SFX") {
            return url
        }
        return Bundle.main.url(forResource: name, withExtension: fileExtension)
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
        cancelVLMTransition()
        vlmDonePlayer?.stop()
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
        vlmHaptics.follow(p)
    }

    /// 停止 loading 音效：淡出 0.3 秒後停止
    func stopVLMLoadingGracefully() {
        cancelVLMTransition()
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
        vlmFadeTimer = fadeTimer
        RunLoop.main.add(fadeTimer, forMode: .common)
    }

    /// 立即停止 loading 音效
    func stopVLMLoadingImmediately() {
        cancelVLMTransition()
        vlmHaptics.stop()
        vlmLoadingStopAfterCurrent = false
        vlmLoadingPlayer?.stop()
        vlmLoadingPlayer?.currentTime = 0
    }

    /// 播放一次 done 音效（loading 淡出 0.2s，done 延遲 0.2s）
    func playVLMDone() {
        cancelVLMTransition()
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
        vlmFadeTimer = fadeTimer
        RunLoop.main.add(fadeTimer, forMode: .common)

        // done 音效延遲 0.2 秒播放
        let work = DispatchWorkItem { [weak self] in
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
            self.vlmHaptics.follow(p)
        }
        vlmDoneWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func cancelVLMTransition() {
        vlmFadeTimer?.invalidate()
        vlmFadeTimer = nil
        vlmDoneWork?.cancel()
        vlmDoneWork = nil
    }
}

/// Reads the playing sound's envelope, including loops and fades, rather than inventing a pulse rhythm.
@MainActor
private final class AudioEnvelopeHaptics {
    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?
    private var meter: Timer?

    func follow(_ audio: AVAudioPlayer) {
        stop()
        guard AppHaptics.enabled(), CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              UIApplication.shared.applicationState == .active else { return }
        do {
            if engine == nil {
                let engine = try CHHapticEngine()
                engine.isAutoShutdownEnabled = true
                engine.resetHandler = { [weak self] in Task { @MainActor in self?.stop(); self?.engine = nil } }
                engine.stoppedHandler = { [weak self] _ in Task { @MainActor in self?.stop() } }
                self.engine = engine
            }
            guard let engine else { return }
            try engine.start()
            let duration = min(30, max(0.1, audio.duration))
            let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.35)
            ], relativeTime: 0, duration: duration)
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makeAdvancedPlayer(with: pattern)
            player.loopEnabled = true
            player.loopEnd = duration
            self.player = player
            audio.isMeteringEnabled = true
            try player.sendParameters([CHHapticDynamicParameter(parameterID: .hapticIntensityControl,
                                                                value: 0, relativeTime: 0)], atTime: 0)
            try player.start(atTime: CHHapticTimeImmediate)
            let timer = Timer(timeInterval: 1.0 / 50, repeats: true) { [weak self, weak audio] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    guard let audio, audio.isPlaying, AppHaptics.enabled(),
                          UIApplication.shared.applicationState == .active else { self.stop(); return }
                    audio.updateMeters()
                    let db = (0..<max(1, audio.numberOfChannels)).map { audio.averagePower(forChannel: $0) }.max() ?? -160
                    let intensity = AudioHapticEnvelope.intensity(decibels: db, volume: audio.volume)
                    do {
                        try self.player?.sendParameters([CHHapticDynamicParameter(parameterID: .hapticIntensityControl,
                            value: intensity, relativeTime: 0)], atTime: CHHapticTimeImmediate)
                    } catch { self.stop() }
                }
            }
            meter = timer
            RunLoop.main.add(timer, forMode: .common)
        } catch { stop() }
    }

    func stop() {
        meter?.invalidate()
        meter = nil
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
    }

    deinit { meter?.invalidate() }
}

// MARK: - Loading 音效播完回調

/// 獨立 delegate helper：避免 SFXPlayer 同時繼承 NSObject 同 ObservableObject
private final class VLMLoadingDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinished: (() -> Void)?
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinished?()
    }
}
