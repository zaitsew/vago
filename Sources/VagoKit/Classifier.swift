import Foundation

/// What the judge knows besides the page itself.
public struct JudgeContext: Sendable, Equatable {
    /// Local clock hour, 0–23.
    public var hour: Int?
    /// How long this place has been in front, in seconds.
    public var secondsInFront: Int
    /// The last counted place before this one, within 10 minutes: "Xcode (work)".
    public var previous: String?
    /// True when a rule called this place ambiguous; false when nothing knows it.
    public var ambiguous: Bool

    public init(hour: Int? = nil, secondsInFront: Int = 0, previous: String? = nil, ambiguous: Bool = true) {
        self.hour = hour
        self.secondsInFront = secondsInFront
        self.previous = previous
        self.ambiguous = ambiguous
    }
}

/// The AI judge for places no rule settles. The Mac app supplies the FoundationModels
/// implementation; tests supply a stub.
public protocol Judge: Sendable {
    func judge(_ o: ActivitySample, goals: String, context: JudgeContext) async -> Verdict?
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
    /// Who decided.
    public enum Source: String, Codable, Sendable {
        case rule        // a built-in, learned or corrected rule
        case answer      // the owner's answer today
        case judge       // the AI, sure enough
        case fallback    // no rule and no usable verdict
    }

    public var bucket: Bucket
    /// True when the call was a guess: shown in "Vago's calls" for a one-tap correction.
    public var unclear: Bool
    public var reason: String
    public var source: Source
    /// True when a rule called the place ambiguous (Instagram, YouTube, a browser with no URL).
    public var ambiguous: Bool
    /// The judge's confidence, when the judge decided or was asked.
    public var confidence: Double?
    /// The judge's sure answer (confidence at or above the line), even when it was held.
    public var verdict: Bucket?

    public init(bucket: Bucket, unclear: Bool, reason: String, source: Source = .rule, ambiguous: Bool = false,
                confidence: Double? = nil, verdict: Bucket? = nil) {
        self.bucket = bucket
        self.unclear = unclear
        self.reason = reason
        self.source = source
        self.ambiguous = ambiguous
        self.confidence = confidence
        self.verdict = verdict
    }
}

/// Classifier = rules, then the day cache, then the judge.
///
/// Vago decides on its own; the owner only corrects a miss.
/// - A rule settles the place: its bucket. The judge cannot override a rule, so feeds stay waste.
/// - A place no rule knows, or one a rule calls ambiguous, goes to the judge.
/// - A verdict at or above 0.7 confidence is the answer.
/// - A weaker verdict, or none, is neutral and unclear: it does not move the share either way.
/// - Without a judge, ambiguous use counts as procrastination (unclear) and unknown use as neutral.
/// - While the judge is held (`setJudgeTrusted(false)`, see `JudgeAudit`), a "work" verdict on an
///   ambiguous place counts as neutral.
public actor Classifier {
    /// Verdicts below this confidence are guesses.
    public static let minimumConfidence = 0.7

    private var rules: RuleBook
    private var goals: String
    private let judge: Judge?
    private var judgeTrusted = true
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    private var cacheDay: DayKey
    private var cache: [String: Verdict] = [:]
    private var inFlight: [String: Task<Verdict?, Never>] = [:]
    /// Bumped when the goals change, so a verdict asked under the old goals is not cached.
    private var generation = 0

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

    /// Swap the rules after a correction or a learned rule. Cached verdicts stay: rules are checked first.
    public func update(rules: RuleBook) { self.rules = rules }

    public func update(goals: String) {
        guard goals != self.goals else { return }
        self.goals = goals
        cache.removeAll()                          // verdicts were made against the old goals
        inFlight.removeAll()
        generation += 1
    }

    /// False holds the judge's "work" verdicts on ambiguous places (see `JudgeAudit`).
    public func setJudgeTrusted(_ trusted: Bool) { judgeTrusted = trusted }

    public var hasJudge: Bool { judge != nil }

    public func classify(_ o: ActivitySample, context: JudgeContext = JudgeContext()) async -> Classification {
        let rule = rules.matchingRule(for: o)
        if let rule, rule.bucket != .ambiguous {
            return Classification(bucket: rule.bucket, unclear: false, reason: "rule: \(Self.describe(rule))", source: .rule)
        }
        let ambiguous = rule != nil
        guard let judge else {
            return ambiguous
                ? Classification(bucket: .procrastination, unclear: true, reason: "ambiguous, no judge available", source: .fallback, ambiguous: true)
                : Classification(bucket: .neutral, unclear: false, reason: "no rule matches", source: .fallback)
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
            let asked = generation
            var ctx = context
            ctx.ambiguous = ambiguous
            let task = Task { await judge.judge(o, goals: goals, context: ctx) }
            inFlight[key] = task
            verdict = await task.value
            if generation == asked {
                inFlight[key] = nil
                if let verdict, cacheDay == day { cache[key] = verdict }   // a nil verdict is retried next time
            }
        }
        return classification(from: verdict, ambiguous: ambiguous)
    }

    private func classification(from verdict: Verdict?, ambiguous: Bool) -> Classification {
        guard let verdict else {
            return Classification(bucket: .neutral, unclear: true, reason: "the judge gave no verdict", source: .fallback, ambiguous: ambiguous)
        }
        guard verdict.confidence >= Self.minimumConfidence, verdict.bucket != .ambiguous else {
            return Classification(bucket: .neutral, unclear: true, reason: "unsure: \(verdict.reason)", source: .fallback,
                                  ambiguous: ambiguous, confidence: verdict.confidence)
        }
        if ambiguous, verdict.bucket == .productive, !judgeTrusted {
            return Classification(bucket: .neutral, unclear: true, reason: "held: \(verdict.reason)", source: .fallback,
                                  ambiguous: true, confidence: verdict.confidence, verdict: .productive)
        }
        return Classification(bucket: verdict.bucket, unclear: false, reason: verdict.reason, source: .judge,
                              ambiguous: ambiguous, confidence: verdict.confidence, verdict: verdict.bucket)
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
