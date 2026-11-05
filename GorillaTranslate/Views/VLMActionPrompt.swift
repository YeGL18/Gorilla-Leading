import SwiftUI
import UIKit

struct PlaceRenameAlert: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Binding var isPresented: Bool
    @Binding var name: String
    let title: String
    let message: String
    let allowsEmpty: Bool
    let onSave: (String) -> Void
    func body(content: Content) -> some View {
        content.background {
            PlaceRenamePresenter(isPresented: $isPresented, name: $name, title: title,
                message: message, dark: scheme == .dark, allowsEmpty: allowsEmpty, onSave: onSave)
                .frame(width: 0, height: 0)
        }
    }
}

private struct PlaceRenamePresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    @Binding var name: String
    let title: String
    let message: String
    let dark: Bool
    let allowsEmpty: Bool
    let onSave: (String) -> Void
    func makeUIViewController(context: Context) -> Host { Host() }
    func updateUIViewController(_ host: Host, context: Context) { host.update(self) }
    final class Host: UIViewController {
        private var value: PlaceRenamePresenter?
        private weak var alert: UIAlertController?
        private weak var confirm: UIAlertAction?
        override func viewDidLoad() { super.viewDidLoad(); view.backgroundColor = .clear }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            if let value { update(value) }
        }
        func update(_ value: PlaceRenamePresenter) {
            self.value = value
            guard value.isPresented else { alert?.dismiss(animated: true); alert = nil; return }
            guard alert == nil, viewIfLoaded?.window != nil, presentedViewController == nil else { return }
            let controller = UIAlertController(title: value.title, message: value.message, preferredStyle: .alert)
            controller.overrideUserInterfaceStyle = value.dark ? .dark : .light
            controller.view.tintColor = .systemBlue
            controller.view.tintAdjustmentMode = .normal
            controller.addTextField { field in
                field.placeholder = String(localized: "名稱")
                field.text = value.name
                field.addTarget(self, action: #selector(self.changed(_:)), for: .editingChanged)
            }
            let input = controller.textFields![0]
            let save = UIAlertAction(title: String(localized: "確定"), style: .default) { [weak self] _ in
                // Retain the field, not the alert: UIKit may release its presenter while dismissing.
                let text = (input.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                value.name = text
                value.onSave(text)
                value.isPresented = false
                self?.alert = nil
            }
            save.isEnabled = value.allowsEmpty || !value.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            controller.addAction(UIAlertAction(title: String(localized: "取消"), style: .destructive) { [weak self] _ in
                value.isPresented = false
                self?.alert = nil
            })
            controller.addAction(save)
            controller.preferredAction = save
            confirm = save
            alert = controller
            // The zero-size SwiftUI bridge is not a presentation canvas (notably on Duo).
            // Present from the visible full-size controller so UIKit's hit regions match its layout.
            var presenter = view.window?.rootViewController
            while let next = presenter?.presentedViewController { presenter = next }
            presenter?.present(controller, animated: true)
        }
        @objc private func changed(_ field: UITextField) {
            let text = field.text ?? ""
            value?.name = text
            confirm?.isEnabled = value?.allowsEmpty == true || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

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
