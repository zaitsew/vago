import Foundation

/// The main number: the share of active time that was not waste.
///
///     100% − procrastination / (productive + neutral + procrastination)
///
/// "100% minus the time spent on bullshit." Neutral use (Finder, Maps, a bank app, a call the AI
/// was unsure about) is not waste, so it counts as productive here. Idle, locked and asleep time
/// is not in it at all. A minute is a minute on every device; the iPhone adds only what Screen
/// Time reports (its waste and work lists), so its neutral time is missing.
/// Below 15 active minutes the share is not shown: two minutes of Reels at 09:00 would read 0%.
public struct ProductiveShare: Sendable, Equatable {
    /// Active seconds needed before the share is shown.
    public static let minimumSeconds = 15 * 60

    public var productive: Int
    public var neutral: Int
    public var procrastination: Int

    public init(productive: Int, neutral: Int = 0, procrastination: Int) {
        self.productive = max(0, productive)
        self.neutral = max(0, neutral)
        self.procrastination = max(0, procrastination)
    }

    /// Seconds in the denominator.
    public var active: Int { productive + neutral + procrastination }

    /// Whole percent; nil below `minimumSeconds`. 100 only with no waste at all, 0 only with
    /// nothing but waste.
    public var percent: Int? {
        guard active >= Self.minimumSeconds else { return nil }
        let waste = Double(procrastination) * 100 / Double(active)
        var p = 100 - Int(waste.rounded())
        if p == 100 && procrastination > 0 { p = 99 }
        if p == 0 && procrastination < active { p = 1 }
        return p
    }

    /// "92%", or "—" while there is too little to judge.
    public var text: String { percent.map { "\($0)%" } ?? "—" }

    /// Green from 90% (30 minutes of waste in a 5-hour day), yellow from 75%, red below.
    public var tint: Tint? {
        guard let p = percent else { return nil }
        return p >= 90 ? .green : p >= 75 ? .yellow : .red
    }
}

extension Ledger {
    /// `day`'s share across `devices` (all by default).
    public func share(for day: DayKey, devices: [Device] = Device.allCases) -> ProductiveShare {
        var p = 0, n = 0, w = 0
        for device in devices {
            guard let d = days[Self.key(day, device)] else { continue }
            p += d.productive
            n += d.neutral
            w += d.procrastination
        }
        return ProductiveShare(productive: p, neutral: n, procrastination: w)
    }
}
