import Foundation
import Testing
@testable import VagoKit

@Suite("Classifier")
struct ClassifierTests {
    let reel = web("https://www.instagram.com/", title: "Instagram")
    let clock = TestClock(at("2026-10-29 10:00"))

    func make(_ judge: Judge?, rules: RuleBook = builtIn) -> Classifier {
        let clock = self.clock
        return Classifier(rules: rules, judge: judge, goals: "ship Vago", now: { clock.now }, calendar: utc)
    }

    @Test func rulesDecideWithoutTheJudge() async {
        let judge = StubJudge(workVerdict)
        let c = make(judge)
        let r = await c.classify(web("https://instagram.com/reels/1"))
        #expect(r.bucket == .procrastination && !r.unclear)
        #expect(await judge.calls == 0)
    }

    @Test func productiveAndNeutralRulesAreClear() async {
        let c = make(nil)
        let work = await c.classify(app("com.apple.dt.Xcode"))
        let neutral = await c.classify(app("com.apple.finder"))
        let unknown = await c.classify(app("com.example.unknown"))      // no judge: unknown stays neutral
        #expect(work.bucket == .productive && !work.unclear)
        #expect(neutral.bucket == .neutral && !neutral.unclear)
        #expect(unknown.bucket == .neutral && !unknown.unclear && unknown.source == .fallback)
    }

    @Test func highConfidenceVerdictIsUsed() async {
        let c = make(StubJudge(workVerdict))
        let r = await c.classify(reel)
        #expect(r.bucket == .productive)
        #expect(!r.unclear)
        #expect(r.reason == "work chat")
    }

    @Test func confidenceExactlyAtTheLineIsUsed() async {
        let c = make(StubJudge(Verdict(bucket: .productive, confidence: 0.7, reason: "edge")))
        #expect(await c.classify(reel).bucket == .productive)
    }

    @Test func lowConfidenceIsNeutralAndUnclear() async {
        let c = make(StubJudge(Verdict(bucket: .productive, confidence: 0.69, reason: "maybe work")))
        let r = await c.classify(reel)
        #expect(r.bucket == .neutral)
        #expect(r.unclear && r.verdict == nil && r.ambiguous)
    }

    @Test func noJudgeCountsAsProcrastinationAndIsUnclear() async {
        let r = await make(nil).classify(reel)
        #expect(r.bucket == .procrastination)
        #expect(r.unclear)
    }

    @Test func nilVerdictIsNeutralAndIsNotCached() async {
        let judge = StubJudge(nil)
        let c = make(judge)
        let first = await c.classify(reel)
        _ = await c.classify(reel)
        #expect(first.bucket == .neutral && first.unclear)
        #expect(await judge.calls == 2)                        // a failed call is retried
    }

    @Test func aJudgeThatAnswersAmbiguousIsUnclear() async {
        let c = make(StubJudge(Verdict(bucket: .ambiguous, confidence: 0.95, reason: "no idea")))
        let r = await c.classify(reel)
        #expect(r.bucket == .neutral && r.unclear)
    }

    @Test func theJudgeGetsTheGoals() async {
        let judge = StubJudge(workVerdict)
        _ = await make(judge).classify(reel)
        #expect(await judge.lastGoals == "ship Vago")
    }

    @Test func sameSiteAndTitleHitsTheCache() async {
        let judge = StubJudge(workVerdict)
        let c = make(judge)
        _ = await c.classify(web("https://www.instagram.com/", title: "Instagram  Team"))
        _ = await c.classify(web("https://instagram.com/", title: " instagram team "))   // host and title normalize
        _ = await c.classify(web("https://www.instagram.com/", title: "Instagram Team"))
        #expect(await judge.calls == 1)
    }

    @Test func aNewTitleAsksTheJudgeAgain() async {
        let judge = StubJudge(workVerdict)
        let c = make(judge)
        _ = await c.classify(web("https://www.instagram.com/", title: "Inbox"))
        _ = await c.classify(web("https://www.instagram.com/", title: "Feed"))
        #expect(await judge.calls == 2)
    }

