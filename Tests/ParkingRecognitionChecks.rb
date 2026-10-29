require 'fileutils'

repo = File.expand_path('..', __dir__)
source = File.read("#{repo}/GorillaTranslate/ContentView.swift")
settings = File.read("#{repo}/GorillaTranslate/Views/SettingsView.swift")
def extract(source, first, last)
  start = source.index(first) or abort "Missing #{first}"
  finish = source.index(last, start) or abort "Missing #{last}"
  source[start...finish]
end
methods = extract(source, '    private func recognizeParkingWithLLM(', '    private func startLLMPollingAfterAction()') +
  extract(source, '    private func parseParkingLLMResponse(', '    private func startParkingInfoSwitchTimer()')
methods = methods.gsub('private func', 'func').gsub('{ @MainActor in', '{ @MainActor [self] in')
enum_source = extract(settings, 'enum ParkingRecognitionMethod:', "@available(iOS 27.0, *)\n@Generable")
root = '/private/tmp/gorilla-recognition-checks'
FileUtils.mkdir_p(root)
File.write("#{root}/Checks.swift", <<~SWIFT)
  import Foundation
  #{enum_source}
  struct UIImage {}
  @MainActor final class UIPasteboard {
      static let general = UIPasteboard()
      var image: UIImage?
  }
  @MainActor enum ParkingImageRecognition {
      static var isAvailable = true
      static let status = "Unavailable"
      static var result = "車位：A123\\n樓層：2\\n區域：B"
      static var fail = false
      static func recognize(_ image: UIImage) async throws -> String {
          let text = result, shouldFail = fail
          try? await Task.sleep(nanoseconds: 20_000_000)
          if shouldFail { throw NSError(domain: "Test", code: 1) }
          return text
      }
  }
  final class Sound {
      func playVLMLoading() {}
      func stopVLMLoadingImmediately() {}
      func stopVLMLoadingGracefully() {}
      func playVLMDone() {}
  }
  final class ParkingFloorStore {
      struct Point { var predictedFloorIndex: Int? }
      var allPoints: [Point] = []
      static func cleanFloorText(_ text: String) -> String? { text }
  }
  @MainActor final class Recognition {
      var isNonAutomotiveArrival = false, hasParkingSpotData = false
      var currentRecognizingPhotoID: UUID?, pendingFloorPhotoID: UUID?
      var activeRecognitionMethod = ParkingRecognitionMethod.shortcut
      var parkingRecognitionMethod = "shortcut"
      var parkingImageRecognitionTask: Task<Void, Never>?
      var llmRawResult: String?, llmError: String?
      var parkingInfoSwitchTimer: Timer?, llmSoundStopTimer: Timer?, llmPollTimer: Timer?
      var showLLMActionPrompt = false, isRecognizing = false, showFloorConfirm = false
      var hasConfirmedFloorThisSession = false
      var llmSpotNumber: String?, llmAreaCode: String?, llmFloorText: String?, llmFloorIndex: Int?
      var pendingOriginalFloorIndex: Int?, pendingFloorText: String?, pendingFloorIndex: Int?
      var recognizedFloorToConfirm: Int?, recognizedFloorText: String?
      var parkingPhotoContributions: [UUID: [String: String]] = [:]
      var merges = 0, floorExcludedMerges = 0
      let sfxPlayer = Sound(), parkingFloorStore = ParkingFloorStore()
      func startOrbRecognitionBoost() {}
      func stopOrbRecognitionBoost() {}
      func stopOrbRecognitionBoostGradually(triggerSixColor: Bool) {}
      func mergeParkingInfoExcludingFloor() { floorExcludedMerges += 1 }
      func mergeAndDisplayParkingInfo() { merges += 1 }
      func saveParkingContributions() {}
      static func parseFloorIndex(_ text: String) -> Int? { Int(text) }
  #{methods}
  }
  @main struct Checks {
      @MainActor static func main() async {
          let r = Recognition(), id = UUID()
          r.recognizeParkingWithLLM(image: UIImage(), photoID: id)
          precondition(r.showLLMActionPrompt && UIPasteboard.general.image != nil)
          r.cancelParkingImageRecognition()
          UIPasteboard.general.image = nil
          r.parkingRecognitionMethod = "foundationModels"
          r.recognizeParkingWithLLM(image: UIImage(), photoID: id)
          precondition(r.isRecognizing && !r.showLLMActionPrompt && UIPasteboard.general.image == nil)
          await r.parkingImageRecognitionTask?.value
          precondition(r.parkingPhotoContributions[id]?["spot"] == "A123")
          precondition(r.parkingPhotoContributions[id]?["method"] == "foundationModels")
          precondition(!r.isRecognizing && r.llmFloorIndex == 2)
          let pending = UUID()
          r.parkingFloorStore.allPoints = [.init(predictedFloorIndex: 1)]
          r.recognizeParkingWithLLM(image: UIImage(), photoID: pending)
          await r.parkingImageRecognitionTask?.value
          precondition(r.showFloorConfirm && r.pendingFloorPhotoID == pending)
          precondition(r.floorExcludedMerges == 1 && r.parkingPhotoContributions[pending]?["floor"] == nil)
          ParkingImageRecognition.result = "車位：未識別\\n樓層：未識別\\n區域：未識別"
          let unreadable = UUID()
          r.recognizeParkingWithLLM(image: UIImage(), photoID: unreadable)
          await r.parkingImageRecognitionTask?.value
          precondition(r.parkingPhotoContributions[unreadable] == nil, "Do not copy old photo values into a new result")
          precondition(r.llmError != nil && r.llmRawResult?.contains("未識別") == true)
          let formatted = UUID()
          ParkingImageRecognition.result = "**車位號：** ABC-12345\\n- 區域號：綠色\\n樓層：-\\n識別邏輯：大堂門口 3 不是樓層\\n樓層：3"
          r.recognizeParkingWithLLM(image: UIImage(), photoID: formatted)
          await r.parkingImageRecognitionTask?.value
          precondition(r.parkingPhotoContributions[formatted]?["spot"] == "ABC-12345")
          precondition(r.parkingPhotoContributions[formatted]?["area"] == "綠色")
          precondition(r.parkingPhotoContributions[formatted]?["floor"] == nil, "Reasoning must never become floor data")
          let cancelled = UUID()
          ParkingImageRecognition.result = "車位：Z999"
          r.recognizeParkingWithLLM(image: UIImage(), photoID: cancelled)
          let task = r.parkingImageRecognitionTask
          r.cancelParkingImageRecognition()
          await task?.value
          precondition(r.parkingPhotoContributions[cancelled] == nil && !r.isRecognizing)
          ParkingImageRecognition.isAvailable = false
          r.recognizeParkingWithLLM(image: UIImage(), photoID: UUID())
          precondition(r.llmError == "Unavailable" && !r.isRecognizing && !r.showLLMActionPrompt)
          ParkingImageRecognition.isAvailable = true
          ParkingImageRecognition.fail = true
          r.recognizeParkingWithLLM(image: UIImage(), photoID: UUID())
          await r.parkingImageRecognitionTask?.value
          precondition(r.llmError != nil && !r.isRecognizing && r.currentRecognizingPhotoID == nil)
          r.llmError = nil
          r.isNonAutomotiveArrival = true
          r.hasParkingSpotData = false
          r.recognizeParkingWithLLM(image: UIImage(), photoID: UUID())
          precondition(!r.isRecognizing && r.currentRecognizingPhotoID == nil)
          print("PASS: shortcut/native routing, parsed results, floor confirmation, missing values, cancellation, unavailable model, failure and stay exclusion")
      }
  }
SWIFT
abort 'Compilation failed' unless system('swiftc', '-parse-as-library', '-module-cache-path', '/private/tmp/gorilla-swift-test-cache', "#{root}/Checks.swift", '-o', "#{root}/checks")
abort 'Tests failed' unless system("#{root}/checks")
