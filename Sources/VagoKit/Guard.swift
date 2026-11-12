import Foundation

/// The owner's work hours: a daily block on chosen weekdays.
public struct WorkHours: Codable, Sendable, Equatable {
    public var start: Int            // minutes after midnight, default 9*60
    public var end: Int              // default 18*60; end <= start means the block crosses midnight
    public var weekdays: Set<Int>    // Calendar weekday numbers, 1 = Sunday … 7 = Saturday; default 2...6

    public init(start: Int = 540, end: Int = 1080, weekdays: Set<Int> = [2, 3, 4, 5, 6]) {
        self.start = start
        self.end = end
        self.weekdays = weekdays
    }

    /// True when `date` falls inside a work block. A block that crosses midnight belongs to the
    /// weekday it started on.
    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let minute = Self.minuteOfDay(date, calendar)
        let weekday = calendar.component(.weekday, from: date)
        if start < end {
            return weekdays.contains(weekday) && minute >= start && minute < end
        }
        if minute >= start { return weekdays.contains(weekday) }
        if minute < end { return weekdays.contains(weekday == 1 ? 7 : weekday - 1) }
        return false
    }

    /// When the work block that contains `date` ends; nil when `date` is outside work hours.
    public func blockEnd(containing date: Date, calendar: Calendar = .current) -> Date? {
        guard contains(date, calendar: calendar) else { return nil }
        let midnight = calendar.startOfDay(for: date)
        let crossesToTomorrow = end <= start && Self.minuteOfDay(date, calendar) >= start
        let day = crossesToTomorrow ? (calendar.date(byAdding: .day, value: 1, to: midnight) ?? midnight) : midnight
        // Set the wall-clock time rather than adding minutes, so a DST change on that day keeps 18:00 at 18:00.
        return calendar.date(bySettingHour: end / 60, minute: end % 60, second: 0, of: day)
    }

    private static func minuteOfDay(_ date: Date, _ calendar: Calendar) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }
}

/// A place the owner named as a waste place.
public struct GuardedPlace: Codable, Sendable, Equatable, Identifiable {
    public enum Mode: String, Codable, Sendable, CaseIterable { case pause, block }

    public var id: UUID
    public var name: String          // "Instagram"
    public var host: String?         // web, "instagram.com" also matches "www."/subdomains, like Rule.host
    public var bundleID: String?     // app, exact, case-insensitive
    public var mode: Mode

    public init(id: UUID = UUID(), name: String, host: String? = nil, bundleID: String? = nil, mode: Mode = .pause) {
        self.id = id
        self.name = name
        self.host = host
        self.bundleID = bundleID
        self.mode = mode
    }

    /// True when the host matches the sample's host, or the bundle id matches. A place with neither matches nothing.
    public func matches(_ o: ActivitySample) -> Bool {
        if let wanted = Self.cleanHost(host), let oHost = o.host,
           oHost == wanted || oHost.hasSuffix("." + wanted) { return true }
        if let bundle = Self.clean(bundleID), o.bundleID.caseInsensitiveCompare(bundle) == .orderedSame { return true }
        return false
    }

    /// True when both places name the same host or the same bundle id.
    func overlaps(_ other: GuardedPlace) -> Bool {
        if let a = Self.cleanHost(host), let b = Self.cleanHost(other.host), a == b { return true }
        if let a = Self.clean(bundleID), let b = Self.clean(other.bundleID),
           a.caseInsensitiveCompare(b) == .orderedSame { return true }
        return false
    }

    private static func clean(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        return s
    }

    private static func cleanHost(_ s: String?) -> String? {
        guard var host = clean(s)?.lowercased() else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host.isEmpty ? nil : host
    }
}

/// The guard list: up to three places, a daily budget and the work hours.
public struct GuardList: Codable, Sendable, Equatable {
    public static let maxPlaces = 3
    public static let passMinutes = 5
    public static let pauseSeconds = 5
    public static let defaultBudgetMinutes = 30

    public var places: [GuardedPlace]
    public var budgetMinutes: Int
    public var workHours: WorkHours
    public var enabled: Bool         // false until setup is finished

    public init(places: [GuardedPlace] = [], budgetMinutes: Int = 30, workHours: WorkHours = .init(), enabled: Bool = false) {
        self.places = places
        self.budgetMinutes = budgetMinutes
        self.workHours = workHours
        self.enabled = enabled
    }

    public func place(for o: ActivitySample) -> GuardedPlace? {
        places.first { $0.matches(o) }
    }

    /// False at `maxPlaces` or when the same host or bundle id is already listed.
    @discardableResult
    public mutating func add(_ p: GuardedPlace) -> Bool {
        guard places.count < Self.maxPlaces, !places.contains(where: { $0.overlaps(p) }) else { return false }
        places.append(p)
        return true
    }

