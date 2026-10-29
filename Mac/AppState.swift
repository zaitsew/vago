import Foundation
import VagoKit

/// Everything the Mac app keeps between launches: `~/Library/Application Support/Vago/state.json`.
/// Only `RuleBook.customRules` is stored, never the built-ins, so a new VagoKit brings its own.
struct PersistedState: Codable, Sendable {
    static let defaultGoals = "Build my startups, find a high-paying job, grow my network; scrolling feeds is not work"

    var onboarded = false
    var goals = PersistedState.defaultGoals
    var customRules: [Rule] = []
    var limit = AdaptiveLimit()
    /// Every device's finished days plus today. The adaptive limit and the 7-day average read it.
    var ledger = Ledger()
    /// This Mac's totals for the current day (also merged into `ledger`).
    var today: DeviceDay?
    /// Today's non-neutral stretches of use, newest last.
    var sessions: [Session] = []
    /// Ids in `sessions` that the classifier guessed at and the owner has not answered yet.
    var reviewPending: [UUID] = []
    /// Day-scoped answers from the intent nudge, keyed by site or bundle id.
    var overrides: [String: Bucket] = [:]
    var overridesDay: DayKey?
    var focus: FocusSession?
    /// Finished focus sessions of the last 14 days.
    var focusLog: [FocusSession] = []

    init() {}

    // A missing key falls back to its default, so adding a field never loses the file.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? false
        goals = try c.decodeIfPresent(String.self, forKey: .goals) ?? Self.defaultGoals
        customRules = try c.decodeIfPresent([Rule].self, forKey: .customRules) ?? []
        limit = try c.decodeIfPresent(AdaptiveLimit.self, forKey: .limit) ?? AdaptiveLimit()
        ledger = try c.decodeIfPresent(Ledger.self, forKey: .ledger) ?? Ledger()
        today = try c.decodeIfPresent(DeviceDay.self, forKey: .today)
        sessions = try c.decodeIfPresent([Session].self, forKey: .sessions) ?? []
        reviewPending = try c.decodeIfPresent([UUID].self, forKey: .reviewPending) ?? []
        overrides = try c.decodeIfPresent([String: Bucket].self, forKey: .overrides) ?? [:]
        overridesDay = try c.decodeIfPresent(DayKey.self, forKey: .overridesDay)
        focus = try c.decodeIfPresent(FocusSession.self, forKey: .focus)
        focusLog = try c.decodeIfPresent([FocusSession].self, forKey: .focusLog) ?? []
    }

    private enum Keys: String, CodingKey {
        case onboarded, goals, customRules, limit, ledger, today, sessions, reviewPending
        case overrides, overridesDay, focus, focusLog
    }
}

/// The JSON used on disk and in the key-value store. The iPhone app reads the same values.
enum Codec {
    static func encode<T: Encodable>(_ value: T, pretty: Bool = false) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try? encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        if let value = try? JSONDecoder().decode(type, from: data) { return value }
        let iso = JSONDecoder()
        iso.dateDecodingStrategy = .iso8601          // tolerate the other common date format
        return try? iso.decode(type, from: data)
    }
}

/// Reads and writes the two files under Application Support. Failures are logged, never thrown:
/// tracking must go on when the disk is full.
struct StateStore: Sendable {
    let directory: URL
    var stateURL: URL { directory.appendingPathComponent("state.json") }
    var usageURL: URL { directory.appendingPathComponent("usage.json") }

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vago", isDirectory: true)
    }

    func load() -> PersistedState {
        guard let data = try? Data(contentsOf: stateURL) else { return PersistedState() }
        if let state = Codec.decode(PersistedState.self, from: data) { return state }
        // Unreadable file: keep it for inspection and start clean rather than overwrite it silently.
        let backup = directory.appendingPathComponent("state.corrupt-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.copyItem(at: stateURL, to: backup)
        NSLog("Vago: state.json unreadable, copied to %@", backup.lastPathComponent)
        return PersistedState()
    }

    func save(_ state: PersistedState) {
        write(Codec.encode(state, pretty: true), to: stateURL)
    }

    /// `usage.json`: flat counters that `./check.sh usage` prints, one `key=value` line each.
    func saveUsage(_ counters: [String: Int]) {
        guard let data = try? JSONSerialization.data(withJSONObject: counters, options: [.sortedKeys, .prettyPrinted]) else { return }
        write(data, to: usageURL)
    }

    private func write(_ data: Data?, to url: URL) {
        guard let data else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("Vago: could not write %@: %@", url.lastPathComponent, error.localizedDescription)
        }
    }
}
