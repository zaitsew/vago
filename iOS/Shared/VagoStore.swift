import FamilyControls
import Foundation
import VagoKit

/// The App Group store: everything the app, the monitor, the shields and the widget share.
///
/// The app and the extensions are separate processes. Each call reads fresh from
/// `UserDefaults`, so no process keeps a stale copy. Writes are small JSON values.
struct VagoStore: @unchecked Sendable {
    static let groupID = "group.com.zaitsew.vago"

    let defaults: UserDefaults

    init() {
        // Without the entitlement (an unsigned simulator build) the suite still opens, in the app's own container.
        defaults = UserDefaults(suiteName: Self.groupID) ?? .standard
    }

    // MARK: JSON

    private func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T?, _ key: String) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }

    // MARK: Flags

    var onboarded: Bool {
        get { defaults.bool(forKey: "onboarded") }
        nonmutating set { defaults.set(newValue, forKey: "onboarded") }
    }

    var liveActivityEnabled: Bool {
        get { defaults.object(forKey: "liveActivityEnabled") as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: "liveActivityEnabled") }
    }

    /// The last Screen Time error an extension hit (a failed `startMonitoring`). Shown in Settings.
    var lastError: String? {
        get { defaults.string(forKey: "lastError") }
        nonmutating set { defaults.set(newValue, forKey: "lastError") }
    }

    // MARK: Selections

    func selection(_ kind: SelectionKind) -> FamilyActivitySelection {
        load(FamilyActivitySelection.self, "selection.\(kind.rawValue)") ?? FamilyActivitySelection()
    }

    func setSelection(_ selection: FamilyActivitySelection, for kind: SelectionKind) {
        save(selection, "selection.\(kind.rawValue)")
    }

    // MARK: Counters, pass, limit, ledger

    /// Today's counters. Counters of an earlier day read as empty.
    func counters(for day: DayKey) -> DayCounters {
        if let stored = load(DayCounters.self, "counters"), stored.day == day { return stored }
        return DayCounters(day: day)
    }

    func setCounters(_ counters: DayCounters) { save(counters, "counters") }

    func pass() -> Pass? { load(Pass.self, "pass") }
    func setPass(_ pass: Pass?) { save(pass, "pass") }

    func limit() -> AdaptiveLimit { load(AdaptiveLimit.self, "limit") ?? AdaptiveLimit() }
    func setLimit(_ limit: AdaptiveLimit) { save(limit, "limit") }

    /// The ledger is kept as one `DeviceDay.encoded()` value per ledger key, the same format as iCloud.
    func ledger() -> Ledger {
        guard let stored = load([String: Data].self, "ledgerDays") else { return Ledger() }
        return Ledger(days: stored.compactMapValues { DeviceDay(encoded: $0) })
    }

    /// How many days of the ledger the App Group keeps. The adaptive limit needs 7.
    static let ledgerDays = 120

    func setLedger(_ ledger: Ledger) {
        let cutoff = DayKey.of(.now).adding(days: -Self.ledgerDays)
        let kept = ledger.days.filter { $0.value.day >= cutoff }
        save(kept.mapValues { $0.encoded() }, "ledgerDays")
    }

    /// Merges one device's day into the stored ledger.
    func merge(_ day: DeviceDay) {
        var ledger = ledger()
        ledger.merge(day)
        setLedger(ledger)
    }

    // MARK: Focus

    func sessions() -> [FocusSession] { load([FocusSession].self, "focusSessions") ?? [] }

    func setSessions(_ sessions: [FocusSession]) { save(Array(sessions.suffix(400)), "focusSessions") }

    /// All sessions, with a session that ran past its end marked as grown (and saved so).
    func settledSessions(now: Date = .now) -> [FocusSession] {
        var sessions = sessions()
        var changed = false
        for index in sessions.indices where sessions[index].state == .growing {
            sessions[index].tick(bucket: .neutral, seconds: 0, now: now)
            changed = changed || sessions[index].state != .growing
        }
        if changed { setSessions(sessions) }
        return sessions
    }

    /// The session that is still growing, if any.
    func activeFocus(now: Date = .now) -> FocusSession? {
        settledSessions(now: now).last { $0.state == .growing }
    }

    /// Replaces the most recent session (the one being changed).
    func updateLastSession(_ change: (inout FocusSession) -> Void) {
        var sessions = sessions()
        guard !sessions.isEmpty else { return }
        change(&sessions[sessions.count - 1])
        setSessions(sessions)
    }

    func focusSeconds(on day: DayKey, now: Date = .now) -> Int {
        settledSessions(now: now)
            .filter { DayKey.of($0.start) == day }
            .reduce(0) { $0 + $1.focusSeconds(at: now) }
    }

    // MARK: Publishing

    /// Writes this iPhone's `DeviceDay` for today into the ledger and returns it.
    @discardableResult
    func publishToday(now: Date = .now) -> DeviceDay {
        let day = DayKey.of(now)
        let counters = counters(for: day)
        let value = DeviceDay(
            day: day,
            device: .iphone,
            procrastination: counters.procrastinationSeconds,
            productive: counters.productiveSeconds,
            focus: focusSeconds(on: day, now: now),
            updatedAt: now
        )
        // Unchanged numbers are not rewritten: the app calls this every few seconds.
        if let stored = ledger().days[Ledger.key(day, .iphone)],
           stored.procrastination == value.procrastination, stored.productive == value.productive,
           stored.focus == value.focus {
            return stored
        }
        merge(value)
        return value
    }

    func snapshot(now: Date = .now) -> Snapshot {
        let day = DayKey.of(now)
        let ledger = ledger()
        let total = ledger.total(for: day)
        return Snapshot(
            day: day,
            procrastination: total.procrastination,
            productive: total.productive,
            focus: total.focus,
            iphone: ledger.days[Ledger.key(day, .iphone)],
            mac: ledger.days[Ledger.key(day, .mac)],
            limitMinutes: limit().current
        )
    }
}

/// Today across devices, as the widget, shield, Live Activity and Today tab show it.
struct Snapshot: Equatable, Sendable {
    var day: DayKey
    var procrastination: Int      // seconds, all devices
    var productive: Int
    var focus: Int
    var iphone: DeviceDay?
    var mac: DeviceDay?
    var limitMinutes: Int

    var mood: Mood { Mood(used: procrastination, limitMinutes: limitMinutes) }
    var readout: String { Readout.short(seconds: procrastination, limitMinutes: limitMinutes) }
    var minutesUsed: Int { procrastination / 60 }

    /// Used share of the limit, 0...1+ (a ring fills to 1 and then stays full).
    var share: Double {
        limitMinutes > 0 ? Double(procrastination) / Double(limitMinutes * 60) : (procrastination > 0 ? 1 : 0)
    }
}

extension DayKey {
    /// 04:00 local on this day.
    var start: Date {
        let parts = id.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return .now }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: DayKey.rolloverHour))
            ?? .now
    }
}
