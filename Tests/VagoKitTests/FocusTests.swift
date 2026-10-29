import Foundation
import Testing
@testable import VagoKit

@Suite("Focus session")
struct FocusTests {
    let start = at("2026-10-29 10:00")

    func session(_ minutes: Int = 25) -> FocusSession { FocusSession(start: start, minutes: minutes) }

    @Test(arguments: [
        (0.0, "🌱"), (374.0, "🌱"), (375.0, "🌿"), (749.0, "🌿"), (750.0, "🪴"),
        (1125.0, "🪴"), (1499.0, "🪴"), (1500.0, "🌳"), (99_999.0, "🌳"),
    ])
    func stagesByElapsedFraction(elapsed: Double, emoji: String) {
        // 25 minutes = 1500 s: 25% = 375 s, 50% = 750 s, 100% = 1500 s.
        #expect(session().stage(at: start.addingTimeInterval(elapsed)) == emoji)
    }

    @Test func aFiftyMinuteSessionScalesTheStages() {
        let s = session(50)                                                    // 3000 s: 25% = 750 s
        #expect(s.stage(at: start.addingTimeInterval(12 * 60)) == "🌱")
        #expect(s.stage(at: start.addingTimeInterval(13 * 60)) == "🌿")
        #expect(s.stage(at: start.addingTimeInterval(25 * 60)) == "🪴")
        #expect(s.stage(at: start.addingTimeInterval(50 * 60)) == "🌳")
    }

    @Test func aClockBeforeTheStartShowsASeedling() {
        #expect(session().stage(at: start.addingTimeInterval(-30)) == "🌱")
    }

    @Test func finishingGrowsATree() {
        var s = session()
        s.tick(bucket: .productive, seconds: 1, now: start.addingTimeInterval(1499))
        #expect(s.state == .growing)
        s.tick(bucket: .productive, seconds: 1, now: start.addingTimeInterval(1500))
        #expect(s.state == .grown)
        #expect(s.endedAt == s.end)
        #expect(s.stage(at: start.addingTimeInterval(1500)) == "🌳")
    }

    @Test func sixtySecondsOfDistractionIsStillFine() {
        var s = session()
        s.tick(bucket: .procrastination, seconds: 60, now: start.addingTimeInterval(100))
        #expect(s.state == .growing)
        #expect(s.distractedSeconds == 60)
    }

    @Test func moreThanSixtySecondsWiltsTheTree() {
        var s = session()
        s.tick(bucket: .procrastination, seconds: 30, now: start.addingTimeInterval(100))
        s.tick(bucket: .procrastination, seconds: 31, now: start.addingTimeInterval(131))
        #expect(s.state == .wilted)
        #expect(s.stage(at: start.addingTimeInterval(131)) == "🥀")
        #expect(s.stage(at: start.addingTimeInterval(5000)) == "🥀")           // stays wilted past the end
    }

    @Test func ambiguousUseDistractsToo() {
        var s = session()
        s.tick(bucket: .ambiguous, seconds: 61, now: start.addingTimeInterval(100))
        #expect(s.state == .wilted)
    }

    @Test func workAndNeutralUseDoNotDistract() {
        var s = session()
        s.tick(bucket: .productive, seconds: 500, now: start.addingTimeInterval(500))
        s.tick(bucket: .neutral, seconds: 500, now: start.addingTimeInterval(1000))
        #expect(s.distractedSeconds == 0)
        #expect(s.state == .growing)
    }

    @Test func aWiltedSessionStaysWilted() {
        var s = session()
        s.tick(bucket: .procrastination, seconds: 61, now: start.addingTimeInterval(200))
        let wilted = s
        s.tick(bucket: .productive, seconds: 5000, now: start.addingTimeInterval(6000))
        #expect(s == wilted)
    }

    @Test func aGrownTreeCannotWilt() {
        var s = session()
        s.tick(bucket: .productive, seconds: 1, now: start.addingTimeInterval(1500))
        s.tick(bucket: .procrastination, seconds: 300, now: start.addingTimeInterval(1800))
        #expect(s.state == .grown)
        #expect(s.distractedSeconds == 0)
    }

    @Test func wiltingBeatsFinishingOnTheSameTick() {
        var s = session()
        s.tick(bucket: .procrastination, seconds: 61, now: start.addingTimeInterval(1500))
        #expect(s.state == .wilted)
    }

    @Test func focusTimeCountsUpToTheWilt() {
        var s = session()
        #expect(s.focusSeconds(at: start.addingTimeInterval(600)) == 600)      // still growing
        s.tick(bucket: .procrastination, seconds: 61, now: start.addingTimeInterval(300))
        #expect(s.focusSeconds(at: start.addingTimeInterval(900)) == 300)      // frozen at the wilt
    }

    @Test func aFinishedSessionCountsItsFullLength() {
        var s = session()
        s.tick(bucket: .productive, seconds: 1, now: start.addingTimeInterval(1600))
        #expect(s.focusSeconds(at: start.addingTimeInterval(9000)) == 1500)
    }

    @Test func abandoningKeepsTheTimeSoFar() {
        var s = session()
        s.abandon(now: start.addingTimeInterval(420))
        #expect(s.state == .abandoned)
        #expect(s.focusSeconds(at: start.addingTimeInterval(9000)) == 420)
        #expect(s.stage(at: start.addingTimeInterval(9000)) == "🥀")
    }

    @Test func remainingTimeCountsDown() {
        let s = session()
        #expect(s.remaining(at: start.addingTimeInterval(300)) == 1200)
        #expect(s.remaining(at: start.addingTimeInterval(9000)) == 0)
    }

    @Test func roundTripsThroughJSON() throws {
        var s = session(50)
        s.tick(bucket: .procrastination, seconds: 10, now: start.addingTimeInterval(20))
        let back = try JSONDecoder().decode(FocusSession.self, from: JSONEncoder().encode(s))
        #expect(back == s)
    }
}
