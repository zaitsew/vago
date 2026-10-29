import Foundation

/// Forest-style session: a seedling grows into a tree; a distraction wilts it.
public struct FocusSession: Codable, Sendable, Equatable {
    public enum State: String, Codable, Sendable { case growing, grown, wilted, abandoned }

    /// More than this many distracted seconds wilts the tree.
    public static let wiltThresholdSeconds = 60

    public var start: Date
    public var minutes: Int                      // 25 or 50
    public var distractedSeconds: Int
    public var state: State                      // .growing, .grown, .wilted, .abandoned
    /// When the session stopped growing (grown, wilted or abandoned). `nil` while growing.
    public var endedAt: Date?

    public init(start: Date, minutes: Int = 25) {
        self.start = start
        self.minutes = minutes
        self.distractedSeconds = 0
        self.state = .growing
        self.endedAt = nil
    }

    public var duration: TimeInterval { TimeInterval(max(1, minutes) * 60) }
    public var end: Date { start.addingTimeInterval(duration) }

    /// Seconds since the start, clamped to the session length.
    public func elapsed(at now: Date) -> TimeInterval {
        min(duration, max(0, now.timeIntervalSince(start)))
    }

    /// 0...1 of the planned length.
    public func fraction(at now: Date) -> Double { elapsed(at: now) / duration }

    public func remaining(at now: Date) -> TimeInterval { duration - elapsed(at: now) }

    /// "🌱" under 25%, "🌿" under 50%, "🪴" under 100%, "🌳" when done, "🥀" when wilted or abandoned.
    public func stage(at now: Date) -> String {
        if state == .wilted || state == .abandoned { return "🥀" }
        let f = fraction(at: now)
        if f < 0.25 { return "🌱" }
        if f < 0.5 { return "🌿" }
        if f < 1 { return "🪴" }
        return "🌳"
    }

    /// Seconds that count as focus: from the start to the moment the session stopped
    /// (or `now` while it grows), never past the planned length.
    public func focusSeconds(at now: Date) -> Int {
        let until = endedAt ?? now
        return Int(elapsed(at: until))
    }

    /// Feeds one stretch of foreground use. Procrastination and ambiguous use distract;
    /// productive and neutral use do not. Does nothing once the session has stopped.
    /// Use after the planned end does not count: the tree has already grown.
    public mutating func tick(bucket: Bucket, seconds: Int, now: Date) {
        guard state == .growing else { return }
        if bucket == .procrastination || bucket == .ambiguous {
            let tickStart = now.addingTimeInterval(-TimeInterval(max(0, seconds)))
            let beforeEnd = Int(max(0, min(now, end).timeIntervalSince(tickStart)))
            distractedSeconds += min(max(0, seconds), beforeEnd)
        }
        if distractedSeconds > Self.wiltThresholdSeconds {
            state = .wilted
            endedAt = min(now, end)
        } else if now >= end {
            state = .grown
            endedAt = end
        }
    }

    /// The owner stopped early. Keeps the focus time up to `now`.
    public mutating func abandon(now: Date) {
        guard state == .growing else { return }
        state = .abandoned
        endedAt = now
    }
}
