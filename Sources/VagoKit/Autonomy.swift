import Foundation

/// Watches the judge for the failure that matters: calling every feed "research".
///
/// The Mac records every second the judge decided on an ambiguous place. When each of the last
/// three finished days had at least 30 such minutes and more than 80% of them came out as work,
/// the judge is held: its "work" verdicts on ambiguous places count as neutral until a day
/// passes the test again or the owner corrects a call.
public struct JudgeAudit: Codable, Sendable, Equatable {
    public static let windowDays = 3
    public static let minimumSeconds = 30 * 60
    public static let maximumWorkShare = 0.8

    public struct Tally: Codable, Sendable, Equatable {
        public var work = 0
        public var other = 0
        public init(work: Int = 0, other: Int = 0) { self.work = work; self.other = other }
        var total: Int { work + other }
        var suspicious: Bool {
            total >= JudgeAudit.minimumSeconds && Double(work) / Double(total) > JudgeAudit.maximumWorkShare
        }
    }

    /// Day id → seconds of sure verdicts on ambiguous places.
    public var days: [String: Tally] = [:]
    /// The day the owner last corrected a call. A correction lifts the hold for that day.
    public var correctedOn: String?

    public init() {}

    /// Counts `seconds` of `c`. Only sure verdicts on ambiguous places count, held ones included.
    public mutating func record(_ c: Classification, seconds: Int, day: DayKey) {
        guard c.ambiguous, let verdict = c.verdict, seconds > 0 else { return }
        var t = days[day.id] ?? Tally()
        if verdict == .productive { t.work += seconds } else { t.other += seconds }
        days[day.id] = t
        if days.count > 14 {
            let cutoff = day.adding(days: -14).id
            days = days.filter { $0.key >= cutoff }
        }
    }

    public mutating func corrected(on day: DayKey) { correctedOn = day.id }

    /// False when the judge should be held today.
    public func trusted(on today: DayKey) -> Bool {
        if correctedOn == today.id { return true }
        for back in 1...Self.windowDays {
            guard let t = days[today.adding(days: -back).id], t.suspicious else { return true }
        }
        return false
    }
}

/// Learns rules for places nothing knew, so the judge is asked less and the answer stays put.
///
/// When the judge gives the same sure verdict (confidence 0.85 or more) on an unknown place on
/// three different days, the place gets an `.auto` rule. Never for a place a rule calls
/// ambiguous: three good YouTube days must not make all of YouTube work.
public struct VerdictMemory: Codable, Sendable, Equatable {
    public static let minimumConfidence = 0.85
    public static let daysNeeded = 3

    public struct Entry: Codable, Sendable, Equatable {
        public var bucket: Bucket
        public var days: [String]
    }

    /// Place key → what the judge said on which days.
    public var places: [String: Entry] = [:]

    public init() {}

    /// Notes one classification. Returns the `.auto` rule to add when the place has earned one.
    public mutating func note(_ o: ActivitySample, _ c: Classification, day: DayKey) -> Rule? {
        guard !c.ambiguous, let confidence = c.confidence, c.source == .judge || c.source == .fallback else { return nil }
        let (key, rule) = Self.place(o, bucket: c.bucket)
        guard c.source == .judge, confidence >= Self.minimumConfidence else {
            places[key] = nil                       // an unsure day breaks the run
            return nil
        }
        var entry = places[key] ?? Entry(bucket: c.bucket, days: [])
        if entry.bucket != c.bucket { entry = Entry(bucket: c.bucket, days: []) }   // the judge changed its mind: start over
        if !entry.days.contains(day.id) { entry.days.append(day.id) }
        places[key] = entry
        guard entry.days.count >= Self.daysNeeded else { return nil }
        places[key] = nil
        return rule
    }

    /// Web: host plus the first path component. App: the bundle id.
    static func place(_ o: ActivitySample, bucket: Bucket) -> (String, Rule) {
        var rule = Rule(bucket: bucket, source: .auto)
        if let host = o.host {
            rule.host = host
            if let first = o.url?.pathComponents.first(where: { $0 != "/" && !$0.isEmpty }) {
                rule.pathPrefix = "/" + first.lowercased()
            }
            return ("web:\(host)\(rule.pathPrefix ?? "")", rule)
        }
        rule.bundleID = o.bundleID
        return ("app:\(o.bundleID.lowercased())", rule)
    }
}
