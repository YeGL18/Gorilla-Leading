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

    /// Starts the Live Activity, or updates the running one with the latest snapshot.
    func sync(_ state: GorillaActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // Recover an activity that survived an app relaunch.
        if activity == nil {
            activity = Activity<GorillaActivityAttributes>.activities.first
        }

        if let activity {
            Task {
                await activity.update(ActivityContent(state: state, staleDate: nil))
            }
            return
        }

        do {
            activity = try Activity.request(
                attributes: GorillaActivityAttributes(),
                contentState: state,
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
    }
}
