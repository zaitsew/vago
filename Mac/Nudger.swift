import Foundation
import VagoKit

/// Shows the floating panel: the focus nudge, the move reminder, toasts and the evening review.
///
/// Vago never asks during the day whether a place is work. A place it is unsure about counts as
/// neutral and waits in "Vago's calls"; once in the evening, if any are waiting, one panel offers
/// to review them (`AppModel.considerEveningReview`). The one daytime panel about a place is the
/// focus nudge: the owner started the session, and a clear distraction puts it at risk (at most
/// once per site in 10 minutes).
@MainActor
final class Nudger {
    static let cooldown: TimeInterval = 10 * 60

    private let panel = NudgePanel()
    private var lastShown: [String: Date] = [:]
    private var lastKey: String?

    func consider(key: String, label: String, classification c: Classification, focus: FocusSession?, now: Date) {
        if key != lastKey {
            lastKey = key
            if panel.tag == "nudge" { panel.close() }  // the owner has moved on
        }
        guard !panel.isShowing, focus?.state == .growing, c.bucket == .procrastination else { return }
        // A clear distraction in the middle of a focus session: the first second is enough.
        if let last = lastShown[key], now.timeIntervalSince(last) < Self.cooldown { return }
        lastShown[key] = now
        panel.show(title: "\(focus?.stage(at: now) ?? "🌱") at risk — back to work?", subtitle: label, buttons: [
            .init(title: "Back to work", prominent: true) {},
            .init(title: "Scroll", prominent: false) {},
        ])
    }

    /// Hides the panel (locked, idle, new focus session).
    func reset() {
        lastKey = nil
        panel.close()
    }

    func toast(_ text: String) {
        guard panel.tag != "break" else { return }
        panel.show(title: text, subtitle: nil, buttons: [], seconds: 8, tag: "toast")
    }

    /// The move reminder. Stays 90 seconds; closing by itself counts as unanswered.
    func showBreak(move: Move, minutes: Int, done: @escaping @MainActor () -> Void, another: @escaping @MainActor () -> Void,
                   later: @escaping @MainActor () -> Void, ignored: @escaping @MainActor () -> Void) {
        panel.show(
            title: "🚶 \(minutes) min at the Mac. Time to move",
            subtitle: move.title,
            detail: move.how,
            buttons: [
                .init(title: "I did it", prominent: true, action: done),
                .init(title: "Another", prominent: false, keepsOpen: true, action: another),
                .init(title: "Later", prominent: false, action: later),
            ],
            seconds: 90, tag: "break", timedOut: ignored
        )
    }

    /// True while the focus nudge or the evening review is on screen.
    var showingNudge: Bool { panel.tag == "nudge" || panel.tag == "review" }

    /// True while any panel is on screen.
    var isShowing: Bool { panel.isShowing }

    /// The evening review offer: once a day, only when Vago has unsure calls waiting.
    /// Stays a minute; closing by itself counts as "Not today".
    func showEveningReview(count: Int, review: @escaping @MainActor () -> Void) {
        let places = count == 1 ? "1 place" : "\(count) places"
        panel.show(
            title: "Vago was unsure about \(places) today",
            subtitle: "Work or waste? Each answer becomes a rule.",
            buttons: [
                .init(title: "Review", prominent: true, action: review),
                .init(title: "Not today", prominent: false) {},
            ],
            seconds: 60, tag: "review"
        )
    }

    func closeBreak() {
        if panel.tag == "break" { panel.close() }
    }

    /// A new day: the focus nudge's cooldowns start over.
    func forgetDay() {
        lastShown = [:]
    }
}
