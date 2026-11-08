import Foundation

/// One device's totals for one day. Seconds.
public struct DeviceDay: Codable, Sendable, Equatable {
    public var day: DayKey
    public var device: Device
    public var procrastination: Int
    public var productive: Int
    public var focus: Int
    public var updatedAt: Date
    /// Productive seconds per hour slot (`DayKey.hourSlot`), 24 entries. Empty in values
    /// written before hours existed.
    public var productiveByHour: [Int]
    /// Procrastination seconds per hour slot, 24 entries. Empty in older values.
    public var procrastinationByHour: [Int]
    /// Neutral seconds (Finder, Maps, a bank app, an unsure call): counted in the share's
    /// denominator, never as waste. 0 in older values and on the iPhone, which cannot see them.
    public var neutral: Int
    /// Neutral seconds per hour slot, 24 entries. Empty in older values.
    public var neutralByHour: [Int]

    public init(day: DayKey, device: Device, procrastination: Int = 0, productive: Int = 0, focus: Int = 0,
                neutral: Int = 0, updatedAt: Date) {
        self.day = day
        self.device = device
        self.procrastination = procrastination
        self.productive = productive
        self.focus = focus
        self.updatedAt = updatedAt
        self.productiveByHour = []
        self.procrastinationByHour = []
        self.neutral = neutral
        self.neutralByHour = []
    }

    private enum CodingKeys: String, CodingKey {
        case day, device, procrastination, productive, focus, updatedAt, productiveByHour, procrastinationByHour
        case neutral, neutralByHour
    }

    /// Values from builds before hours existed decode with empty hour lists.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(DayKey.self, forKey: .day)
        device = try c.decode(Device.self, forKey: .device)
        procrastination = try c.decode(Int.self, forKey: .procrastination)
        productive = try c.decode(Int.self, forKey: .productive)
        focus = try c.decode(Int.self, forKey: .focus)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        productiveByHour = try c.decodeIfPresent([Int].self, forKey: .productiveByHour) ?? []
        procrastinationByHour = try c.decodeIfPresent([Int].self, forKey: .procrastinationByHour) ?? []
        neutral = try c.decodeIfPresent(Int.self, forKey: .neutral) ?? 0
        neutralByHour = try c.decodeIfPresent([Int].self, forKey: .neutralByHour) ?? []
    }

    var totalSeconds: Int { procrastination + productive + focus }

    /// Counts `seconds` of `bucket` use that ended at `date`: the day total and its hour slot.
    /// Ambiguous seconds are not counted (the classifier settles them before they get here).
    public mutating func add(_ bucket: Bucket, seconds: Int, at date: Date, calendar: Calendar = .current) {
        guard seconds > 0 else { return }
        let slot = DayKey.hourSlot(of: date, calendar: calendar)
        switch bucket {
        case .productive:
            productive += seconds
            Self.bump(&productiveByHour, slot, seconds)
        case .procrastination:
            procrastination += seconds
            Self.bump(&procrastinationByHour, slot, seconds)
        case .neutral:
            neutral += seconds
            Self.bump(&neutralByHour, slot, seconds)
        case .ambiguous:
            break
        }
    }

    /// Moves up to `seconds` from one bucket to another (a corrected call), in the day total
    /// and in the hour slot of `date`. Returns the seconds moved.
    @discardableResult
    public mutating func move(_ seconds: Int, from: Bucket, to: Bucket, at date: Date, calendar: Calendar = .current) -> Int {
        guard from != to, seconds > 0, from != .ambiguous, to != .ambiguous else { return 0 }
        let slot = DayKey.hourSlot(of: date, calendar: calendar)
        let moved = min(seconds, self[total: from])
        guard moved > 0 else { return 0 }
        self[total: from] -= moved
        self[total: to] += moved
        Self.bump(&self[hours: from], slot, -moved)
        Self.bump(&self[hours: to], slot, moved)
        return moved
    }

    /// Moves a corrected session that started at `start` and lasted `seconds`, hour by hour,
    /// so a 10:50–11:10 session moves 10 minutes in each hour slot. Returns the seconds moved.
    @discardableResult
    public mutating func move(_ seconds: Int, from: Bucket, to: Bucket, startingAt start: Date, calendar: Calendar = .current) -> Int {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        var cursor = start
        var left = seconds
        var moved = 0
        while left > 0 {
            let hourStart = gregorian.dateInterval(of: .hour, for: cursor)?.start ?? cursor
            let nextHour = hourStart.addingTimeInterval(3600)
            let chunk = max(1, min(left, Int(nextHour.timeIntervalSince(cursor).rounded(.up))))
            moved += move(chunk, from: from, to: to, at: cursor, calendar: calendar)
            left -= chunk
            cursor = nextHour
        }
        return moved
    }

    private subscript(total bucket: Bucket) -> Int {
        get {
            switch bucket {
            case .productive: productive
            case .procrastination: procrastination
            case .neutral: neutral
            case .ambiguous: 0
            }
        }
        set {
            switch bucket {
            case .productive: productive = newValue
            case .procrastination: procrastination = newValue
            case .neutral: neutral = newValue
            case .ambiguous: break
            }
        }
    }

    private subscript(hours bucket: Bucket) -> [Int] {
        get {
            switch bucket {
            case .productive: productiveByHour
            case .procrastination: procrastinationByHour
            case .neutral: neutralByHour
            case .ambiguous: []
            }
        }
        set {
            switch bucket {
            case .productive: productiveByHour = newValue
            case .procrastination: procrastinationByHour = newValue
            case .neutral: neutralByHour = newValue
            case .ambiguous: break
            }
        }
    }

    /// Sets the hour lists to 24 entries and adds `delta` to `slot`.
    static func bump(_ hours: inout [Int], _ slot: Int, _ delta: Int) {
        if hours.count != DayKey.hoursPerDay {
            hours = (0..<DayKey.hoursPerDay).map { hours.indices.contains($0) ? hours[$0] : 0 }
        }
        guard hours.indices.contains(slot) else { return }
        hours[slot] = max(0, hours[slot] + delta)
    }
}

