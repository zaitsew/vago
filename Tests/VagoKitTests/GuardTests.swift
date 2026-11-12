import Foundation
import Testing
@testable import VagoKit

@Suite("Guard")
struct GuardTests {
    // 2026-11-12 is a Thursday; 14 is Saturday, 15 Sunday.
    let insta = GuardedPlace(name: "Instagram", host: "instagram.com", mode: .pause)
    let tg = GuardedPlace(name: "Telegram", bundleID: "ru.keepcoder.Telegram", mode: .block)

    func list(_ places: [GuardedPlace], enabled: Bool = true, budget: Int = 30) -> GuardList {
        GuardList(places: places, budgetMinutes: budget, enabled: enabled)
    }

    func added(_ l: inout GuardList, _ p: GuardedPlace) -> Bool { l.add(p) }

    func check(_ a: GuardAction, _ b: GuardAction) { #expect(a == b) }

    func tick(_ s: inout GuardState, _ o: ActivitySample?, _ l: GuardList, _ now: Date, isWork: Bool = false, used: Int = 0) -> GuardAction {
        s.tick(o, list: l, isWork: isWork, usedSeconds: used, now: now, calendar: utc)
    }

    // MARK: matching

    @Test func hostMatchesSubdomainsAndWww() {
        #expect(insta.matches(web("https://www.instagram.com/reels")))
        #expect(insta.matches(web("https://m.instagram.com/")))
        #expect(!insta.matches(web("https://notinstagram.com/")))
        #expect(!insta.matches(app("com.apple.Safari")))
    }

    @Test func bundleMatchesIgnoringCase() {
        #expect(tg.matches(app("RU.KEEPCODER.TELEGRAM")))
        #expect(!tg.matches(app("net.whatsapp.WhatsApp")))
    }

    @Test func aPlaceWithNeitherMatchesNothing() {
        let empty = GuardedPlace(name: "Nothing", host: "  ", bundleID: "")
        #expect(!empty.matches(web("https://instagram.com/")))
        #expect(!empty.matches(app("com.apple.Safari")))
    }

    @Test func aPlaceWithHostAndBundleMatchesEither() {
        let both = GuardedPlace(name: "X", host: "x.com", bundleID: "com.atebits.Tweetie2")
        #expect(both.matches(web("https://x.com/home")))
        #expect(both.matches(app("com.atebits.Tweetie2")))
    }

    // MARK: list

    @Test func addRefusesAFourthPlace() {
        var l = GuardList()
        #expect(added(&l, GuardedPlace(name: "a", host: "a.com")))
        #expect(added(&l, GuardedPlace(name: "b", host: "b.com")))
        #expect(added(&l, GuardedPlace(name: "c", bundleID: "c.app")))
        #expect(!added(&l, GuardedPlace(name: "d", host: "d.com")))
        #expect(l.places.count == 3)
    }

    @Test func addRefusesDuplicates() {
        var l = GuardList()
        #expect(added(&l, insta))
        #expect(!added(&l, GuardedPlace(name: "Insta again", host: "WWW.Instagram.com")))
        #expect(added(&l, tg))
        #expect(!added(&l, GuardedPlace(name: "TG", bundleID: "RU.keepcoder.telegram")))
        #expect(l.places.count == 2)
    }

    @Test func removeAndSetMode() {
        var l = list([insta, tg])
        l.setMode(insta.id, .block)
        #expect(l.places[0].mode == .block)
        l.remove(tg.id)
        #expect(l.places == [GuardedPlace(id: insta.id, name: "Instagram", host: "instagram.com", mode: .block)])
        l.setMode(UUID(), .pause)   // unknown id: no change
        #expect(l.places.count == 1)
    }

    @Test func listRoundTripsThroughJSON() throws {
        let l = list([insta, tg])
        let back = try JSONDecoder().decode(GuardList.self, from: JSONEncoder().encode(l))
        #expect(back == l)
    }

    // MARK: proposals

    func session(_ sample: ActivitySample, seconds: Int, guess: Bucket = .procrastination) -> Session {
        Session(start: at("2026-11-12 10:00"), seconds: seconds, sample: ActivitySampleRecord(sample), guess: guess, reason: "")
    }

    @Test func proposalsRankByTotalSeconds() {
        let sessions = [
            session(web("https://www.reddit.com/r/swift"), seconds: 300),
            session(web("https://reddit.com/"), seconds: 400),
            session(web("https://www.instagram.com/"), seconds: 600, guess: .ambiguous),
            session(app("com.netflix.Netflix", name: "Netflix"), seconds: 100),
            session(web("https://news.ycombinator.com/"), seconds: 50),
        ]
        let p = GuardList.proposals(from: sessions, limit: 3)
        #expect(p.map(\.name) == ["reddit.com", "instagram.com", "Netflix"])
        #expect(p[0].host == "reddit.com" && p[0].bundleID == nil)
        #expect(p[2].bundleID == "com.netflix.Netflix" && p[2].host == nil)
        #expect(p.allSatisfy { $0.mode == .pause })
    }

    @Test func proposalsSkipProductiveAndOtherGuesses() {
        let sessions = [
            session(web("https://github.com/"), seconds: 9000, guess: .ambiguous),
            session(web("https://www.instagram.com/direct/inbox"), seconds: 8000, guess: .ambiguous),
            session(web("https://docs.google.com/"), seconds: 7000, guess: .procrastination),
            session(web("https://reddit.com/"), seconds: 7000, guess: .productive),
            session(web("https://reddit.com/"), seconds: 7000, guess: .neutral),
            session(web("https://tiktok.com/"), seconds: 10),
        ]
        #expect(GuardList.proposals(from: sessions).map(\.name) == ["tiktok.com"])
    }

    @Test func proposalsHonourTheLimit() {
        let sessions = (1...5).map { session(web("https://site\($0).com/"), seconds: $0 * 10) }
        #expect(GuardList.proposals(from: sessions, limit: 2).map(\.name) == ["site5.com", "site4.com"])
        #expect(GuardList.proposals(from: []).isEmpty)
    }

    // MARK: work hours

    @Test func workHoursWeekdayAndWeekend() {
        let h = WorkHours()
        #expect(h.contains(at("2026-11-12 09:00"), calendar: utc))
        #expect(h.contains(at("2026-11-12 17:59"), calendar: utc))
        #expect(!h.contains(at("2026-11-12 18:00"), calendar: utc))
        #expect(!h.contains(at("2026-11-12 08:59"), calendar: utc))
        #expect(!h.contains(at("2026-11-14 12:00"), calendar: utc))   // Saturday
        #expect(!h.contains(at("2026-11-15 12:00"), calendar: utc))   // Sunday
    }

    @Test func workHoursCrossingMidnight() {
        let h = WorkHours(start: 22 * 60, end: 6 * 60, weekdays: [6])   // Friday night
        #expect(h.contains(at("2026-11-13 23:00"), calendar: utc))      // Friday 23:00
        #expect(h.contains(at("2026-11-14 05:59"), calendar: utc))      // Saturday early: Friday's block
        #expect(!h.contains(at("2026-11-14 06:00"), calendar: utc))
        #expect(!h.contains(at("2026-11-14 23:00"), calendar: utc))     // Saturday night: not listed
        #expect(!h.contains(at("2026-11-13 05:00"), calendar: utc))     // Friday early: Thursday's block
    }

    @Test func sundayEarlyMorningBelongsToSaturday() {
        let h = WorkHours(start: 22 * 60, end: 2 * 60, weekdays: [7])
        #expect(h.contains(at("2026-11-15 01:00"), calendar: utc))
        #expect(!h.contains(at("2026-11-16 01:00"), calendar: utc))
    }

    @Test func blockEnd() {
        let h = WorkHours()
        #expect(h.blockEnd(containing: at("2026-11-12 10:00"), calendar: utc) == at("2026-11-12 18:00"))
        #expect(h.blockEnd(containing: at("2026-11-12 19:00"), calendar: utc) == nil)
        let night = WorkHours(start: 22 * 60, end: 6 * 60, weekdays: [6])
        #expect(night.blockEnd(containing: at("2026-11-13 23:00"), calendar: utc) == at("2026-11-14 06:00"))
        #expect(night.blockEnd(containing: at("2026-11-14 01:00"), calendar: utc) == at("2026-11-14 06:00"))
    }

    // MARK: pause

    @Test func pauseOnEntryOnly() {
        var s = GuardState()
        let l = list([insta])
        let o = web("https://instagram.com/")
        let t = at("2026-11-14 12:00")
        check(tick(&s, o, l, t), .pause(insta, overBudget: false))
        check(tick(&s, o, l, t.addingTimeInterval(1)), .none)
        check(tick(&s, o, l, t.addingTimeInterval(2)), .none)
        #expect(s.pausesShown[insta.id] == 1)
        #expect(s.front == insta.id)
    }

    @Test func leavingAndReturningPausesAgain() {
        var s = GuardState()
        let l = list([insta])
        let t = at("2026-11-14 12:00")
        _ = tick(&s, web("https://instagram.com/"), l, t)
        check(tick(&s, web("https://github.com/"), l, t.addingTimeInterval(1)), .none)
        #expect(s.front == nil)
        check(tick(&s, web("https://instagram.com/"), l, t.addingTimeInterval(2)), .pause(insta, overBudget: false))
        check(tick(&s, nil, l, t.addingTimeInterval(3)), .none)
        #expect(s.front == nil)
    }

    @Test func aPassSilencesThePauseAndExpiryPausesOnce() {
        var s = GuardState()
        let l = list([insta])
        let o = web("https://instagram.com/")
        let t = at("2026-11-14 12:00")
        _ = tick(&s, o, l, t)
        s.grantPass(insta.id, now: t.addingTimeInterval(5))
        #expect(s.passesTaken[insta.id] == 1)
        #expect(s.hasPass(insta.id, now: t.addingTimeInterval(5 + 299)))
        check(tick(&s, o, l, t.addingTimeInterval(5 + 299)), .none)
        #expect(!s.hasPass(insta.id, now: t.addingTimeInterval(5 + 300)))
        check(tick(&s, o, l, t.addingTimeInterval(5 + 300)), .pause(insta, overBudget: false))
        check(tick(&s, o, l, t.addingTimeInterval(5 + 301)), .none)
        #expect(s.pausesShown[insta.id] == 2)
    }

    @Test func closeThenReopenPausesAgain() {
        var s = GuardState()
        let l = list([insta])
        let o = web("https://instagram.com/")
        let t = at("2026-11-14 12:00")
        _ = tick(&s, o, l, t)
        s.closed(insta.id, now: t.addingTimeInterval(5))
        #expect(s.closes[insta.id] == 1)
        #expect(s.front == nil)
        check(tick(&s, o, l, t.addingTimeInterval(6)), .pause(insta, overBudget: false))
    }

    @Test func overBudgetFlag() {
        var s = GuardState()
        let l = list([insta], budget: 30)
        let o = web("https://instagram.com/")
        let t = at("2026-11-14 12:00")
        check(tick(&s, o, l, t, used: 1799), .pause(insta, overBudget: false))
        s.closed(insta.id, now: t)
        check(tick(&s, o, l, t.addingTimeInterval(1), used: 1800), .pause(insta, overBudget: true))
    }

    @Test func disabledUnmatchedAndWorkAreNeverGuarded() {
        let o = web("https://instagram.com/")
        let t = at("2026-11-14 12:00")
        var s = GuardState()
        check(tick(&s, o, list([insta], enabled: false), t), .none)
        check(tick(&s, web("https://github.com/"), list([insta]), t), .none)
        check(tick(&s, o, list([insta]), t, isWork: true), .none)
        #expect(s.front == nil)
        #expect(s.pausesShown.isEmpty)
        // After the owner switches the place back from work, entry pauses.
        check(tick(&s, o, list([insta]), t.addingTimeInterval(1)), .pause(insta, overBudget: false))
    }

    // MARK: block

    @Test func blockEveryTickInsideWorkHours() {
        var s = GuardState()
        let l = list([tg])
        let o = app("ru.keepcoder.Telegram", name: "Telegram")
        let t = at("2026-11-12 10:00")
        for i in 0..<3 {
            check(tick(&s, o, l, t.addingTimeInterval(Double(i))), .block(tg, until: at("2026-11-12 18:00")))
        }
        #expect(s.pausesShown.isEmpty)
    }

    @Test func blockBecomesPauseOutsideWorkHours() {
        var s = GuardState()
        let l = list([tg])
        let o = app("ru.keepcoder.Telegram", name: "Telegram")
        let t = at("2026-11-12 19:00")
        check(tick(&s, o, l, t), .pause(tg, overBudget: false))
        check(tick(&s, o, l, t.addingTimeInterval(1)), .none)
        let weekend = at("2026-11-14 11:00")
        s.closed(tg.id, now: weekend)
        check(tick(&s, o, l, weekend), .pause(tg, overBudget: false))
    }

    @Test func unlockLiftsTheBlockForFiveMinutes() {
        var s = GuardState()
        let l = list([tg])
        let o = app("ru.keepcoder.Telegram", name: "Telegram")
        let t = at("2026-11-12 10:00")
        check(tick(&s, o, l, t), .block(tg, until: at("2026-11-12 18:00")))
        s.unlock(tg.id, now: t)
        #expect(s.unlocks[tg.id] == 1)
        #expect(s.passesTaken[tg.id] == nil)
        check(tick(&s, o, l, t.addingTimeInterval(299)), .none)
        check(tick(&s, o, l, t.addingTimeInterval(300)), .block(tg, until: at("2026-11-12 18:00")))
    }

    // MARK: day reset

    @Test func aNewDayResetsCountersAndPasses() {
        var s = GuardState()
        let l = list([insta])
        let o = web("https://instagram.com/")
        let t = at("2026-11-14 12:00")
        _ = tick(&s, o, l, t)
        s.grantPass(insta.id, now: t)
        s.closed(insta.id, now: t)
        #expect(s.day == DayKey.of(t, calendar: utc))
        let next = at("2026-11-15 12:00")
        #expect(s.hasPass(insta.id, now: t.addingTimeInterval(1)))
        check(tick(&s, o, l, next), .pause(insta, overBudget: false))
        #expect(s.day == DayKey.of(next, calendar: utc))
        #expect(s.passes.isEmpty)
        #expect(s.closes.isEmpty && s.passesTaken.isEmpty && s.unlocks.isEmpty)
        #expect(s.pausesShown[insta.id] == 1)
    }

    @Test func aPlaceStillInFrontAtTheDayChangePausesAgain() {
        var s = GuardState()
        let l = list([insta])
        let o = web("https://instagram.com/")
        let late = at("2026-11-14 03:58")      // the Vago day ends at 04:00
        check(tick(&s, o, l, late), .pause(insta, overBudget: false))
        s.grantPass(insta.id, now: late)
        check(tick(&s, o, l, late.addingTimeInterval(60)), .none)
        check(tick(&s, o, l, at("2026-11-14 04:01")), .pause(insta, overBudget: false))
    }

    @Test func blockEndKeepsWallClockTimeAcrossDST() throws {
        var madrid = Calendar(identifier: .gregorian)
        madrid.timeZone = try #require(TimeZone(identifier: "Europe/Madrid"))
        // 2026-03-29 is the spring change in Madrid; a Sunday block 09:00–18:00.
        let hours = WorkHours(start: 540, end: 1080, weekdays: [1])
        let noon = try #require(madrid.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 12)))
        let end = try #require(hours.blockEnd(containing: noon, calendar: madrid))
        #expect(madrid.component(.hour, from: end) == 18)
        #expect(madrid.component(.minute, from: end) == 0)
    }

    @Test func stateRoundTripsThroughJSON() throws {
        var s = GuardState()
        _ = tick(&s, web("https://instagram.com/"), list([insta]), at("2026-11-14 12:00"))
        s.grantPass(insta.id, now: at("2026-11-14 12:00"))
        let back = try JSONDecoder().decode(GuardState.self, from: JSONEncoder().encode(s))
        #expect(back == s)
    }
}
