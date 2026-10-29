import Foundation

/// What a reader needs from the Mac app's `state.json` (`~/Library/Application Support/Vago/`).
/// Only these keys are decoded, so a field added to the Mac app never breaks a reader, and a
/// reader never sees rules, goals or sessions: no app names, titles or URLs.
public struct StateFile: Decodable, Sendable {
    public var ledger: Ledger
    public var limit: AdaptiveLimit
    public var focus: FocusSession?

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vago", isDirectory: true)
            .appendingPathComponent("state.json")
    }

    private enum Keys: String, CodingKey { case ledger, limit, focus }

    public init(ledger: Ledger = Ledger(), limit: AdaptiveLimit = AdaptiveLimit(), focus: FocusSession? = nil) {
        self.ledger = ledger
        self.limit = limit
        self.focus = focus
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        ledger = try c.decodeIfPresent(Ledger.self, forKey: .ledger) ?? Ledger()
        limit = try c.decodeIfPresent(AdaptiveLimit.self, forKey: .limit) ?? AdaptiveLimit()
        focus = try c.decodeIfPresent(FocusSession.self, forKey: .focus)
    }

    public enum LoadError: Error, Equatable, CustomStringConvertible {
        case missing(String)
        case unreadable(String)

        public var description: String {
            switch self {
            case .missing(let path): "No Vago data at \(path). Open the Vago Mac app once."
            case .unreadable(let path): "Could not read \(path): the file is not Vago state."
            }
        }
    }

    /// Reads the file. The Mac app writes dates as numbers; ISO 8601 is accepted too.
    public static func load(from url: URL = defaultURL) throws -> StateFile {
        guard let data = try? Data(contentsOf: url) else { throw LoadError.missing(url.path) }
        if let state = try? JSONDecoder().decode(StateFile.self, from: data) { return state }
        let iso = JSONDecoder()
        iso.dateDecodingStrategy = .iso8601
        if let state = try? iso.decode(StateFile.self, from: data) { return state }
        throw LoadError.unreadable(url.path)
    }

    /// The numbers the tools return, as of `now`.
    public func report(now: Date = .now, calendar: Calendar = .current) -> VagoReport {
        let today = DayKey.of(now, calendar: calendar)
        let todayDevices = Device.allCases.filter { ledger.days[Ledger.key(today, $0)] != nil }
        let updated = todayDevices.compactMap { ledger.days[Ledger.key(today, $0)]?.updatedAt }.max()
        let running = focus.flatMap { $0.state == .growing && $0.end > now ? $0 : nil }
        return VagoReport(
            now: now,
            today: ledger.summary(for: today, limitMinutes: limit.current),
            week: ledger.weekSummary(endingOn: today, limitMinutes: limit.current),
            devicesToday: todayDevices.map(\.rawValue),
            updatedAt: updated,
            baselineMinutes: limit.baseline,
            macFocus: running.map {
                MacFocus(minutes: $0.minutes, minutesLeft: Int(($0.remaining(at: now) / 60).rounded(.up)))
            }
        )
    }
}

/// A focus block running on the Mac. The iPhone's block is not visible to the Mac's file.
public struct MacFocus: Codable, Sendable, Equatable {
    public var minutes: Int
    public var minutesLeft: Int
}

/// Everything the read-only tools can say, from one read of the file.
public struct VagoReport: Sendable, Equatable {
    public var now: Date
    public var today: DaySummary
    public var week: WeekSummary
    /// Which devices have a value for today ("mac", "iphone"). The iPhone appears after iCloud sync.
    public var devicesToday: [String]
    /// The newest device value for today; nil when nothing is tracked today.
    public var updatedAt: Date?
    public var baselineMinutes: Int?
    public var macFocus: MacFocus?
}
