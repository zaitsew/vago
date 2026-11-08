import Foundation

/// One short exercise that needs no equipment and fits beside a desk.
public struct Move: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    /// Exactly what to do, with reps or seconds.
    public var how: String

    public init(id: String, title: String, how: String) {
        self.id = id
        self.title = title
        self.how = how
    }

    /// The rotation. Each takes 2 to 3 minutes, needs no floor and no change of clothes.
    public static let all: [Move] = [
        Move(id: "squats", title: "Squats", how: "15 slow squats, 3 seconds down. Then shake out your legs."),
        Move(id: "desk-pushups", title: "Desk push-ups", how: "12 push-ups with your hands on the desk edge. Body straight."),
        Move(id: "hip-flexor", title: "Hip flexor stretch", how: "Lunge stance, back knee soft. 30 seconds each side, twice."),
        Move(id: "walk", title: "Walk and water", how: "Walk for 2 minutes, refill your water and look at something far away."),
        Move(id: "calf-raises", title: "Calf raises", how: "20 slow calf raises, then 20 more on your toes' edge."),
        Move(id: "chest-opener", title: "Chest opener", how: "Hands clasped behind your back, chest up. 3 × 20 seconds."),
        Move(id: "reverse-lunges", title: "Reverse lunges", how: "10 reverse lunges each leg, one hand on the desk if needed."),
        Move(id: "neck-shoulders", title: "Neck and shoulders", how: "10 shoulder rolls each way, 10 chin tucks, 20 seconds per side ear to shoulder."),
        Move(id: "back-extension", title: "Standing back bend", how: "Hands on your lower back, lean back gently. 10 times, then 10 torso twists."),
    ]
}

/// One finished move.
public struct MoveEntry: Codable, Sendable, Equatable {
    public var at: Date
    public var moveID: String

    public init(at: Date, moveID: String) {
        self.at = at
        self.moveID = moveID
    }
}

/// The "you have been at the laptop non-stop" reminder. Pure: the Mac app feeds it the seconds
/// someone is at the Mac and asks whether a reminder is due.
///
/// - A streak is unbroken time at the Mac, whatever the app. A gap of `restSeconds` without use
///   (away, locked, asleep) is a break: the next use starts a new streak.
/// - After `streakMinutes` the reminder is due. "Later" asks again in `laterMinutes`. A reminder
///   nobody answered asks again in `retryMinutes`. After `maxIgnored` unanswered reminders the
///   panel stops for this streak and only the menu-bar mark stays, so it never nags.
/// - "I did it" logs the move and starts a new streak. "Not today" silences it until 04:00.
public struct BreakCoach: Codable, Sendable, Equatable {
    public static let defaultStreakMinutes = 90
    public static let streakChoices = [45, 60, 75, 90, 120]
    /// A gap this long without use counts as a break.
    public static let restSeconds = 5 * 60
    public static let laterMinutes = 15
    public static let retryMinutes = 25
    public static let maxIgnored = 2

    public var enabled = true
    public var streakMinutes = BreakCoach.defaultStreakMinutes
    /// When the current streak started; nil before the first use.
    public var streakStart: Date?
    /// The last second someone was at the Mac.
    public var lastActive: Date?
    /// The reminder stays quiet until then.
    public var snoozedUntil: Date?
    /// Reminders in this streak that closed without an answer.
    public var ignored = 0
    /// "Not today": quiet for the rest of that day.
    public var pausedDay: DayKey?
    /// Index into `Move.all` of the next move to suggest.
    public var nextMove = 0
    /// Finished moves of the last 14 days.
    public var log: [MoveEntry] = []

    public init() {}

    /// The move the next reminder suggests.
    public var move: Move { Move.all[((nextMove % Move.all.count) + Move.all.count) % Move.all.count] }

    /// Someone was at the Mac for the second ending at `now`.
    public mutating func active(at now: Date) {
        if let last = lastActive, now.timeIntervalSince(last) < TimeInterval(Self.restSeconds), streakStart != nil {
            lastActive = max(last, now)
            return
        }
        startStreak(at: now)
    }