    public mutating func remove(_ id: UUID) {
        places.removeAll { $0.id == id }
    }

    public mutating func setMode(_ id: UUID, _ mode: GuardedPlace.Mode) {
        guard let i = places.firstIndex(where: { $0.id == id }) else { return }
        places[i].mode = mode
    }

    /// Up to `limit` proposals from recent sessions: sessions whose guess is .procrastination or .ambiguous,
    /// grouped by host (web) or bundle id (app), ranked by total seconds. Places a built-in rule calls
    /// .productive are skipped.
    public static func proposals(from sessions: [Session], limit: Int = 3) -> [GuardedPlace] {
        struct Group { var place: GuardedPlace; var seconds: Int }
        var groups: [String: Group] = [:]
        for s in sessions where s.guess == .procrastination || s.guess == .ambiguous {
            let sample = s.sample.sample
            if RuleBook.builtIn.bucket(for: sample) == .productive { continue }
            let key: String
            let place: GuardedPlace
            if let host = sample.host {
                key = "h:" + host
                place = GuardedPlace(name: host, host: host)
            } else {
                key = "b:" + sample.bundleID.lowercased()
                place = GuardedPlace(name: sample.appName, bundleID: sample.bundleID)
            }
            groups[key, default: Group(place: place, seconds: 0)].seconds += s.seconds
        }
        let ranked = groups.sorted { $0.value.seconds != $1.value.seconds ? $0.value.seconds > $1.value.seconds : $0.key < $1.key }
        return ranked.prefix(max(0, limit)).map(\.value.place)
    }
}

/// What the app does with the second just counted.
public enum GuardAction: Sendable, Equatable {
    case none
    case pause(GuardedPlace, overBudget: Bool)
    case block(GuardedPlace, until: Date?)
}

/// The guard's memory: passes, the place in front, and today's counters.
public struct GuardState: Codable, Sendable, Equatable {
    public var passes: [UUID: Date] = [:]   // place id → when its pass ends
    public var front: UUID?                 // the guarded place in front at the last tick
    public var day: DayKey?
    public var pausesShown: [UUID: Int] = [:], closes: [UUID: Int] = [:], passesTaken: [UUID: Int] = [:], unlocks: [UUID: Int] = [:]

    public init() {}

    /// One counted second. `o` = the place in front (nil when idle/locked). `isWork` = the owner switched this place
    /// to work (today or always): never guard it. `usedSeconds` = procrastination seconds today.
    public mutating func tick(_ o: ActivitySample?, list: GuardList, isWork: Bool, usedSeconds: Int, now: Date, calendar: Calendar = .current) -> GuardAction {
        rollDay(now, calendar)
        guard list.enabled, let o, !isWork, let place = list.place(for: o) else {
            front = nil
            return .none
        }
        let wasFront = front == place.id
        front = place.id
        let valid = hasPass(place.id, now: now)

        if place.mode == .block, let end = list.workHours.blockEnd(containing: now, calendar: calendar) {
            return valid ? .none : .block(place, until: end)
        }
        if valid { return .none }
        let expired = passes[place.id] != nil
        if expired { passes[place.id] = nil }
        guard !wasFront || expired else { return .none }
        pausesShown[place.id, default: 0] += 1
        return .pause(place, overBudget: usedSeconds >= list.budgetMinutes * 60)
    }

    /// "Open for 5 minutes": a pass of `passMinutes`.
    public mutating func grantPass(_ id: UUID, now: Date) {
        passes[id] = now.addingTimeInterval(TimeInterval(GuardList.passMinutes * 60))
        passesTaken[id, default: 0] += 1
    }

    /// The deliberate unlock of a block: a pass of `passMinutes`, counted in `unlocks`.
    public mutating func unlock(_ id: UUID, now: Date) {
        passes[id] = now.addingTimeInterval(TimeInterval(GuardList.passMinutes * 60))
        unlocks[id, default: 0] += 1
    }

    /// "Close": counted; `front` is cleared so reopening pauses again.
    public mutating func closed(_ id: UUID, now: Date) {
        closes[id, default: 0] += 1
        front = nil
    }

    public func hasPass(_ id: UUID, now: Date) -> Bool {
        guard let end = passes[id] else { return false }
        return end > now
    }

    private mutating func rollDay(_ now: Date, _ calendar: Calendar) {
        let today = DayKey.of(now, calendar: calendar)
        defer { day = today }
        guard let day, day != today else { return }
        passes = [:]
        front = nil                      // a place still in front at the day change pauses again
        pausesShown = [:]; closes = [:]; passesTaken = [:]; unlocks = [:]
    }
}
