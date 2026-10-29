import DeviceActivity
import FamilyControls
import Foundation
import Observation
import VagoKit
import WidgetKit

/// The app's state. Counting happens in the monitor extension; this model reads what the
/// extension wrote to the App Group, merges the Mac's days from iCloud, and drives the UI.
@MainActor
@Observable
final class AppModel {
    let store = VagoStore()

    var snapshot: Snapshot
    var limit: AdaptiveLimit
    var sessions: [FocusSession] = []
    var counters: DayCounters
    var onboarded: Bool
    var authorized: Bool
    var iCloudSignedIn = CloudSync.isSignedIn
    var lastCloudChange: Date?
    var errorMessage: String?
    var selections: [SelectionKind: FamilyActivitySelection] = [:]

    init() {
        let store = VagoStore()
        snapshot = store.snapshot()
        limit = store.limit()
        counters = store.counters(for: DayKey.of(.now))
        onboarded = store.onboarded
        authorized = AuthorizationCenter.shared.authorizationStatus == .approved
        for kind in SelectionKind.allCases { selections[kind] = store.selection(kind) }
    }

    var activeFocus: FocusSession? { sessions.last { $0.state == .growing } }

    // MARK: Refresh

    /// Called on foreground, on an iCloud change and every few seconds while visible.
    func refresh(syncCloud: Bool = true) async {
        let now = Date()
        let today = DayKey.of(now)
        authorized = AuthorizationCenter.shared.authorizationStatus == .approved
        iCloudSignedIn = CloudSync.isSignedIn

        // Today's iPhone numbers (also credits focus time), then the Mac's from iCloud.
        store.publishToday(now: now)
        var ledger = store.ledger()
        var macChanged = false
        if syncCloud, CloudSync.pull(into: &ledger, today: today) {
            lastCloudChange = now
            macChanged = true
        }
        // Roll the limit once per day, on the merged ledger, and share it with the shield and widget.
        var limit = store.limit()
        limit.roll(to: today, ledger: ledger)
        store.setLimit(limit)
        // Write the ledger back only when iCloud added something; the monitor owns the iPhone numbers.
        if macChanged { store.setLedger(ledger) }
        if syncCloud { CloudSync.push(ledger, today: today) }

        let previous = snapshot
        self.limit = limit
        sessions = store.settledSessions(now: now)
        counters = store.counters(for: today)
        snapshot = store.snapshot(now: now)
        errorMessage = store.lastError

        // A focus session that ended while the app was away: lift the shield now.
        if activeFocus == nil { VagoShields.liftFocus() }
        // Reloads are budgeted by the system; ask only when the numbers moved.
        if snapshot != previous { WidgetCenter.shared.reloadAllTimelines() }
        await LiveActivityController.sync(store)
    }

    // MARK: Onboarding and selections

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        } catch {
            errorMessage = "Screen Time access was not granted: \(error.localizedDescription)"
        }
        authorized = AuthorizationCenter.shared.authorizationStatus == .approved
    }

    func binding(for kind: SelectionKind) -> FamilyActivitySelection {
        selections[kind] ?? FamilyActivitySelection()
    }

    func setSelection(_ selection: FamilyActivitySelection, for kind: SelectionKind) {
        selections[kind] = selection
        store.setSelection(selection, for: kind)
    }

    func count(_ kind: SelectionKind) -> Int {
        let s = binding(for: kind)
        return s.applicationTokens.count + s.categoryTokens.count + s.webDomainTokens.count
    }

    /// A broad list holds a whole category beside a narrower list: apps in both are counted twice.
    var categoryOverlap: Bool {
        func empty(_ kind: SelectionKind) -> Bool { count(kind) == 0 }
        let p = binding(for: .procrastination), a = binding(for: .ambiguous)
        return (!p.categoryTokens.isEmpty && (!empty(.ambiguous) || !empty(.productive)))
            || (!a.categoryTokens.isEmpty && !empty(.productive))
    }

    func finishOnboarding() async {
        store.onboarded = true
        onboarded = true
        restartMonitoring()
        await refresh()
    }

    /// Re-registers the daily schedule (after a selection changed) and puts the gate back up.
    func restartMonitoring() {
        store.normalizeSelections()
        for kind in SelectionKind.allCases { selections[kind] = store.selection(kind) }
        store.lastError = nil
        do {
            try VagoMonitoring.startDaily(store)
            store.setPass(nil)
            VagoMonitoring.stop(.pass)
            VagoShields.applyAmbiguous(store)
            errorMessage = nil
        } catch {
            let message = "Could not start counting: \(error.localizedDescription)"
            store.lastError = message
            errorMessage = message
        }
    }

    // MARK: Focus

    func startFocus(minutes: Int) {
        do {
            try FocusControl.start(minutes: minutes, store: store)
        } catch FocusControl.Failure.alreadyRunning {
            return
        } catch let failure as FocusControl.Failure {
            errorMessage = failure.message
            return
        } catch {
            errorMessage = "Could not start focus: \(error.localizedDescription)"
            return
        }
        Task { await refresh(syncCloud: false) }
    }

    /// Gives up: the tree wilts and the shield comes off. Focus time so far still counts.
    func abandonFocus() {
        FocusControl.stop(store: store)
        Task { await refresh() }
    }

    // MARK: Garden

    /// Sessions that started this calendar week, oldest first.
    var thisWeek: [FocusSession] {
        let calendar = Calendar.current
        guard let week = calendar.dateInterval(of: .weekOfYear, for: .now) else { return [] }
        return sessions.filter { week.contains($0.start) && $0.state != .growing }
    }

    // MARK: Settings

    func setLiveActivityEnabled(_ enabled: Bool) {
        store.liveActivityEnabled = enabled
        Task { await LiveActivityController.sync(store) }
    }

    var calibrationDay: Int? {
        guard limit.baseline == nil else { return nil }
        let tracked = store.ledger().trackedDays().filter { $0 < DayKey.of(.now) }.count
        return min(tracked + 1, AdaptiveLimit.calibrationDays)
    }
}