/// One hour slot of a day, across devices or for one device. Seconds.
public struct HourSlot: Codable, Sendable, Equatable, Identifiable {
    public var slot: Int                 // 0 = 04:00
    public var productive: Int
    public var procrastination: Int
    public var neutral: Int
    public var id: Int { slot }
    public var clockHour: Int { DayKey.clockHour(ofSlot: slot) }
    public var total: Int { productive + procrastination + neutral }
    public init(slot: Int, productive: Int = 0, procrastination: Int = 0, neutral: Int = 0) {
        self.slot = slot
        self.productive = productive
        self.procrastination = procrastination
        self.neutral = neutral
    }
}

extension DeviceDay {
    /// The 24 hour slots of this device's day.
    public var hours: [HourSlot] {
        (0..<DayKey.hoursPerDay).map { i in
            HourSlot(
                slot: i,
                productive: productiveByHour.indices.contains(i) ? productiveByHour[i] : 0,
                procrastination: procrastinationByHour.indices.contains(i) ? procrastinationByHour[i] : 0,
                neutral: neutralByHour.indices.contains(i) ? neutralByHour[i] : 0
            )
        }
    }
}

/// All devices' days, merged. The key-value store keeps one JSON value per
/// `day/<day id>/<device>` key; the later `updatedAt` wins per key.
public struct Ledger: Codable, Sendable {
    public var days: [String: DeviceDay]         // key = "day/<id>/<device>"

    public init(days: [String: DeviceDay] = [:]) { self.days = days }

    /// The key-value store key for one device's day.
    public static func key(_ day: DayKey, _ device: Device) -> String { "day/\(day.id)/\(device.rawValue)" }

    /// Sums every device's seconds for `day`.
    public func total(for day: DayKey) -> (procrastination: Int, productive: Int, focus: Int) {
        var sum = (procrastination: 0, productive: 0, focus: 0)
        for device in Device.allCases {
            guard let d = days[Self.key(day, device)] else { continue }
            sum.procrastination += d.procrastination
            sum.productive += d.productive
            sum.focus += d.focus
        }
        return sum
    }

    /// Keeps the value with the later `updatedAt`. On a tie, the larger value wins, compared
    /// by (procrastination, productive, focus), so merging in any order gives the same ledger.
    public mutating func merge(_ other: DeviceDay) {
        let key = Self.key(other.day, other.device)
        if let existing = days[key] {
            if existing.updatedAt > other.updatedAt { return }
            if existing.updatedAt == other.updatedAt
                && (existing.procrastination, existing.productive, existing.focus, existing.neutral)
                    >= (other.procrastination, other.productive, other.focus, other.neutral) { return }
        }
        days[key] = other
    }

    /// Days with a value on any device, oldest first.
    public func trackedDays() -> [DayKey] {
        Set(days.values.map(\.day)).sorted()
    }

    /// Procrastination minutes (seconds / 60, rounded down) of tracked days before `day`,
    /// oldest first, at most `count` entries. A day is tracked if any device has a value.
    public func history(endingBefore day: DayKey, count: Int) -> [Int] {
        guard count > 0 else { return [] }
        return trackedDays()
            .filter { $0 < day }
            .suffix(count)
            .map { total(for: $0).procrastination / 60 }
    }

    /// The 24 hour slots of `day`, summed over `devices` (all devices by default).
    public func hours(for day: DayKey, devices: [Device] = Device.allCases) -> [HourSlot] {
        var slots = (0..<DayKey.hoursPerDay).map { HourSlot(slot: $0) }
        for device in devices {
            guard let d = days[Self.key(day, device)] else { continue }
            for h in d.hours {
                slots[h.slot].productive += h.productive
                slots[h.slot].procrastination += h.procrastination
                slots[h.slot].neutral += h.neutral
            }
        }
        return slots
    }
}