    /// Seconds of the current streak as of `now`. 0 once the owner has been away for a break.
    public func streakSeconds(at now: Date) -> Int {
        guard let start = streakStart, let last = lastActive else { return 0 }
        if now.timeIntervalSince(last) >= TimeInterval(Self.restSeconds) { return 0 }
        return max(0, Int(now.timeIntervalSince(start)))
    }

    /// True when the streak has passed the threshold and nothing silences it.
    public func isDue(at now: Date, calendar: Calendar = .current) -> Bool {
        guard enabled, streakSeconds(at: now) >= streakMinutes * 60 else { return false }
        if let pausedDay, pausedDay == DayKey.of(now, calendar: calendar) { return false }
        return true
    }

    /// True when the floating panel should show now (the app still holds it during focus or a call).
    public func wantsPanel(at now: Date, calendar: Calendar = .current) -> Bool {
        guard isDue(at: now, calendar: calendar), ignored < Self.maxIgnored else { return false }
        if let snoozedUntil, now < snoozedUntil { return false }
        return true
    }

    /// True when the menu bar should carry the quiet "time to move" mark.
    public func wantsMark(at now: Date, calendar: Calendar = .current) -> Bool {
        isDue(at: now, calendar: calendar)
    }

    /// The panel is on screen. Until it is answered, it counts as unanswered.
    public mutating func shown(at now: Date) {
        snoozedUntil = now.addingTimeInterval(TimeInterval(Self.retryMinutes * 60))
    }

    /// The panel closed without an answer.
    public mutating func ignore(at now: Date) {
        ignored += 1
        snoozedUntil = now.addingTimeInterval(TimeInterval(Self.retryMinutes * 60))
    }

    /// "Later": ask again in 15 minutes.
    public mutating func later(at now: Date) {
        snoozedUntil = now.addingTimeInterval(TimeInterval(Self.laterMinutes * 60))
    }

    /// "Not today": quiet until the next 04:00 day.
    public mutating func pauseToday(at now: Date, calendar: Calendar = .current) {
        pausedDay = DayKey.of(now, calendar: calendar)
    }

    /// "I did it": logs the suggested move and starts a new streak.
    public mutating func done(at now: Date) {
        log.append(MoveEntry(at: now, moveID: move.id))
        nextMove = (nextMove + 1) % Move.all.count
        let cutoff = now.addingTimeInterval(-14 * 86_400)
        log.removeAll { $0.at < cutoff }
        startStreak(at: now)
    }

    /// "Another": the next move in the rotation, without logging one.
    public mutating func swap() {
        nextMove = (nextMove + 1) % Move.all.count
    }

    /// Finished moves on `day`.
    public func moves(on day: DayKey, calendar: Calendar = .current) -> Int {
        log.filter { DayKey.of($0.at, calendar: calendar) == day }.count
    }

    /// Finished moves since `date`.
    public func moves(since date: Date) -> Int {
        log.filter { $0.at >= date }.count
    }

    private mutating func startStreak(at now: Date) {
        streakStart = now
        lastActive = now
        snoozedUntil = nil
        ignored = 0
    }

    // A missing key falls back to its default, so a new field never loses the saved state.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        streakMinutes = try c.decodeIfPresent(Int.self, forKey: .streakMinutes) ?? Self.defaultStreakMinutes
        streakStart = try c.decodeIfPresent(Date.self, forKey: .streakStart)
        lastActive = try c.decodeIfPresent(Date.self, forKey: .lastActive)
        snoozedUntil = try c.decodeIfPresent(Date.self, forKey: .snoozedUntil)
        ignored = try c.decodeIfPresent(Int.self, forKey: .ignored) ?? 0
        pausedDay = try c.decodeIfPresent(DayKey.self, forKey: .pausedDay)
        nextMove = try c.decodeIfPresent(Int.self, forKey: .nextMove) ?? 0
        log = try c.decodeIfPresent([MoveEntry].self, forKey: .log) ?? []
    }
}
