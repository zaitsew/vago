import AppKit
import Foundation
import Observation
import ServiceManagement
import VagoKit

/// A group of unclear sessions on one site or app, shown in the review queue.
struct ReviewItem: Identifiable, Equatable {
    var id: String                    // SiteKey
    var sample: ActivitySample
    var label: String
    var seconds: Int
    var reason: String                // what the AI guessed, or why there was no guess
    var sessionIDs: [UUID]
}

enum PauseReason: Sendable, Equatable { case locked, idle }

/// The app's state. One instance, on the main actor. Accounting lives in AppModel+Accounting.swift;
/// stored properties are here because an extension cannot add them.
@MainActor
@Observable
final class AppModel {
    // MARK: Persisted
    var goals: String
    var limit: AdaptiveLimit
    var ledger: Ledger
    var today: DeviceDay
    var sessions: [Session]
    var reviewPending: [UUID]
    var overrides: [String: Bucket]
    var focus: FocusSession?
    var focusLog: [FocusSession]
    var rules: RuleBook
    var onboarded: Bool

    // MARK: Live
    var clock = Date()
    var pause: PauseReason?
    var currentLabel: String?
    var accessibilityGranted = Permissions.accessibilityGranted
    var automation: [String: AutomationState] = [:]
    var judgeAvailable = false
    var icloudEnabled = false
    var launchAtLogin = false
    var lastToast: String?

    // MARK: Plumbing (not observed)
    @ObservationIgnored let store: StateStore
    @ObservationIgnored var classifier: Classifier
    @ObservationIgnored var currentSession: (index: Int, key: String, lastAt: Date)?
    @ObservationIgnored var dirty = false
    @ObservationIgnored var lastFlush = Date.distantPast
    @ObservationIgnored var lastUsageWrite = Date.distantPast
    @ObservationIgnored var nudger: Nudger?
    @ObservationIgnored var sync: CloudSync?
    /// Called after every change the menu bar shows.
    @ObservationIgnored var onChange: (@MainActor () -> Void)?

    init(store: StateStore = StateStore(), now: Date = Date()) {
        self.store = store
        let state = store.load()
        let day = DayKey.of(now)
        goals = state.goals
        limit = state.limit
        ledger = state.ledger
        sessions = state.sessions
        reviewPending = state.reviewPending
        overrides = state.overridesDay == day ? state.overrides : [:]
        focus = state.focus
        focusLog = state.focusLog
        onboarded = state.onboarded
        let book = RuleBook(custom: state.customRules)
        rules = book
        today = state.today ?? DeviceDay(day: day, device: .mac, updatedAt: now)
        let judge = FoundationModelsJudge.makeIfAvailable()
        judgeAvailable = judge != nil
        classifier = Classifier(rules: book, judge: judge, goals: state.goals)
        launchAtLogin = SMAppService.mainApp.status == .enabled

        if today.day != day {
            // The Mac was off over the 04:00 change: the old day is already in the ledger.
            startNewDay(day, now: now)
        } else {
            limit.roll(to: day, ledger: ledger)
        }
        ledger.merge(today)
    }

    // MARK: Lifecycle

    /// Wires the key-value store. Called once, after init.
    func attachSync() {
        let sync = CloudSync { [weak self] day in self?.adopt(remote: day) }
        self.sync = sync
        icloudEnabled = sync.isEnabled
        sync.start()
        sync.write(today)
    }

    /// A day another device (or an earlier run of this Mac) wrote to iCloud.
    func adopt(remote day: DeviceDay) {
        if day.device == .mac, day.day == today.day {
            // The same Mac's own value, e.g. after state.json was lost: keep the larger one.
            let remoteTotal = day.procrastination + day.productive + day.focus
            if remoteTotal > today.procrastination + today.productive + today.focus { today = day }
        }
        ledger.merge(day)
        dirty = true
        onChange?()
    }

    /// Persists state if it changed; at most every 5 seconds unless `force`.
    func flush(force: Bool = false, now: Date = Date()) {
        if force || (dirty && now.timeIntervalSince(lastFlush) >= 5) {
            store.save(snapshot())
            lastFlush = now
            dirty = false
        }
        if force || now.timeIntervalSince(lastUsageWrite) >= 30 {
            store.saveUsage(usageCounters(now: now))
            sync?.write(today, force: force)
            lastUsageWrite = now
        }
    }

