import Foundation
import VagoKit

/// The move reminder: after 90 minutes at the Mac without a break, a floating panel suggests one
/// short exercise. The rules are in VagoKit's `BreakCoach`; this file decides the moment.
extension AppModel {
    /// After a focus session or a call ends, wait this long before the panel.
    static let breakGraceSeconds: TimeInterval = 60
    /// A due reminder waits for an app switch, at most this long.
    static let breakSwitchWaitSeconds: TimeInterval = 3 * 60

    /// When someone last touched the Mac. The tracker keeps counting for 2 minutes without input,
    /// but a break is 5 minutes from the last input, not from the last counted second. On video
    /// pages, where watching needs no input, the counted second is the activity.
    static func lastInput(for obs: ActivitySample, now: Date) -> Date {
        guard Presence.idleThreshold(for: obs) <= Presence.idleSeconds else { return now }
        return now.addingTimeInterval(-min(Presence.secondsSinceInput(), Presence.idleSeconds))
    }

    /// Someone used the Mac during the second ending at `now`, in the place `key`.
    func noteBreakActivity(key: String, lastInput: Date, now: Date) {
        breaks.active(at: lastInput)
        let switched = breakLastKey != nil && breakLastKey != key
        breakLastKey = key
        considerBreak(now: now, switched: switched)
    }

    /// Decides whether the panel shows now. Held during focus and while the microphone is in use,
    /// then for a minute after. Shown at an app switch, or after 3 minutes of waiting for one.
    func considerBreak(now: Date, switched: Bool) {
        // Focus is tracked every second, so a session that ends at the threshold still gets its minute.
        if focus?.state == .growing { breakHeldUntil = now.addingTimeInterval(Self.breakGraceSeconds) }
        guard breaks.wantsPanel(at: now) else { breakDueSince = nil; return }
        if focus?.state == .growing || Microphone.inUse() {
            breakHeldUntil = now.addingTimeInterval(Self.breakGraceSeconds)
            return
        }
        if let held = breakHeldUntil, now < held { return }
        if nudger?.showingNudge == true { return }
        let dueSince = breakDueSince ?? now
        breakDueSince = dueSince
        guard switched || now.timeIntervalSince(dueSince) >= Self.breakSwitchWaitSeconds else { return }
        showBreak(now: now)
    }

    /// Shows the panel now: from the tracker, or from "Move now" in the popover.
    func showBreak(now: Date = Date()) {
        breakDueSince = nil
        breaks.shown(at: now)
        dirty = true
        let minutes = breaks.streakSeconds(at: now) / 60
        nudger?.showBreak(
            move: breaks.move,
            minutes: minutes,
            done: { [weak self] in self?.breakDone() },
            another: { [weak self] in
                guard let self else { return }
                self.breaks.swap()
                self.showBreak()
            },
            later: { [weak self] in self?.breakLater() },
            ignored: { [weak self] in self?.breakIgnored() }
        )
        onChange?()
    }

    func breakDone() {
        breaks.done(at: Date())
        nudger?.closeBreak()
        nudger?.toast(String(localized: "🚶 Done. Next reminder after \(breaks.streakMinutes) min at the Mac", comment: "Toast after a move was done. The argument is the minutes at the Mac before the next reminder."))
        changedBreaks()
    }

    func breakLater() {
        breaks.later(at: Date())
        changedBreaks()
    }

    func breakIgnored() {
        breaks.ignore(at: Date())
        changedBreaks()
    }

    func breakNotToday() {
        breaks.pauseToday(at: Date())
        nudger?.closeBreak()
        changedBreaks()
    }

    func setBreaksEnabled(_ on: Bool) {
        breaks.enabled = on
        if !on { nudger?.closeBreak() }
        changedBreaks()
    }

    func setBreakMinutes(_ minutes: Int) {
        breaks.streakMinutes = minutes
        changedBreaks()
    }

    var movesToday: Int { breaks.moves(on: today.day) }

    private func changedBreaks() {
        dirty = true
        flush(now: Date())
        onChange?()
    }
}
