import SwiftUI
import UIKit
struct ParkingRecognitionInfoAlert: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var isPresented: Bool
    let message: String
    let onEdit: () -> Void
    let onClear: () -> Void
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content.background {
            ParkingRecognitionAlertPresenter(isPresented: $isPresented, message: message,
                dark: colorScheme == .dark, onEdit: onEdit, onClear: onClear, onConfirm: onConfirm)
                .frame(width: 0, height: 0)
        }
    }
}

private struct ParkingRecognitionAlertPresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let message: String
    let dark: Bool
    let onEdit: () -> Void
    let onClear: () -> Void
    let onConfirm: () -> Void

    func makeUIViewController(context: Context) -> Host { Host() }
    func updateUIViewController(_ host: Host, context: Context) { host.update(self) }

    final class Host: UIViewController {
        private var presentation: ParkingRecognitionAlertPresenter?
        private weak var activeAlert: UIAlertController?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            if let presentation { update(presentation) }
        }

        func update(_ presentation: ParkingRecognitionAlertPresenter) {
            self.presentation = presentation
            guard presentation.isPresented else {
                activeAlert?.dismiss(animated: true)
                activeAlert = nil
                return
            }
            if let activeAlert {
                activeAlert.message = presentation.message
                applyAppearance(to: activeAlert, dark: presentation.dark)
                return
            }
            guard viewIfLoaded?.window != nil, presentedViewController == nil else { return }
            let alert = UIAlertController(title: String(localized: "車位資訊"),
                message: presentation.message, preferredStyle: .alert)
            for (title, style, action) in [
                (String(localized: "編輯"), UIAlertAction.Style.default, presentation.onEdit),
                (String(localized: "清除車位"), .destructive, presentation.onClear),
                (String(localized: "確定"), .cancel, presentation.onConfirm)
            ] {
                alert.addAction(UIAlertAction(title: title, style: style) { [weak self] _ in
                    self?.activeAlert = nil
                    self?.presentation?.isPresented = false
                    action()
                })
            }
            applyAppearance(to: alert, dark: presentation.dark)
            activeAlert = alert
            present(alert, animated: true)
        }

        private func applyAppearance(to alert: UIAlertController, dark: Bool) {
            alert.overrideUserInterfaceStyle = dark ? .dark : .light
            alert.view.tintColor = dark ? .white : UIColor(named: "AccentColor")
        }
    }
}

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
