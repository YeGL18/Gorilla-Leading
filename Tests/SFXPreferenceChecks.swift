import Foundation
import AVFoundation

@main
struct SFXPreferenceChecks {
    static func main() throws {
        let suite = "gorilla-sfx-checks-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        precondition(SFXPreferences.launchName(defaults: defaults) == "gorilla_launch")
        precondition(SFXPreferences.movementVersion(defaults: defaults) == 1)
        for version in [0, 1, 0, 1] {
            defaults.set(version, forKey: SFXPreferences.launchKey)
            defaults.set(version, forKey: SFXPreferences.movementKey)
            precondition(SFXPreferences.launchName(defaults: defaults)
                == (version == 0 ? "gorilla_launch" : "gorilla_launch2"))
            let pair = SFXPreferences.movementNames(version: SFXPreferences.movementVersion(defaults: defaults))
            precondition(pair.stationary == (version == 0 ? "sfx_enter_stationary" : "sfx_enter_stationary_v2"))
            precondition(pair.driving == (version == 0 ? "sfx_enter_driving" : "sfx_enter_driving_v2"))
            let restored = UserDefaults(suiteName: suite)!
            precondition(SFXPreferences.launchName(defaults: restored) == SFXPreferences.launchName(defaults: defaults))
            precondition(SFXPreferences.movementVersion(defaults: restored) == version)
        }
        defaults.set(99, forKey: SFXPreferences.movementKey)
        precondition(SFXPreferences.movementVersion(defaults: defaults) == 1)
        precondition(SFXPreferences.parkingReminderFile != "gorilla_parking_status_notifi.mp3")
        let audioRoot = URL(fileURLWithPath: CommandLine.arguments[1])
        let reminder = try AVAudioFile(forReading: audioRoot.appendingPathComponent(SFXPreferences.parkingReminderFile))
        let duration = Double(reminder.length) / reminder.processingFormat.sampleRate
        precondition(duration > 0 && duration < 30)
        precondition(reminder.fileFormat.settings[AVFormatIDKey] as? UInt32 == kAudioFormatLinearPCM)
        for name in ["gorilla_launch", "gorilla_launch2", "sfx_enter_stationary", "sfx_enter_driving",
                     "sfx_enter_stationary_v2", "sfx_enter_driving_v2"] {
            precondition(FileManager.default.fileExists(atPath: audioRoot.appendingPathComponent(name + ".mp3").path))
        }
        print("PASS: persistent launch choices, atomic movement pairs, original files retained, dedicated PCM notification sound (\(duration)s)")
    }
}
