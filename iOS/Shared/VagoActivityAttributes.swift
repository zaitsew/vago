import ActivityKit
import Foundation
import VagoKit

/// The Live Activity: today's readout, tinted by mood, and the focus tree while a session runs.
struct VagoActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var emoji: String
        var readout: String            // "😟 28/30m"
        var minutesUsed: Int
        var limitMinutes: Int
        var tint: String               // Tint.rawValue: green, yellow, red
        var focusStage: String?        // "🌱" ... "🌳", while a session runs
        var focusStart: Date?
        var focusEnd: Date?
        var updatedAt: Date

        init(snapshot: Snapshot, focus: FocusSession?, now: Date = .now) {
            let mood = snapshot.mood
            emoji = mood.emoji
            readout = snapshot.readout
            minutesUsed = snapshot.minutesUsed
            limitMinutes = snapshot.limitMinutes
            tint = mood.tint.rawValue
            focusStage = focus?.stage(at: now)
            focusStart = focus?.start
            focusEnd = focus?.end
            updatedAt = now
        }
    }

    var name: String = "Vago"
}

extension VagoActivityAttributes.ContentState {
    var tintValue: Tint { Tint(rawValue: tint) ?? .green }
    var isFocusing: Bool { focusEnd != nil }
}

/// Updates open Live Activities from wherever the process can: the app always, the monitor
/// extension when the system lets it. Starting one is the app's job (`LiveActivityController`).
enum LiveActivityUpdater {
    /// Pushes the current snapshot to every open Live Activity. Returns when the update is delivered.
    static func updateAll(store: VagoStore = VagoStore(), now: Date = .now) async {
        guard store.liveActivityEnabled else { return }
        let state = VagoActivityAttributes.ContentState(
            snapshot: store.snapshot(now: now), focus: store.activeFocus(now: now), now: now
        )
        let content = ActivityContent(state: state, staleDate: now.addingTimeInterval(30 * 60))
        for activity in Activity<VagoActivityAttributes>.activities {
            await activity.update(content)
        }
    }
}
