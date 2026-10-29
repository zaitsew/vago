import ActivityKit
import Foundation

/// Starts and refreshes the Live Activity. Only the app can start one; the monitor extension
/// can update it when the system lets it.
@MainActor
enum LiveActivityController {
    /// The last state sent, without its timestamp. Updates are budgeted, so unchanged state is not resent.
    private static var lastSent: VagoActivityAttributes.ContentState?

    static func sync(_ store: VagoStore) async {
        guard store.liveActivityEnabled, store.onboarded else {
            await end()
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let now = Date()
        let state = VagoActivityAttributes.ContentState(
            snapshot: store.snapshot(now: now), focus: store.activeFocus(now: now), now: now
        )
        var comparable = state
        comparable.updatedAt = .distantPast
        let content = ActivityContent(state: state, staleDate: now.addingTimeInterval(30 * 60))
        if let activity = Activity<VagoActivityAttributes>.activities.first {
            guard comparable != lastSent else { return }
            lastSent = comparable
            await activity.update(content)
        } else {
            lastSent = comparable
            _ = try? Activity.request(attributes: VagoActivityAttributes(), content: content)
        }
    }

    static func end() async {
        lastSent = nil
        for activity in Activity<VagoActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
