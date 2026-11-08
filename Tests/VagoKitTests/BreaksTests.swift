import Foundation
import Testing
@testable import VagoKit

@Suite("Move breaks")
struct BreaksTests {
    let start = at("2026-11-08 09:00")

    /// A coach that saw use every minute from `start` for `minutes` minutes.
    func coach(minutes: Int, every step: Int = 60) -> BreakCoach {
        var c = BreakCoach()
        for s in stride(from: 0, through: minutes * 60, by: step) {
            c.active(at: start.addingTimeInterval(TimeInterval(s)))
        }
        return c
    }

    func t(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    @Test func notDueBeforeTheThreshold() {
        let c = coach(minutes: 89)
        #expect(c.streakSeconds(at: t(89)) == 89 * 60)
        #expect(!c.isDue(at: t(89)))
    }

    @Test func dueAfterNinetyMinutesNonStop() {
        let c = coach(minutes: 90)
        #expect(c.isDue(at: t(90)))
        #expect(c.wantsPanel(at: t(90)))
    }

    @Test func shortGapsDoNotBreakTheStreak() {
        // Use every 4 minutes: each gap is under the 5-minute rest.
        let c = coach(minutes: 92, every: 4 * 60)
        #expect(c.streakSeconds(at: t(92)) == 92 * 60)
    }

    @Test func fiveMinutesAwayIsABreak() {
        var c = coach(minutes: 80)
        #expect(c.streakSeconds(at: t(85)) == 0)                       // away since minute 80
        c.active(at: t(85))
        #expect(c.streakStart == t(85))
        for m in 86...100 { c.active(at: t(Double(m))) }
        #expect(c.streakSeconds(at: t(100)) == 15 * 60)
        #expect(!c.isDue(at: t(100)))
    }

    @Test func laterAsksAgainInFifteenMinutes() {
        var c = coach(minutes: 90)
        #expect(c.wantsPanel(at: t(90)))
        c.shown(at: t(90))
        c.later(at: t(90))
        for m in 91...105 { c.active(at: t(Double(m))) }
        #expect(!c.wantsPanel(at: t(104)))
        #expect(c.wantsPanel(at: t(105)))
        #expect(c.ignored == 0)
    }

    @Test func anUnansweredPanelRetriesOnceThenOnlyTheMarkStays() {
        var c = coach(minutes: 90)
        c.shown(at: t(90))
        c.ignore(at: t(91))
        for m in 91...180 { c.active(at: t(Double(m))) }
        #expect(!c.wantsPanel(at: t(115)))
        #expect(c.wantsPanel(at: t(116)))                            // 25 minutes after the miss
        c.shown(at: t(116))
        c.ignore(at: t(117))
        #expect(!c.wantsPanel(at: t(180)))                           // two misses: no more panels
        #expect(c.wantsMark(at: t(180)))
    }

    @Test func notTodayIsQuietUntilFourInTheMorning() {
        var c = coach(minutes: 90)
        c.pauseToday(at: t(90), calendar: utc)
        #expect(!c.isDue(at: t(90), calendar: utc))
        #expect(!c.wantsMark(at: t(90), calendar: utc))
        let nextDay = at("2026-11-09 04:30")
        c.active(at: nextDay.addingTimeInterval(-90 * 60))
        for m in stride(from: 89, through: 0, by: -1) { c.active(at: nextDay.addingTimeInterval(TimeInterval(-m * 60))) }
        #expect(c.isDue(at: nextDay, calendar: utc))
    }

    @Test func doneLogsTheMoveAndStartsANewStreak() {
        var c = coach(minutes: 90)
        let first = c.move
        c.shown(at: t(90))
        c.done(at: t(93))
        #expect(c.log == [MoveEntry(at: t(93), moveID: first.id)])
        #expect(c.move != first)
        #expect(c.streakStart == t(93))
        #expect(c.snoozedUntil == nil)
        #expect(c.ignored == 0)
        #expect(!c.isDue(at: t(94)))
        #expect(c.moves(on: DayKey.of(t(93), calendar: utc), calendar: utc) == 1)
    }

    @Test func aBreakClearsTheSnoozeAndTheMisses() {
        var c = coach(minutes: 90)
        c.shown(at: t(90))
        c.ignore(at: t(91))
        c.active(at: t(100))                                          // 9 minutes away
        #expect(c.ignored == 0)
        #expect(c.snoozedUntil == nil)
    }

    @Test func swapMovesThroughTheRotationWithoutLogging() {
        var c = BreakCoach()
        var seen: [String] = []
        for _ in Move.all { seen.append(c.move.id); c.swap() }
        #expect(Set(seen).count == Move.all.count)
        #expect(c.move == Move.all[0])
        #expect(c.log.isEmpty)
    }

    @Test func anOlderInputTimeNeverMovesTheStreakBack() {
        var c = coach(minutes: 10)
        c.active(at: t(8))                                            // last input two minutes ago
        #expect(c.lastActive == t(10))
        #expect(c.streakStart == start)
    }

    @Test func disabledIsNeverDue() {
        var c = coach(minutes: 120)
        c.enabled = false
        #expect(!c.isDue(at: t(120)))
    }

    @Test func aShorterThresholdComesSooner() {
        var c = coach(minutes: 45)
        c.streakMinutes = 45
        #expect(c.isDue(at: t(45)))
    }

    @Test func theLogKeepsFourteenDays() {
        var c = BreakCoach()
        c.done(at: at("2026-10-20 10:00"))
        c.done(at: at("2026-11-08 10:00"))
        #expect(c.log.count == 1)
        #expect(c.moves(since: at("2026-11-01 00:00")) == 1)
    }

    @Test func decodesAnOldFileWithMissingKeys() throws {
        let c = try JSONDecoder().decode(BreakCoach.self, from: Data(#"{"streakMinutes":60}"#.utf8))
        #expect(c.streakMinutes == 60)
        #expect(c.enabled)
        #expect(c.log.isEmpty)
    }

    @Test func roundTripsThroughJSON() throws {
        var c = coach(minutes: 90)
        c.shown(at: t(90))
        c.done(at: t(92))
        let back = try JSONDecoder().decode(BreakCoach.self, from: JSONEncoder().encode(c))
        #expect(back == c)
    }

    @Test func everyMoveSaysHowMuch() {
        for m in Move.all {
            #expect(m.how.contains { $0.isNumber }, "\(m.id) needs reps or seconds")
        }
        #expect(Set(Move.all.map(\.id)).count == Move.all.count)
    }
}
