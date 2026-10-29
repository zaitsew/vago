import AppIntents
import FamilyControls
import Foundation
import VagoKit
import WidgetKit

/// Starting and stopping a focus block. The Focus tab and the App Intents both call this, so the
/// shield, the schedule and the saved session always change together.
enum FocusControl {
    /// Shown to the user by the Shortcuts app and Siri, so the text is a sentence.
    enum Failure: Error, CustomLocalizedStringResourceConvertible {
        case notAuthorized
        case alreadyRunning(minutesLeft: Int)
        case couldNotStart(String)

        var message: String {
            switch self {
            case .notAuthorized: "Open Vago once and allow Screen Time, then try again."
            case .alreadyRunning(let left): "A focus block is already running, \(left) min left."
            case .couldNotStart(let reason): "Could not start focus: \(reason)"
            }
        }

        var localizedStringResource: LocalizedStringResource { "\(message)" }
    }

    @discardableResult
    static func start(minutes: Int, store: VagoStore = VagoStore(), now: Date = .now) throws -> FocusSession {
        guard AuthorizationCenter.shared.authorizationStatus == .approved else { throw Failure.notAuthorized }
        if let running = store.activeFocus(now: now) {
            throw Failure.alreadyRunning(minutesLeft: Int((running.remaining(at: now) / 60).rounded(.up)))
        }
        let session = FocusSession(start: now, minutes: minutes)
        do {
            try VagoMonitoring.startFocus(session)
        } catch {
            throw Failure.couldNotStart(error.localizedDescription)
        }
        store.setSessions(store.sessions() + [session])
        VagoShields.applyFocus(store)
        return session
    }

    /// Gives up the running block: the tree wilts and the shield comes off. Focus time so far still
    /// counts. Returns that time in whole minutes, or nil when no block was running.
    @discardableResult
    static func stop(store: VagoStore = VagoStore(), now: Date = .now) -> Int? {
        guard let running = store.activeFocus(now: now) else { return nil }
        store.updateLastSession { $0.abandon(now: now) }
        VagoShields.liftFocus()
        VagoMonitoring.stop(.focus)
        return Int(running.elapsed(at: now) / 60)
    }

    /// Today's numbers for a spoken answer: publishes this iPhone's day, pulls the Mac's from iCloud
    /// and rolls the limit, as the app does on foreground. Works when the app was not open.
    @MainActor
    static func today(store: VagoStore = VagoStore(), now: Date = .now) -> (summary: DaySummary, limit: Int) {
        let day = DayKey.of(now)
        store.publishToday(now: now)
        var ledger = store.ledger()
        if CloudSync.pull(into: &ledger, today: day) { store.setLedger(ledger) }
        var limit = store.limit()
        limit.roll(to: day, ledger: ledger)
        store.setLimit(limit)
        return (ledger.summary(for: day, limitMinutes: limit.current), limit.current)
    }

    /// Widget and Live Activity follow a changed block without waiting for the next threshold.
    @MainActor
    static func refreshSurfaces(store: VagoStore = VagoStore()) async {
        store.publishToday()
        WidgetCenter.shared.reloadAllTimelines()
        await LiveActivityController.sync(store)
    }
}
