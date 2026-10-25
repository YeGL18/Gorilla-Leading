import SwiftUI

struct VLMActionPrompt: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var isPresented: Bool
    let shortcutName: String
    let onReady: () -> Void
    let onCancel: () -> Void

    func body(content: Content) -> some View {
        content.background {
            // Scope alert tint to its presenter, not the parking controls underneath it.
            Color.clear.frame(width: 0, height: 0)
                .alert("請啟動動作按鈕", isPresented: $isPresented) {
                    Button("已準備好", action: onReady)
                    Button("取消", role: .cancel, action: onCancel)
                } message: {
                    Text(String(format: String(localized: "圖片已複製到剪貼簿。\n請按動作按鈕執行「%@」快捷指令。"), shortcutName))
                }
                .tint(colorScheme == .dark ? .white : .accentColor)
        }
    }
}
