import Foundation

struct TranslationRecord: Identifiable, Codable {
    let id: UUID
    let inputText: String
    let outputText: String
    let sourceLanguage: String
    let targetLanguage: String
    let timestamp: Date
    
    init(inputText: String, outputText: String, sourceLanguage: String, targetLanguage: String) {
        self.id = UUID()
        self.inputText = inputText
        self.outputText = outputText
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.timestamp = Date()
    }
}

@MainActor
class HistoryManager: ObservableObject {
    @Published var records: [TranslationRecord] = []
    
    private let storageKey = "translation_history"
    private var hasLoaded = false
    
    init() {}
    
    func prepare() {
        guard !hasLoaded else { return }
        hasLoaded = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            load()
        }
    }
    
    func add(inputText: String, outputText: String, sourceLanguage: String, targetLanguage: String) {
        let record = TranslationRecord(
            inputText: inputText,
            outputText: outputText,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage
        )
        records.insert(record, at: 0)
        save()
    }
    
    func delete(at offsets: IndexSet) {
        records.remove(atOffsets: offsets)
        save()
    }
    
    func delete(_ record: TranslationRecord) {
        records.removeAll { $0.id == record.id }
        save()
    }
    
    private func save() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([TranslationRecord].self, from: data) else {
            records = []
            return
        }
        records = decoded
    }
}