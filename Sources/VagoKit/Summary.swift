import Foundation

/// One day's numbers across devices, in whole minutes (seconds / 60, rounded down, as `Readout` does).
/// The shared answer behind the iPhone's App Intents and the read-only MCP server.
public struct DaySummary: Codable, Sendable, Equatable {
    public var day: String
    public var tracked: Bool
    public var procrastinationMinutes: Int
    public var productiveMinutes: Int
    public var focusMinutes: Int
    /// The daily limit. Only known for today: earlier days did not keep theirs.
    public var limitMinutes: Int?
    public var remainingMinutes: Int?
    public var mood: String?
    public var emoji: String?

    public init(
        day: String, tracked: Bool, procrastinationMinutes: Int, productiveMinutes: Int, focusMinutes: Int,
        limitMinutes: Int? = nil
    ) {
        self.day = day
        self.tracked = tracked
        self.procrastinationMinutes = procrastinationMinutes
        self.productiveMinutes = productiveMinutes
        self.focusMinutes = focusMinutes
        self.limitMinutes = limitMinutes
        if let limitMinutes {
            remainingMinutes = max(0, limitMinutes - procrastinationMinutes)
            let m = Mood(used: procrastinationMinutes * 60, limitMinutes: limitMinutes)
            mood = m.name
            emoji = m.emoji
        }
    }

    /// "😄 12 of 30 min on procrastination, 18 min left. 45 min of work, 25 min of focus."
    public var sentence: String {
        var parts: [String] = []
        if let limitMinutes, let emoji, let remainingMinutes {
            let left = remainingMinutes > 0 ? "\(remainingMinutes) min left" : "over the limit"
            parts.append("\(emoji) \(procrastinationMinutes) of \(limitMinutes) min on procrastination, \(left).")
        } else {
            parts.append("\(procrastinationMinutes) min on procrastination.")
        }
        parts.append("\(productiveMinutes) min of work, \(focusMinutes) min of focus.")
        return parts.joined(separator: " ")
    }
}

/// The last `days` days, ending today. Days with no data are listed as untracked, with zeros,
/// and left out of the averages.
public struct WeekSummary: Codable, Sendable, Equatable {
    public var from: String
    public var to: String
    public var days: [DaySummary]
    public var trackedDays: Int
    public var totalProcrastinationMinutes: Int
    public var totalProductiveMinutes: Int
    public var totalFocusMinutes: Int
    /// Averages over tracked days; nil when none is tracked.
    public var averageProcrastinationMinutes: Int?
    public var averageProductiveMinutes: Int?
    /// Tracked days at or under the 30-minute target (`AdaptiveLimit.targetMinutes`).
    public var daysUnderTarget: Int
    public var targetMinutes: Int
    public var bestDay: String?
    public var worstDay: String?

    public var sentence: String {
        guard trackedDays > 0, let avgP = averageProcrastinationMinutes, let avgW = averageProductiveMinutes else {
            return "No tracked days in the last \(days.count) days."
        }
        return "Last \(days.count) days (\(trackedDays) tracked): \(avgP) min a day on procrastination, "
            + "\(avgW) min a day of work, \(totalFocusMinutes) min of focus in all. "
            + "\(daysUnderTarget) of \(trackedDays) days at or under \(targetMinutes) min."
    }
}

extension Mood {
    /// A stable word for the mood, for machine-readable output.
    public var name: String {
        switch self {
        case .beaming: "beaming"
        case .happy: "happy"
        case .neutral: "neutral"
        case .worried: "worried"
        case .upset: "upset"
        case .wrecked: "wrecked"
        }
    }
}

extension Ledger {
    /// `day`'s totals across devices. `limitMinutes` is passed for today only.
    public func summary(for day: DayKey, limitMinutes: Int? = nil) -> DaySummary {
        let total = total(for: day)
        let tracked = Device.allCases.contains { days[Self.key(day, $0)] != nil }
        return DaySummary(
            day: day.id,
            tracked: tracked,
            procrastinationMinutes: total.procrastination / 60,
            productiveMinutes: total.productive / 60,
            focusMinutes: total.focus / 60,
            limitMinutes: limitMinutes
        )
    }

    /// The `count` days ending on `today`, oldest first. Today carries `limitMinutes`.
    public func weekSummary(endingOn today: DayKey, limitMinutes: Int, count: Int = 7) -> WeekSummary {
        let count = max(1, count)
        let list = (0..<count).map { offset -> DaySummary in
            let day = today.adding(days: offset - (count - 1))
            return summary(for: day, limitMinutes: day == today ? limitMinutes : nil)
        }
        let tracked = list.filter(\.tracked)
        let sumP = tracked.reduce(0) { $0 + $1.procrastinationMinutes }
        let sumW = tracked.reduce(0) { $0 + $1.productiveMinutes }
        let sumF = tracked.reduce(0) { $0 + $1.focusMinutes }
        return WeekSummary(
            from: list.first?.day ?? today.id,
            to: today.id,
            days: list,
            trackedDays: tracked.count,
            totalProcrastinationMinutes: sumP,
            totalProductiveMinutes: sumW,
            totalFocusMinutes: sumF,
            averageProcrastinationMinutes: tracked.isEmpty ? nil : sumP / tracked.count,
            averageProductiveMinutes: tracked.isEmpty ? nil : sumW / tracked.count,
            daysUnderTarget: tracked.filter { $0.procrastinationMinutes <= AdaptiveLimit.targetMinutes }.count,
            targetMinutes: AdaptiveLimit.targetMinutes,
            bestDay: tracked.min { $0.procrastinationMinutes < $1.procrastinationMinutes }?.day,
            worstDay: tracked.max { $0.procrastinationMinutes < $1.procrastinationMinutes }?.day
        )
    }
}
