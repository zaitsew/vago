import Foundation

/// The AI judge for ambiguous observations. The Mac app supplies the FoundationModels
/// implementation; tests supply a stub.
public protocol Judge: Sendable {
    func judge(_ o: ActivitySample, goals: String) async -> Verdict?
}

public struct Verdict: Codable, Sendable, Equatable {
    public var bucket: Bucket
    public var confidence: Double
    public var reason: String

    public init(bucket: Bucket, confidence: Double, reason: String) {
        self.bucket = bucket
        self.confidence = confidence
        self.reason = reason
    }
}

public struct Classification: Sendable, Equatable {
    public var bucket: Bucket
    /// True when the call was a guess: queue the session for the nightly review.
    public var unclear: Bool
    public var reason: String

    public init(bucket: Bucket, unclear: Bool, reason: String) {
        self.bucket = bucket
        self.unclear = unclear
        self.reason = reason
    }
}

/// Classifier = rules, then the day cache, then the judge. A verdict under 0.6 confidence,
/// no verdict, or no judge counts as procrastination and is queued for review (`unclear == true`).
public actor Classifier {
    /// Verdicts below this confidence are guesses.
    public static let minimumConfidence = 0.6

    private var rules: RuleBook
    private var goals: String
    private let judge: Judge?
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    private var cacheDay: DayKey
    private var cache: [String: Verdict] = [:]
    private var inFlight: [String: Task<Verdict?, Never>] = [:]

    public init(
        rules: RuleBook,
        judge: Judge?,
        goals: String,
        now: @escaping @Sendable () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.rules = rules
        self.judge = judge
        self.goals = goals
        self.now = now
        self.calendar = calendar
        self.cacheDay = DayKey.of(now(), calendar: calendar)
    }

    /// Swap the rules after the owner answers a review. Cached verdicts stay: rules are checked first.
    public func update(rules: RuleBook) { self.rules = rules }

    public func update(goals: String) { self.goals = goals }

    public func classify(_ o: ActivitySample) async -> Classification {
        let rule = rules.matchingRule(for: o)
        let bucket = rule?.bucket ?? .neutral
        guard bucket == .ambiguous else {
            let why = rule.map { "rule: \(Self.describe($0))" } ?? "no rule matches"
            return Classification(bucket: bucket, unclear: false, reason: why)
        }
        guard let judge else {
            return Classification(bucket: .procrastination, unclear: true, reason: "ambiguous, no judge available")
        }

        let day = DayKey.of(now(), calendar: calendar)
        if day != cacheDay {
            cacheDay = day
            cache.removeAll()
            inFlight.removeAll()
        }
        let key = Self.cacheKey(o, day: day)

        let verdict: Verdict?
        if let cached = cache[key] {
            verdict = cached
        } else if let pending = inFlight[key] {
            verdict = await pending.value          // one judge call per key, even when asked every second
        } else {
            let goals = self.goals
            let task = Task { await judge.judge(o, goals: goals) }
            inFlight[key] = task
            verdict = await task.value
            inFlight[key] = nil
            if let verdict, cacheDay == day { cache[key] = verdict }   // a nil verdict is retried next time
        }
        return Self.classification(from: verdict)
    }

    private static func classification(from verdict: Verdict?) -> Classification {
        guard let verdict else {
            return Classification(bucket: .procrastination, unclear: true, reason: "ambiguous, the judge gave no verdict")
        }
        guard verdict.confidence >= minimumConfidence, verdict.bucket != .ambiguous else {
            return Classification(bucket: .procrastination, unclear: true, reason: "unsure: \(verdict.reason)")
        }
        return Classification(bucket: verdict.bucket, unclear: false, reason: verdict.reason)
    }

    /// Day, then host (or bundle id), then the title with case and spacing removed.
    private static func cacheKey(_ o: ActivitySample, day: DayKey) -> String {
        let place = o.host.map { "host:\($0)" } ?? "app:\(o.bundleID.lowercased())"
        let title = (o.windowTitle ?? "")
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return "\(day.id)|\(place)|\(title)"
    }

    private static func describe(_ rule: Rule) -> String {
        var parts: [String] = []
        if let b = rule.bundleID { parts.append(b) }
        if let h = rule.host { parts.append(h + (rule.pathPrefix ?? "")) }
        else if let p = rule.pathPrefix { parts.append(p) }
        if let t = rule.titleContains { parts.append("title~\(t)") }
        return "\(parts.joined(separator: " ")) is \(rule.bucket.rawValue)"
    }
}
