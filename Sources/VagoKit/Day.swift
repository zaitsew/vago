import Foundation

/// A 04:00-to-04:00 day. Late-night use belongs to the evening it started in.
public struct DayKey: Codable, Hashable, Comparable, Sendable {
    /// "2026-10-29". ISO dates sort the same as calendar dates.
    public let id: String

    /// The local hour at which a new day starts.
    public static let rolloverHour = 4

    public init(id: String) { self.id = id }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool { lhs.id < rhs.id }

    /// The day `date` belongs to in `calendar`'s time zone: 2026-10-30 02:30 is "2026-10-29".
    public static func of(_ date: Date, calendar: Calendar = .current) -> DayKey {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        var moment = date
        if gregorian.component(.hour, from: date) < rolloverHour {
            moment = gregorian.date(byAdding: .day, value: -1, to: date) ?? date.addingTimeInterval(-86_400)
        }
        let c = gregorian.dateComponents([.year, .month, .day], from: moment)
        return DayKey(id: String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0))
    }

    /// The day `days` calendar days later (negative: earlier). Returns `self` for a malformed id.
    public func adding(days: Int) -> DayKey {
        let parts = id.split(separator: "-").compactMap { Int($0) }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        guard parts.count == 3,
              let noon = utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)),
              let moved = utc.date(byAdding: .day, value: days, to: noon)
        else { return self }
        let c = utc.dateComponents([.year, .month, .day], from: moved)
        return DayKey(id: String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0))
    }
}
