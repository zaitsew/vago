import Foundation

/// The global mode shown by one icon.
public enum Mode: String, Codable, Sendable, CaseIterable {
    case work, procrastination, neutral

    public init(_ bucket: Bucket) {
        switch bucket {
        case .productive: self = .work
        case .procrastination, .ambiguous: self = .procrastination
        case .neutral: self = .neutral
        }
    }
}

/// Notices a move from work into procrastination, once per drift.
public struct DriftWatch: Codable, Sendable, Equatable {
    public static let dwellSeconds = 60   // continuous procrastination before the notice
    public static let armSeconds = 60     // work needed before a drift counts as "from work"

    var workSeconds = 0                   // work since the last notice
    var streak = 0                        // continuous procrastination seconds

    public init() {}

    /// One counted second. Returns true at most once per drift, when procrastination has lasted `dwellSeconds`
    /// (neutral seconds neither break nor extend the streak) after at least `armSeconds` of work since the last
    /// notice. A `guarded` place never fires and its seconds do not grow the streak.
    public mutating func tick(_ mode: Mode, guarded: Bool, now: Date) -> Bool {
        switch mode {
        case .work:
            workSeconds += 1
            streak = 0
        case .neutral:
            break
        case .procrastination:
            guard !guarded else { return false }
            streak += 1
            if streak >= Self.dwellSeconds && workSeconds >= Self.armSeconds {
                workSeconds = 0
                streak = 0
                return true
            }
        }
        return false
    }

    /// Locked or idle: resets the procrastination streak, keeps the arming.
    public mutating func idle() { streak = 0 }
}