    @Test func appsCacheByBundleAndTitle() async {
        let judge = StubJudge(workVerdict)
        let c = make(judge)
        let chat = app("ru.keepcoder.Telegram", title: "Acme")
        _ = await c.classify(chat)
        _ = await c.classify(chat)
        #expect(await judge.calls == 1)
    }

    @Test func cacheResetsWhenTheDayChanges() async {
        let judge = StubJudge(workVerdict)
        let c = make(judge)
        _ = await c.classify(reel)
        clock.now = at("2026-10-30 03:59")                      // still the 29th
        _ = await c.classify(reel)
        #expect(await judge.calls == 1)
        clock.now = at("2026-10-30 04:00")                      // the 30th
        _ = await c.classify(reel)
        #expect(await judge.calls == 2)
    }

    @Test func concurrentCallsShareOneJudgeCall() async {
        let judge = StubJudge(workVerdict, delay: .milliseconds(50))
        let c = make(judge)
        let o = reel
        let results = await withTaskGroup(of: Classification.self) { group in
            for _ in 0..<5 { group.addTask { await c.classify(o) } }
            return await group.reduce(into: []) { $0.append($1) }
        }
        #expect(results.count == 5)
        #expect(results.allSatisfy { $0.bucket == .productive })
        #expect(await judge.calls == 1)
    }

    @Test func updatedRulesApplyAtOnce() async {
        let c = make(StubJudge(workVerdict))
        var book = builtIn
        book.learn(from: web("https://instagram.com/reels/1"), bucket: .productive)
        await c.update(rules: book)
        let r = await c.classify(web("https://instagram.com/reels/1"))
        #expect(r.bucket == .productive && !r.unclear)
    }

    // MARK: Autonomy

    @Test func unknownPlacesGoToTheJudge() async {
        let judge = StubJudge(Verdict(bucket: .procrastination, confidence: 0.9, reason: "a game"))
        let r = await make(judge).classify(app("com.example.game", title: "Level 3"))
        #expect(r.bucket == .procrastination && !r.unclear && r.source == .judge && !r.ambiguous)
        #expect(await judge.lastContext?.ambiguous == false)
    }

    @Test func theJudgeCannotOverrideAWasteRule() async {
        let judge = StubJudge(workVerdict)
        let r = await make(judge).classify(web("https://www.youtube.com/shorts/abc", title: "Swift tips"))
        #expect(r.bucket == .procrastination && r.source == .rule)
        #expect(await judge.calls == 0)
    }

    @Test func theJudgeGetsTheContext() async {
        let judge = StubJudge(workVerdict)
        _ = await make(judge).classify(reel, context: JudgeContext(hour: 11, secondsInFront: 40, previous: "Xcode (work)"))
        let ctx = await judge.lastContext
        #expect(ctx?.hour == 11 && ctx?.previous == "Xcode (work)" && ctx?.ambiguous == true)
    }

    @Test func aHeldJudgeCannotCallAmbiguousUseWork() async {
        let c = make(StubJudge(workVerdict))
        await c.setJudgeTrusted(false)
        let r = await c.classify(reel)
        #expect(r.bucket == .neutral && r.unclear && r.verdict == .productive)
        #expect(r.reason.hasPrefix("held: "))
    }

    @Test func aHeldJudgeStillDecidesUnknownPlaces() async {
        let c = make(StubJudge(workVerdict))
        await c.setJudgeTrusted(false)
        #expect(await c.classify(app("com.example.editor")).bucket == .productive)
    }

    @Test func newGoalsClearTheCache() async {
        let judge = StubJudge(workVerdict)
        let c = make(judge)
        _ = await c.classify(reel)
        await c.update(goals: "learn Spanish")
        _ = await c.classify(reel)
        #expect(await judge.calls == 2)
        #expect(await judge.lastGoals == "learn Spanish")
    }

    @Test func aVerdictAskedUnderOldGoalsIsNotCached() async {
        let judge = StubJudge(workVerdict, delay: .milliseconds(80))
        let c = make(judge)
        let o = reel
        let first = Task { await c.classify(o) }
        try? await Task.sleep(for: .milliseconds(20))
        await c.update(goals: "learn Spanish")
        _ = await first.value
        _ = await c.classify(o)
        #expect(await judge.calls == 2)
    }
}
