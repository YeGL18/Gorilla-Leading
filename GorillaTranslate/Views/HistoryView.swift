import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var historyManager: HistoryManager

    var body: some View {
        NavigationStack {
            ZStack {
                if historyManager.records.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 48))
                            .foregroundStyle(.tertiary)
                        Text("No translation history yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    List {
                        ForEach(historyManager.records) { record in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(record.sourceLanguage)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "arrow.right")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                    Text(record.targetLanguage)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(record.timestamp, style: .time)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record.inputText)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    Text(record.outputText)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(3)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete { offsets in
                            historyManager.delete(at: offsets)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("History")
            .toolbar {
                if !historyManager.records.isEmpty {
                    EditButton()
                }
            }
        }
    }
}

#Preview {
    HistoryView()
        .environmentObject(HistoryManager())
}
