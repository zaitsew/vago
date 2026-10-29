import Foundation

/// One device's totals for one day. Seconds.
public struct DeviceDay: Codable, Sendable, Equatable {
    public var day: DayKey
    public var device: Device
    public var procrastination: Int
    public var productive: Int
    public var focus: Int
    public var updatedAt: Date

    public init(day: DayKey, device: Device, procrastination: Int = 0, productive: Int = 0, focus: Int = 0, updatedAt: Date) {
        self.day = day
        self.device = device
        self.procrastination = procrastination
        self.productive = productive
        self.focus = focus
        self.updatedAt = updatedAt
    }

    var totalSeconds: Int { procrastination + productive + focus }
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
                && (existing.procrastination, existing.productive, existing.focus)
                    >= (other.procrastination, other.productive, other.focus) { return }
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
}
