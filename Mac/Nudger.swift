import Foundation
import VagoKit

/// Decides when to ask "Work or scroll?" and shows the floating panel.
///
/// Two cases: the front place is ambiguous, the classifier could only guess, and the owner has not
/// answered for it today; or the owner hits a distraction during a focus session. Never more than
/// one nudge per site in 10 minutes. Answers are held by the model for the rest of the day.
@MainActor
final class Nudger {
    static let cooldown: TimeInterval = 10 * 60
    static let dwellSeconds: TimeInterval = 5

    private let panel = NudgePanel()
    private var lastShown: [String: Date] = [:]
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
            panel.close()                              // the owner has moved on
        }
        guard !answered, !panel.isShowing else { return }
        if let last = lastShown[key], now.timeIntervalSince(last) < Self.cooldown { return }

        let growing = focus?.state == .growing
        if c.unclear {
            // Ambiguous and the classifier could not tell. Wait a few seconds so a passing tab does not ask.
            guard growing || now.timeIntervalSince(dwellSince) >= Self.dwellSeconds else { return }
            lastShown[key] = now
            let title = growing ? "\(focus?.stage(at: now) ?? "🌱") at risk — work or scroll?" : "Work or scroll?"
            panel.show(title: title, subtitle: label, buttons: [
                .init(title: "Work", prominent: true) { [answer] in answer(key, .productive) },
                .init(title: "Scroll", prominent: false) { [answer] in answer(key, .procrastination) },
            ])
        } else if growing, c.bucket == .procrastination {
            // A clear distraction in the middle of a focus session: the first second is enough.
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
        panel.show(title: text, subtitle: nil, buttons: [], seconds: 8)
    }

    func forgetDay() { lastShown = [:] }
}
