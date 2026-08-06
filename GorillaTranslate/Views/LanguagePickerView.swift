import SwiftUI

struct LanguagePickerView: View {
    let languages: [Language]
    let selectedLanguage: Language
    let onSelect: (Language) -> Void
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(languages) { language in
                        Button(action: { onSelect(language) }) {
                            HStack(spacing: 16) {
                                Text(language.flag)
                                    .font(.title)

                                Text(language.displayName)
                                    .font(.headline)
                                    .foregroundStyle(.primary)

                                Spacer()

                                if language.id == selectedLanguage.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .padding(16)
                        }
                        .buttonStyle(.glass)
                    }
                }
                .padding(16)
            }
            .navigationTitle("Select Language")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
