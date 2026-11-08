import AppKit
import Foundation
import Observation
import ServiceManagement
import VagoKit

/// One place Vago made a call on today, grouped by site or app, shown in the Day window's
/// "Vago's calls" with a one-tap correction.
struct CallItem: Identifiable, Equatable {
    var id: String                    // SiteKey
    var sample: ActivitySample
    var label: String
    var seconds: Int
    var bucket: Bucket
    var reason: String                // the AI's reason, or why there was none
    var unsure: Bool
    var corrected: Bool
    var sessionIDs: [UUID]
}

/// What is in front right now, for the popover's "Now" line.
struct NowPlace: Equatable {
    var key: String                   // SiteKey
    var label: String
    var sample: ActivitySample
    var bucket: Bucket
    var reason: String
    var source: Classification.Source
    var unclear: Bool
}

/// The two windows the popover opens.
enum AppWindow: Sendable { case day, settings }

/// Reasons the app writes into a session itself, to tell them from the AI's.
enum CallReason {
    static let answer = "your answer today"
    static let corrected = "you corrected this"

    /// True for sessions a rule or an answer settled: not one of Vago's calls.
    static func isSettled(_ reason: String) -> Bool {
        reason.hasPrefix("rule: ") || reason == answer
    }
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
    var breaks: BreakCoach
    var judgeAudit: JudgeAudit
    var verdictMemory: VerdictMemory

    // MARK: Live
    var clock = Date()
    var pause: PauseReason?
    var now: NowPlace?
    /// True while `JudgeAudit` holds the judge's "work" verdicts on ambiguous places.
    var judgeHeld = false
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
    @ObservationIgnored var breakLastKey: String?
    @ObservationIgnored var breakDueSince: Date?
    @ObservationIgnored var breakHeldUntil: Date?
    /// The place in front: since when, and its last call. Feeds the judge's context.
    @ObservationIgnored var place: (key: String, label: String, bucket: Bucket, since: Date, lastAt: Date)?
    /// The place before it, for "Just before: Xcode (work)".
    @ObservationIgnored var previousPlace: (label: String, bucket: Bucket, at: Date)?
    /// Called after every change the menu bar shows.
    @ObservationIgnored var onChange: (@MainActor () -> Void)?
    /// Opens the Day or the Settings window (wired by the status item).
    @ObservationIgnored var openWindow: (@MainActor (AppWindow) -> Void)?

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
        breaks = state.breaks
        judgeAudit = state.judgeAudit
        verdictMemory = state.verdictMemory
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
        applyJudgeTrust()
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
            let remoteTotal = day.procrastination + day.productive + day.neutral + day.focus
            if remoteTotal > today.procrastination + today.productive + today.neutral + today.focus { today = day }
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
        s.breaks = breaks
        s.judgeAudit = judgeAudit
        s.verdictMemory = verdictMemory
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
            "moves_today": breaks.moves(on: today.day),
            "moves_7d": breaks.moves(since: weekAgo),
            "productive_percent_today": share.percent ?? -1,
            "auto_rules": rules.rules.filter { $0.source == .auto }.count,
        ]
    }

    // MARK: Derived (read by the menu bar and the popover)

    var totals: (procrastination: Int, productive: Int, focus: Int) { ledger.total(for: today.day) }

    var mood: Mood { Mood(used: totals.procrastination, limitMinutes: limit.current) }

    /// The main metric across devices: 100% minus the share of waste.
    var share: ProductiveShare { ledger.share(for: today.day) }

    /// The menu bar text and its colour: the mood for the limit, then the productive share
    /// ("😄 92%", "😄 —" before 15 active minutes). During focus: the tree stage and the
    /// minutes left. A 🚶 follows while a move is due.
    var menuBar: (text: String, tint: Tint?) {
        if let focus, focus.state == .growing {
            let minutes = Int((focus.remaining(at: clock) / 60).rounded(.up))
            return ("\(focus.stage(at: clock)) \(minutes)m", nil)
        }
        let text = "\(mood.emoji) \(share.text)"
        return (breaks.wantsMark(at: clock) ? "\(text) 🚶" : text, mood.tint)
    }

    /// Today's Mac seconds in `bucket` by site or app, largest first.
    func top(_ bucket: Bucket, count: Int = 5) -> [(label: String, seconds: Int)] {
        var sums: [String: Int] = [:]
        for s in sessions where s.guess == bucket {
            sums[SiteKey.label(s.sample.sample), default: 0] += s.seconds
        }
        return sums.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
            .prefix(count).map { ($0.key, $0.value) }
    }

    /// Vago's calls today: places the AI judged or was unsure about, grouped by site or app,
    /// largest first. Rule and answer sessions are not calls; corrected ones stay, marked.
    var calls: [CallItem] {
        let pending = Set(reviewPending)
        var groups: [String: CallItem] = [:]
        var best: [String: Int] = [:]
        for s in sessions where !CallReason.isSettled(s.reason) {
            let o = s.sample.sample
            let key = SiteKey.of(o)
            var item = groups[key] ?? CallItem(id: key, sample: o, label: SiteKey.label(o), seconds: 0, bucket: s.guess,
                                               reason: s.reason, unsure: false, corrected: false, sessionIDs: [])
            item.seconds += s.seconds
            item.sessionIDs.append(s.id)
            if pending.contains(s.id) { item.unsure = true }
            if s.reason == CallReason.corrected { item.corrected = true }
            if s.seconds > best[key, default: -1] {
                best[key] = s.seconds
                item.sample = o
                item.bucket = s.guess
                if s.reason != CallReason.corrected { item.reason = s.reason }
            }
            groups[key] = item
        }
        return groups.values.sorted { $0.seconds > $1.seconds }.prefix(8).map { item in
            var item = item
            if item.corrected { item.unsure = false }
            return item
        }
    }

    /// Custom rules Vago learned: from corrections (`.review`) and from sure verdicts (`.auto`).
    var learnedRuleCount: Int { rules.rules.filter { $0.source == .review || $0.source == .auto }.count }

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

    /// Removes every learned rule (corrections and `.auto` rules) and starts verdict memory over.
    /// The owner's own rules and the built-ins stay.
    func forgetLearnedRules() {
        rules = RuleBook(custom: rules.customRules.filter { $0.source == .user })
        verdictMemory = VerdictMemory()
        let book = rules, classifier = self.classifier
        Task { await classifier.update(rules: book) }
        dirty = true
        flush(now: Date())
        onChange?()
    }

    /// Hands today's `JudgeAudit` answer to the classifier: at launch, at day start, after a
    /// correction, and when the classifier is rebuilt.
    func applyJudgeTrust() {
        let trusted = judgeAudit.trusted(on: today.day)
        if judgeHeld == trusted { judgeHeld = !trusted }
        let classifier = self.classifier
        Task { await classifier.setJudgeTrusted(trusted) }
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
        applyJudgeTrust()
    }

    func markOnboarded() {
        onboarded = true
        dirty = true
    }
}
