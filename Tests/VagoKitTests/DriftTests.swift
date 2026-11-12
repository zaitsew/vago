import Foundation
import Testing
@testable import VagoKit

@Suite("Drift watch")
struct DriftTests {
    let now = at("2026-11-12 10:00")

    /// Feeds `seconds` ticks of `mode`; returns how many times it fired.
    @discardableResult
    func feed(_ w: inout DriftWatch, _ mode: Mode, _ seconds: Int, guarded: Bool = false) -> Int {
        var fired = 0
        for _ in 0..<seconds where w.tick(mode, guarded: guarded, now: now) { fired += 1 }
        return fired
    }

    @Test func modeFromBucket() {
        #expect(Mode(.productive) == .work)
        #expect(Mode(.procrastination) == .procrastination)
        #expect(Mode(.ambiguous) == .procrastination)
        #expect(Mode(.neutral) == .neutral)
    }

    @Test func firesAfterWorkThenDwell() {
        var w = DriftWatch()
        feed(&w, .work, 60)
        #expect(feed(&w, .procrastination, 59) == 0)
        #expect(feed(&w, .procrastination, 1) == 1)
    }

    @Test func doesNotFireWithoutEnoughWork() {
        var w = DriftWatch()
        feed(&w, .work, 59)
        #expect(feed(&w, .procrastination, 300) == 0)
        var fresh = DriftWatch()
        #expect(feed(&fresh, .procrastination, 300) == 0)
    }

    @Test func neutralSecondsNeitherBreakNorExtendTheStreak() {
        var w = DriftWatch()
        feed(&w, .work, 60)
        feed(&w, .procrastination, 30)
        feed(&w, .neutral, 500)
        #expect(feed(&w, .procrastination, 29) == 0)
        #expect(feed(&w, .procrastination, 1) == 1)
    }

    @Test func workBreaksTheStreak() {
        var w = DriftWatch()
        feed(&w, .work, 60)
        feed(&w, .procrastination, 59)
        feed(&w, .work, 1)
        #expect(feed(&w, .procrastination, 59) == 0)
        #expect(feed(&w, .procrastination, 1) == 1)
    }

    @Test func guardedPlacesNeverFireAndDoNotGrowTheStreak() {
        var w = DriftWatch()
        feed(&w, .work, 60)
        #expect(feed(&w, .procrastination, 600, guarded: true) == 0)
        #expect(feed(&w, .procrastination, 59) == 0)
        #expect(feed(&w, .procrastination, 1) == 1)
    }

    @Test func firesOncePerDriftAndNeedsWorkToRearm() {
        var w = DriftWatch()
        feed(&w, .work, 120)
        #expect(feed(&w, .procrastination, 600) == 1)
        // Back to procrastination after a short work spell: not armed.
        feed(&w, .work, 30)
        #expect(feed(&w, .procrastination, 120) == 0)
        // A full arm period of work arms it again.
        feed(&w, .work, 60)
        #expect(feed(&w, .procrastination, 120) == 1)
    }

    @Test func idleResetsTheStreakButKeepsTheArming() {
        var w = DriftWatch()
        feed(&w, .work, 60)
        feed(&w, .procrastination, 59)
        w.idle()
        #expect(feed(&w, .procrastination, 59) == 0)
        #expect(feed(&w, .procrastination, 1) == 1)
    }
}
