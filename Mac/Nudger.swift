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
        panel.show(title: String(localized: "\(focus?.stage(at: now) ?? "🌱") at risk — back to work?", comment: "Focus nudge title. The argument is the tree emoji of the running focus session."), subtitle: label, buttons: [
            .init(title: String(localized: "Back to work", comment: "Focus nudge button."), prominent: true) {},
            .init(title: String(localized: "Scroll", comment: "Focus nudge button: keep scrolling."), prominent: false) {},
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
            title: String(localized: "🚶 \(minutes) min at the Mac. Time to move", comment: "Move reminder title. The argument is the minutes at the Mac."),
            subtitle: move.title,
            detail: move.how,
            buttons: [
                .init(title: String(localized: "I did it", comment: "Move reminder button."), prominent: true, action: done),
                .init(title: String(localized: "Another", comment: "Move reminder button: suggest another move."), prominent: false, keepsOpen: true, action: another),
                .init(title: String(localized: "Later", comment: "Move reminder button."), prominent: false, action: later),
            ],
            seconds: 90, tag: "break", timedOut: ignored
        )
    }

    /// True while the focus nudge or the evening review is on screen.
    var showingNudge: Bool { panel.tag == "nudge" || panel.tag == "review" }

    /// True while any panel is on screen.
    var isShowing: Bool { panel.isShowing }

    /// The evening review offer: once a day, only when Vago has unsure calls waiting.
    /// `count` is what the review window lists; `total` is every unsure place today. When the
    /// window cannot list them all, the title says so ("Review 5 of 786 unsure places today").
    /// Stays a minute; closing by itself counts as "Not today".
    func showEveningReview(count: Int, of total: Int, review: @escaping @MainActor () -> Void) {
        let places = count == 1
            ? String(localized: "1 place", comment: "Evening review offer: one unsure place.")
            : String(localized: "\(count) places", comment: "Evening review offer: several unsure places. The argument is the count.")
        panel.show(
            title: total > count
                ? String(localized: "Review \(count) of \(total) unsure places today", comment: "Evening review offer title. First argument: places listed; second: all unsure places.")
                : String(localized: "Vago was unsure about \(places) today", comment: "Evening review offer title. The argument is a phrase such as 3 places."),
            subtitle: String(localized: "Work or waste? Each answer becomes a rule.", comment: "Evening review offer subtitle."),
            buttons: [
                .init(title: String(localized: "Review", comment: "Evening review offer button."), prominent: true, action: review),
                .init(title: String(localized: "Not today", comment: "Evening review offer button: skip today."), prominent: false) {},
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
