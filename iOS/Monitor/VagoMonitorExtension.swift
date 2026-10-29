import DeviceActivity
import Foundation
import ManagedSettings
import VagoKit
import WidgetKit

/// Counts. The system calls this extension when a usage threshold is reached; nothing else
/// tells the app how long an app was used (docs/ARCHITECTURE.md, iPhone app).
///
/// Callbacks are not guaranteed in time or in order, so every handler is idempotent:
/// counters only move up, a pass ends once, a shield is re-applied without harm.
final class VagoMonitorExtension: DeviceActivityMonitor {
    private let store = VagoStore()

    // MARK: Schedules

    override func intervalDidStart(for activity: DeviceActivityName) {
        guard activity == .daily else { return }
        // The system also calls this when the schedule is (re)registered in the middle of a day,
        // so nothing here may wipe today's numbers. Counters are keyed by day: a new day reads
        // as empty on its own. Only a pass left over from before today's 04:00 is dropped.
        let now = Date()
        let dayStart = DayKey.of(now).start
        if let pass = store.pass(), pass.start < dayStart {
            store.setPass(nil)
            DeviceActivityCenter().stopMonitoring([.pass])
        }
        // The gate is back unless a pass is running.
        if store.onboarded, store.pass()?.isOpen != true { VagoShields.applyAmbiguous(store) }
        publish(now: now)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        let now = Date()
        switch activity {
        case .pass:
            // The 60-minute window closed. If the pass was not used up, close it now.
            endPass(now: now)
        case .focus:
            finishFocus(now: now)
        default:
            break
        }
    }

    // MARK: Thresholds

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        let now = Date()
        if activity == .pass {
            guard event == .passLimit else { return }
            endPass(now: now)
            publish(now: now)
            return
        }
        guard activity == .daily, let usage = UsageEvent(name: event) else { return }

        let day = DayKey.of(now)
        var counters = store.counters(for: day)
        let added = counters.apply(usage, pass: store.pass(), now: now)
        store.setCounters(counters)

        // A focus session that sees distraction wilts after a minute of it. The focus shield
        // makes this rare (a web view, a gap in the selection), but the tree must tell the truth.
        if added > 0, store.activeFocus(now: now) != nil {
            store.updateLastSession { $0.tick(bucket: .procrastination, seconds: added * 60, now: now) }
            if store.activeFocus(now: now) == nil { finishFocus(now: now) }
        }
        publish(now: now)
    }

    // MARK: Pieces

    /// Closes the open pass and puts the shield back. Safe to call twice.
    private func endPass(now: Date) {
        if var pass = store.pass(), pass.isOpen {
            pass.endedAt = now
            store.setPass(pass)
        }
        VagoShields.applyAmbiguous(store)
        DeviceActivityCenter().stopMonitoring([.pass])
    }

    /// The focus interval ended or the tree wilted: lift the shield. Settled sessions are marked by `VagoStore`.
    private func finishFocus(now: Date) {
        _ = store.settledSessions(now: now)
        VagoShields.liftFocus()
        DeviceActivityCenter().stopMonitoring([.focus])
        publish(now: now)
    }

    /// Writes today's `DeviceDay`, reloads the widget and nudges the Live Activity.
    private func publish(now: Date) {
        store.publishToday(now: now)
        WidgetCenter.shared.reloadAllTimelines()
        updateLiveActivity(now: now)
    }

    /// ActivityKit's `update` compiles in an extension and the system may run it. If it does not
    /// (the process is suspended first, or the call is refused), the app refreshes the Live
    /// Activity when it next runs. Waits at most two seconds so the callback is not held open.
    private func updateLiveActivity(now: Date) {
        let done = DispatchSemaphore(value: 0)
        let store = store
        Task.detached {
            await LiveActivityUpdater.updateAll(store: store, now: now)
            done.signal()
        }
        _ = done.wait(timeout: .now() + 2)
    }
}
