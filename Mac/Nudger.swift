import Foundation
import VagoKit

/// Decides when to ask "Work or scroll?" and shows the floating panel.
///
/// Vago decides on its own, so it asks rarely. Two cases: the front place is ambiguous, the
/// classifier is unsure, and the owner has stayed on it for a minute (at most once per place per
/// day); or the owner hits a distraction during a focus session (at most once per site in 10
/// minutes). Answers are held by the model for the rest of the day.
@MainActor
final class Nudger {
    static let cooldown: TimeInterval = 10 * 60
    static let dwellSeconds: TimeInterval = 60

    private let panel = NudgePanel()
    private var lastShown: [String: Date] = [:]
    private var askedToday: Set<String> = []
    private var dwellKey: String?
    private var dwellSince = Date()
    private let answer: @MainActor (String, Bucket) -> Void

    init(answer: @escaping @MainActor (String, Bucket) -> Void) {
        self.answer = answer
    }

    func consider(key: String, label: String, classification c: Classification, answered: Bool, focus: FocusSession?, now: Date) {
        if key != dwellKey {
            dwellKey = key
            dwellSince = now
            if panel.tag == "nudge" { panel.close() }  // the owner has moved on
        }
        guard !answered, !panel.isShowing else { return }

        let growing = focus?.state == .growing
        if c.ambiguous && c.unclear {
            // Ambiguous and unsure: ask once a day, after a minute on the place, never for a passing tab.
            guard !askedToday.contains(key), now.timeIntervalSince(dwellSince) >= Self.dwellSeconds else { return }
            askedToday.insert(key)
            lastShown[key] = now
            let title = growing ? "\(focus?.stage(at: now) ?? "🌱") at risk — work or scroll?" : "Work or scroll?"
            panel.show(title: title, subtitle: label, buttons: [
                .init(title: "Work", prominent: true) { [answer] in answer(key, .productive) },
                .init(title: "Scroll", prominent: false) { [answer] in answer(key, .procrastination) },
            ])
        } else if growing, c.bucket == .procrastination {
            // A clear distraction in the middle of a focus session: the first second is enough.
            if let last = lastShown[key], now.timeIntervalSince(last) < Self.cooldown { return }
            lastShown[key] = now
            panel.show(title: "\(focus?.stage(at: now) ?? "🌱") at risk — back to work?", subtitle: label, buttons: [
                .init(title: "Back to work", prominent: true) {},
                .init(title: "Scroll", prominent: false) {},
            ])
        }
    }

    /// Clears the dwell timer and hides the panel (locked, idle, new focus session).
    func reset() {
        dwellKey = nil
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

    /// True while a "Work or scroll?" question waits for an answer.
    var showingNudge: Bool { panel.tag == "nudge" }

    func closeBreak() {
        if panel.tag == "break" { panel.close() }
    }

    /// A new day: every place may be asked once again.
    func forgetDay() {
        lastShown = [:]
        askedToday = []
    }
}
