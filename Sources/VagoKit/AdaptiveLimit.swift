import Foundation

/// The Garmin-style limit in docs/PRODUCT.md. Pure: same inputs, same answer.
///
/// Until three tracked days have finished, the limit is 60 minutes. The median of those
/// first three days (at least 30, rounded to 5) is the baseline and the next limit. After
/// that each finished day moves the limit: at or under it, 5 less; more than 150% of it,
/// 5 more. The limit then stays at or under the baseline and the 7-day median + 10 (floored
/// to 5), at or over 30, in whole 5 minutes.
public struct AdaptiveLimit: Codable, Sendable, Equatable {
    public static let targetMinutes = 30
    public static let calibrationMinutes = 60
    public static let calibrationDays = 3
    public static let stepMinutes = 5

    public var baseline: Int?                    // set after calibration
    public var current: Int                      // minutes, today
    public var lastDay: DayKey?                  // the day `current` was last rolled to

    public init() {
        baseline = nil
        current = Self.calibrationMinutes
        lastDay = nil
    }

    /// Rolls the limit forward to `today` using finished days' procrastination. The limit is
    /// replayed from the ledger's first tracked day every time, each finished day against the
    /// limit that was current on that day, so a day that syncs late from another device still
    /// counts. Days with no data change nothing; the same ledger always gives the same limit.
    /// A day before `lastDay` (the clock moved back) changes nothing.
    public mutating func roll(to today: DayKey, ledger: Ledger) {
        if let lastDay, today < lastDay { return }
        let finished = ledger.trackedDays().filter { $0 < today }
        let minutes = finished.map { ledger.total(for: $0).procrastination / 60 }
        lastDay = today
        guard finished.count >= Self.calibrationDays else {
            baseline = nil
            current = Self.calibrationMinutes
            return
        }
        // Calibration days ran under the 60-minute limit and are not applied.
        let base = max(Self.targetMinutes, Self.round5(Self.median(Array(minutes.prefix(Self.calibrationDays)))))
        baseline = base
        current = base
        for i in Self.calibrationDays..<finished.count {
            let usedSeconds = ledger.total(for: finished[i]).procrastination
            let limitSeconds = current * 60
            if usedSeconds <= limitSeconds {
                current -= Self.stepMinutes
            } else if usedSeconds * 100 > limitSeconds * 150 {
                current += Self.stepMinutes
            }
            let window = Array(minutes[max(0, i - 6)...i])
            // The cap is floored to whole 5 minutes, so rounding never lifts the limit over it.
            let cap = Self.floor5(min(base, Self.median(window) + 10))
            current = max(Self.targetMinutes, min(current, cap))
        }
    }

    /// Middle value; the floor of the mean of the two middle values for an even count.
    static func median(_ values: [Int]) -> Int {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }

    /// Nearest multiple of 5 (halves round up).
    static func round5(_ value: Int) -> Int { (value + 2) / 5 * 5 }

    /// Largest multiple of 5 at or under `value`.
    static func floor5(_ value: Int) -> Int { value / 5 * 5 }
}
