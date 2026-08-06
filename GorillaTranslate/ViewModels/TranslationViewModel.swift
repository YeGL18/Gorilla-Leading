import Foundation
import SwiftUI
import FoundationModels

@MainActor
class TranslationViewModel: ObservableObject {
    @Published var inputText: String = ""
    @Published var outputText: String = ""
    @Published var isTranslating: Bool = false
    @Published var sourceLanguage: Language = .english
    @Published var targetLanguage: Language = .chinese
    @Published var modelAvailability: String = "Checking..."
    
    private var session: LanguageModelSession?
    private var translateTask: Task<Void, Never>?
    private var hasPrepared = false
    
    init() {}
    
    func prepare() {
        guard !hasPrepared else { return }
        hasPrepared = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            checkModelAvailability()
        }
    }
    
    private func checkModelAvailability() {
        let model = SystemLanguageModel.default
        
        switch model.availability {
        case .available:
            modelAvailability = "Model Ready"
            session = LanguageModelSession()
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                modelAvailability = "Device not supported"
            case .appleIntelligenceNotEnabled:
                modelAvailability = "Enable Apple Intelligence"
            case .modelNotReady:
                modelAvailability = "Model downloading..."
            @unknown default:
                modelAvailability = "Unavailable"
            }
        @unknown default:
            modelAvailability = "Unknown status"
        }
    }
    
    func translate() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            outputText = ""
            return
        }
        
        isTranslating = true
        
        guard let session = session else {
            outputText = "Model not available. Enable Apple Intelligence in Settings."
            isTranslating = false
            return
        }
        
        translateTask?.cancel()
        translateTask = Task {
            do {
                let prompt = """
                Translate the following text from \(sourceLanguage.displayName) to \(targetLanguage.displayName).
                Only return the translation, nothing else.
                
                Text to translate:
                \(inputText)
                """
                
                let response = try await session.respond(to: prompt)
                
                await MainActor.run {
                    self.outputText = response.content
                    self.isTranslating = false
                    self.translateTask = nil
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.isTranslating = false
                    self.translateTask = nil
                }
            } catch {
                let message: String
                let desc = error.localizedDescription
                if desc.contains("unsafe") || desc.contains("content") {
                    message = "This content was blocked by safety filters. Try rephrasing your text."
                } else {
                    message = "Error: \(desc)"
                }
                await MainActor.run {
                    self.outputText = message
                    self.isTranslating = false
                    self.translateTask = nil
                }
            }
        }
    }
    
    func swapLanguages() {
        let temp = sourceLanguage
        sourceLanguage = targetLanguage
        targetLanguage = temp
        
        if !outputText.isEmpty {
            inputText = outputText
            translate()
        }
    }
    
    func copyToClipboard() {
        UIPasteboard.general.string = outputText
    }
    
    func shareTranslation() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }
        
        let activityVC = UIActivityViewController(
            activityItems: [outputText],
            applicationActivities: nil
        )
        rootVC.present(activityVC, animated: true)
    }
    
    func clearAll() {
        translateTask?.cancel()
        translateTask = nil
        inputText = ""
        outputText = ""
        isTranslating = false
    }
}