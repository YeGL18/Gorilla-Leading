import XCTest
import AVFoundation
@testable import CameraSpeechChecks

final class CameraSpeechRuntimeTests: XCTestCase {
    func testVoiceAndSpokenLanguageAlwaysMatch() {
        for requested in CameraSpeechLanguage.allCases {
            let plan = CameraSystemVoice.resolve(requested)
            XCTAssertTrue(plan.language == requested || plan.language == .english)
            if let voice = plan.voice {
                XCTAssertTrue(plan.language.acceptsVoice(voice.language), "\(requested): \(voice.language)")
                XCTAssertFalse(voice.voiceTraits.contains(.isNoveltyVoice))
                XCTAssertFalse(voice.voiceTraits.contains(.isPersonalVoice))
            }
            let text = CameraAlertSpeech.text(for: nil, language: plan.language)
            XCTAssertFalse(text.isEmpty)
            print("Camera voice \(requested.rawValue) -> \(plan.language.rawValue): \(plan.voice?.name ?? "beeps only")")
        }
    }
}
