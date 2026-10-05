import ActivityKit
import Foundation

/// Bridges the app's visit-status state machine to the system Live Activity
/// (Dynamic Island + Lock Screen).
///
/// State mapping (see `ContentView.updateVisitStatus()`):
///   已泊車 → `.parking`    timer anchored at parking start
///   已開車 → `.driving`    timer anchored at departure
///   已停留 → `.stationary` timer anchored at stationary start
///
/// The timer text itself is rendered by WidgetKit (`Text(_, style: .timer)`),
/// so updates are only needed when the state or its context changes —
/// never on every tick.
@MainActor
final class GorillaActivityManager {
    static let shared = GorillaActivityManager()
    private init() {}

    private var activity: Activity<GorillaActivityAttributes>?
    /// The last state we pushed, used to detect 泊車/開車/停留 transitions.
    private var lastState: GorillaActivityState?

    /// Starts the Live Activity, or updates the running one with the latest snapshot.
    /// - Parameter forceRefresh: bumps `renderNonce` so the payload is always
    ///   different from the archived render — used when the app foregrounds to
    ///   guarantee the system re-renders with the latest widget build.
    func sync(_ newState: GorillaActivityAttributes.ContentState, forceRefresh: Bool = false) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // Recover an activity that survived an app relaunch.
        if activity == nil {
            if let existing = Activity<GorillaActivityAttributes>.activities.first {
                activity = existing
                // Baseline for transition detection = what's actually showing.
                lastState = existing.content.state.state
            }
        }

        var content = newState
        content.languageCode = Bundle.main.preferredLocalizations.first ?? "en"
        if forceRefresh {
            content.renderNonce = Int(Date().timeIntervalSince1970)
        }

        if let activity {
            // 狀態轉變（泊車/開車/停留 互換）→ 帶 alert 更新，
            // 靈動島會擴展一次展示新狀態，然後自動收返 compact。
            let stateChanged = lastState != nil && lastState != content.state
            lastState = content.state
            Task {
                if stateChanged {
                    let alert = AlertConfiguration(
                        title: LocalizedStringResource(stringLiteral:
                            GorillaActivityLocalization.string("Gorilla 泊車記憶", languageCode: content.languageCode)),
                        body: LocalizedStringResource(stringLiteral:
                            content.state.localizedLabel(languageCode: content.languageCode)),
                        sound: .default
                    )
                    await activity.update(
                        ActivityContent(state: content, staleDate: nil),
                        alertConfiguration: alert
                    )
                } else {
                    await activity.update(ActivityContent(state: content, staleDate: nil))
                }
            }
            return
        }

        lastState = content.state
        do {
            activity = try Activity.request(
                attributes: GorillaActivityAttributes(),
                contentState: content,
                pushType: nil
            )
        } catch {
            activity = nil
        }
    }

    /// Ends the Live Activity (parking session over).
    func end() {
        guard let activity else { return }
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        self.activity = nil
        self.lastState = nil
    }
}
