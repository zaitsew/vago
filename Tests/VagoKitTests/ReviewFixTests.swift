import Foundation
import Testing
@testable import VagoKit

/// Regressions from the PR #1 review.
@Suite("Review fixes")
struct ReviewFixTests {
    @Test func aDayThatSyncsLateStillMovesTheLimit() {
        // Rolled past day 4 while it had no data; the Mac's total for it arrives a day later.
        var l = ledger([40, 40, 40, nil, 10])
        var limit = AdaptiveLimit()
        limit.roll(to: dayAfter([40, 40, 40, nil, 10]), ledger: l)
        #expect(limit.current == 35)
        l.merge(deviceDay(firstDay.adding(days: 3), .mac, procrastination: 10))
        limit.roll(to: dayAfter([40, 40, 40, nil, 10]), ledger: l)
        #expect(limit.current == 30)
    }

    @Test func roundingNeverLiftsTheLimitOverTheMedianCap() {
        // 7-day median 83 + 10 = 93: the limit must not be 95.
        let limit = rolled([120, 120, 120, 83, 83, 83, 83])
        #expect(limit.current <= 93)
        #expect(limit.current % 5 == 0)
    }

    @Test func equalTimestampsMergeTheSameInAnyOrder() {
        let day = DayKey(id: "2026-10-29")
        let a = deviceDay(day, .mac, productive: 10)
        let b = deviceDay(day, .mac, procrastination: 10)
        var ab = Ledger(); ab.merge(a); ab.merge(b)
        var ba = Ledger(); ba.merge(b); ba.merge(a)
        #expect(ab.days == ba.days)
    }

    @Test func distractionAfterTheDeadlineDoesNotWiltAGrownTree() {
        let start = at("2026-10-29 10:00")
        var s = FocusSession(start: start, minutes: 25)
        s.tick(bucket: .procrastination, seconds: 60, now: start.addingTimeInterval(600))
        // The Mac slept through the end; the first tick after waking is a distraction.
        s.tick(bucket: .procrastination, seconds: 1, now: start.addingTimeInterval(26 * 60))
        #expect(s.state == .grown)
        #expect(s.stage(at: start.addingTimeInterval(26 * 60)) == "🌳")
    }
}

@Suite("DeviceDay codec")
struct DeviceDayCodecTests {
    let day = DeviceDay(day: DayKey(id: "2026-10-29"), device: .mac, procrastination: 600, productive: 1200, focus: 300, updatedAt: at("2026-10-29 12:00"))

    @Test func roundTrips() {
        #expect(DeviceDay(encoded: day.encoded()) == day)
    }

    @Test func readsAStringAndNumericDates() throws {
        let numeric = try JSONEncoder().encode(day)
        #expect(DeviceDay(encoded: numeric) == day)
        #expect(DeviceDay(encoded: String(decoding: day.encoded(), as: UTF8.self)) == day)
    }

    @Test func rejectsAnythingElse() {
        #expect(DeviceDay(encoded: 42) == nil)
        #expect(DeviceDay(encoded: Data("nope".utf8)) == nil)
    }
}
