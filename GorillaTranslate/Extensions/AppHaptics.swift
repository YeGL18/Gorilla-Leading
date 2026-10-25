import SwiftUI
import UIKit
import MapKit

@MainActor
enum AppHaptics {
    static let preferenceKey = "interactionHapticsEnabled"
    private static var lastFeedback = -Double.infinity
    enum Kind { case tap, selection, longPress }

    static func enabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: preferenceKey) as? Bool ?? true
    }

    static func play(_ kind: Kind) {
        let now = ProcessInfo.processInfo.systemUptime
        guard enabled(), now - lastFeedback >= 0.12 else { return }
        lastFeedback = now
        switch kind {
        case .tap: UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.55)
        case .selection: UISelectionFeedbackGenerator().selectionChanged()
        case .longPress: UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.7)
        }
    }
}

/// Window-level observation covers sheets too, without replacing button styles or consuming gestures.
struct AppHapticObserver: UIViewRepresentable {
    func makeUIView(context: Context) -> Observer { Observer() }
    func updateUIView(_ uiView: Observer, context: Context) {}
    static func dismantleUIView(_ uiView: Observer, coordinator: ()) { uiView.detach() }

    final class Observer: UIView, UIGestureRecognizerDelegate {
        private weak var installedWindow: UIWindow?
        private var recognizers: [UIGestureRecognizer] = []
        private var kind: AppHaptics.Kind = .tap

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window !== installedWindow else { return }
            detach()
            guard let window else { return }
            installedWindow = window
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
            hold.minimumPressDuration = 0.55
            hold.allowableMovement = 8
            recognizers = [tap, hold]
            for recognizer in recognizers {
                recognizer.cancelsTouchesInView = false
                recognizer.delaysTouchesBegan = false
                recognizer.delaysTouchesEnded = false
                recognizer.delegate = self
                window.addGestureRecognizer(recognizer)
            }
        }

        func detach() {
            for recognizer in recognizers { installedWindow?.removeGestureRecognizer(recognizer) }
            recognizers = []
            installedWindow = nil
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard AppHaptics.enabled(), window?.windowScene?.activationState == .foregroundActive else { return false }
            kind = .tap
            var view = touch.view
            while let candidate = view {
                // Map markers provide their own feedback at the actual drag unlock time.
                if gestureRecognizer is UILongPressGestureRecognizer, candidate is MKMapView { return false }
                if candidate is UITextField || candidate is UITextView { return false }
                if let control = candidate as? UIControl {
                    guard control.isEnabled else { return false }
                    if control is UISwitch || control is UISegmentedControl { kind = .selection }
                }
                if candidate is UITabBar || candidate is UINavigationBar { kind = .selection }
                view = candidate.superview
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

        @objc private func tapped() { AppHaptics.play(kind) }
        @objc private func held(_ recognizer: UILongPressGestureRecognizer) {
            if recognizer.state == .began { AppHaptics.play(.longPress) }
        }
    }
}