    func snapshot() -> PersistedState {
        var s = PersistedState()
        s.onboarded = onboarded
        s.goals = goals
        s.customRules = rules.customRules
        s.limit = limit
        s.ledger = ledger
        s.today = today
        s.sessions = sessions
        s.reviewPending = reviewPending
        s.overrides = overrides
        s.overridesDay = today.day
        s.focus = focus
        s.focusLog = focusLog
        return s
    }

    /// The counters in `usage.json`, printed by `./check.sh usage`.
    func usageCounters(now: Date) -> [String: Int] {
        let history = ledger.history(endingBefore: today.day, count: 7)
        let average = history.isEmpty ? 0 : Int((Double(history.reduce(0, +)) / Double(history.count)).rounded())
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        let recent = (focusLog + (focus.map { [$0] } ?? [])).filter { $0.start >= weekAgo }
        return [
            "days_tracked": ledger.trackedDays().count,
            "procrastination_min_today": totals.procrastination / 60,
            "limit_min": limit.current,
            "avg_procrastination_min_7d": average,
            "focus_sessions_7d": recent.count,
            "judge_available": judgeAvailable ? 1 : 0,
        ]
    }

    // MARK: Derived (read by the menu bar and the popover)

    var totals: (procrastination: Int, productive: Int, focus: Int) { ledger.total(for: today.day) }

    var mood: Mood { Mood(used: totals.procrastination, limitMinutes: limit.current) }

    var readout: String { Readout.short(seconds: totals.procrastination, limitMinutes: limit.current) }

    /// The menu bar text and its colour. During focus: the tree stage and the minutes left.
    var menuBar: (text: String, tint: Tint?) {
        if let focus, focus.state == .growing {
            let minutes = Int((focus.remaining(at: clock) / 60).rounded(.up))
            return ("\(focus.stage(at: clock)) \(minutes)m", nil)
        }
        return (readout, mood.tint)
    }

    func seconds(of device: Device) -> (procrastination: Int, productive: Int, focus: Int)? {
        ledger.days[Ledger.key(today.day, device)].map { ($0.procrastination, $0.productive, $0.focus) }
    }

    /// Today's procrastination by site or app, largest first.
    var topDistractions: [(label: String, seconds: Int)] {
        var sums: [String: Int] = [:]
        for s in sessions where s.guess == .procrastination {
            sums[SiteKey.label(s.sample.sample), default: 0] += s.seconds
        }
        return sums.sorted { $0.value > $1.value }.prefix(3).map { ($0.key, $0.value) }
    }

    /// The three largest groups of unclear sessions.
    var reviewItems: [ReviewItem] {
        let pending = Set(reviewPending)
        var groups: [String: ReviewItem] = [:]
        var best: [String: Int] = [:]
        for s in sessions where pending.contains(s.id) {
            let o = s.sample.sample
            let key = SiteKey.of(o)
            var item = groups[key] ?? ReviewItem(id: key, sample: o, label: SiteKey.label(o), seconds: 0, reason: s.reason, sessionIDs: [])
            item.seconds += s.seconds
            item.sessionIDs.append(s.id)
            if s.seconds > best[key, default: -1] { best[key] = s.seconds; item.sample = o; item.reason = s.reason }
            groups[key] = item
        }
        return groups.values.sorted { $0.seconds > $1.seconds }.prefix(3).map { $0 }
    }

    var focusSecondsToday: Int {
        (focusLog + (focus.map { [$0] } ?? []))
            .filter { DayKey.of($0.start) == today.day }
            .reduce(0) { $0 + $1.focusSeconds(at: clock) }
    }

    // MARK: Settings

    func setGoals(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        goals = clean.isEmpty ? PersistedState.defaultGoals : clean
        dirty = true
        let goals = self.goals, classifier = self.classifier
        Task { await classifier.update(goals: goals) }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Vago: launch at login failed: %@", error.localizedDescription)
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func noteAutomation(_ bundleID: String, _ state: AutomationState) {
        if automation[bundleID] != state { automation[bundleID] = state }
    }

    /// Rebuilds the classifier when the on-device model becomes (un)available, e.g. after its download.
    func refreshJudgeIfNeeded() {
        let available = FoundationModelsJudge.isAvailable
        guard available != judgeAvailable else { return }
        judgeAvailable = available
        classifier = Classifier(rules: rules, judge: FoundationModelsJudge.makeIfAvailable(), goals: goals)
    }

    func markOnboarded() {
        onboarded = true
        dirty = true
    }
}
