import Foundation
import Testing
@testable import VagoKit

@Suite("Day")
struct DayTests {
    @Test func fourOClockStartsANewDay() {
        #expect(DayKey.of(at("2026-10-30 03:59"), calendar: utc).id == "2026-10-29")
        #expect(DayKey.of(at("2026-10-30 04:00"), calendar: utc).id == "2026-10-30")
    }

    @Test func lateNightBelongsToTheEveningBefore() {
        #expect(DayKey.of(at("2026-10-30 02:30"), calendar: utc).id == "2026-10-29")
        #expect(DayKey.of(at("2026-10-30 00:00"), calendar: utc).id == "2026-10-29")
        #expect(DayKey.of(at("2026-10-29 23:59"), calendar: utc).id == "2026-10-29")
    }

    @Test func monthAndYearBoundaries() {
        #expect(DayKey.of(at("2026-11-01 02:00"), calendar: utc).id == "2026-10-31")
        #expect(DayKey.of(at("2027-01-01 03:00"), calendar: utc).id == "2026-12-31")
    }

    @Test func usesTheCalendarsTimeZone() {
        var madrid = Calendar(identifier: .gregorian)
        madrid.timeZone = TimeZone(identifier: "Europe/Madrid")!
        let moment = at("2026-10-30 03:30")                     // 03:30 UTC = 04:30 in Madrid (UTC+1)
        #expect(DayKey.of(moment, calendar: utc).id == "2026-10-29")
        #expect(DayKey.of(moment, calendar: madrid).id == "2026-10-30")
    }

    @Test func daysCompareByDate() {
        #expect(DayKey(id: "2026-09-30") < DayKey(id: "2026-10-01"))
        #expect([DayKey(id: "2026-10-02"), DayKey(id: "2026-09-30"), DayKey(id: "2026-10-01")].sorted().map(\.id)
                == ["2026-09-30", "2026-10-01", "2026-10-02"])
    }

    @Test func addingDaysCrossesBoundaries() {
        #expect(DayKey(id: "2026-10-31").adding(days: 1).id == "2026-11-01")
        #expect(DayKey(id: "2026-12-31").adding(days: 1).id == "2027-01-01")
        #expect(DayKey(id: "2026-03-01").adding(days: -1).id == "2026-02-28")
        #expect(DayKey(id: "2028-02-28").adding(days: 1).id == "2028-02-29")
        #expect(DayKey(id: "garbage").adding(days: 1).id == "garbage")
    }

    @Test func roundTripsThroughJSON() throws {
        let key = DayKey(id: "2026-10-29")
        #expect(try JSONDecoder().decode(DayKey.self, from: JSONEncoder().encode(key)) == key)
    }
}

@Suite("Ledger")
struct LedgerTests {
    let day = DayKey(id: "2026-10-29")

    @Test func keyFormat() {
        #expect(Ledger.key(day, .iphone) == "day/2026-10-29/iphone")
        #expect(Ledger.key(day, .mac) == "day/2026-10-29/mac")
    }

    @Test func laterWriteWinsEvenWithSmallerNumbers() {
        var l = Ledger()
        l.merge(deviceDay(day, .mac, procrastination: 20, updated: at("2026-10-29 10:00")))
        l.merge(deviceDay(day, .mac, procrastination: 5, updated: at("2026-10-29 11:00")))
        #expect(l.total(for: day).procrastination == 5 * 60)
    }

    @Test func olderWriteIsIgnored() {
        var l = Ledger()
        l.merge(deviceDay(day, .mac, procrastination: 20, updated: at("2026-10-29 11:00")))
        l.merge(deviceDay(day, .mac, procrastination: 5, updated: at("2026-10-29 10:00")))
        #expect(l.total(for: day).procrastination == 20 * 60)
    }

    @Test func mergeIsOrderIndependent() {
        let a = deviceDay(day, .mac, procrastination: 10, updated: at("2026-10-29 10:00"))
        let b = deviceDay(day, .mac, procrastination: 12, updated: at("2026-10-29 10:00"))   // same stamp
        var x = Ledger(); x.merge(a); x.merge(b)
        var y = Ledger(); y.merge(b); y.merge(a)
        #expect(x.days == y.days)
    }

    @Test func totalsAddAcrossDevices() {
        var l = Ledger()
        l.merge(deviceDay(day, .iphone, procrastination: 12, productive: 30, focus: 25))
        l.merge(deviceDay(day, .mac, procrastination: 8, productive: 90, focus: 50))
        let t = l.total(for: day)
        #expect(t.procrastination == 20 * 60)
        #expect(t.productive == 120 * 60)
        #expect(t.focus == 75 * 60)
    }

    @Test func otherDaysDoNotLeakIntoATotal() {
        var l = Ledger()
        l.merge(deviceDay(day, procrastination: 12))
        l.merge(deviceDay(day.adding(days: 1), procrastination: 40))
        #expect(l.total(for: day).procrastination == 12 * 60)
        #expect(l.total(for: day.adding(days: 2)).procrastination == 0)
    }

    @Test func historyIsOldestFirstAndCapped() {
        let l = ledger([10, 20, 30, 40, 50])
        let today = firstDay.adding(days: 5)
        #expect(l.history(endingBefore: today, count: 3) == [30, 40, 50])
        #expect(l.history(endingBefore: today, count: 99) == [10, 20, 30, 40, 50])
        #expect(l.history(endingBefore: today, count: 0).isEmpty)
    }

    @Test func historyStopsBeforeTheGivenDay() {
        let l = ledger([10, 20, 30, 40, 50])
        #expect(l.history(endingBefore: firstDay.adding(days: 3), count: 7) == [10, 20, 30])
        #expect(l.history(endingBefore: firstDay, count: 7).isEmpty)
    }

    @Test func historySkipsUntrackedDays() {
        let l = ledger([10, nil, nil, 40])
        #expect(l.history(endingBefore: firstDay.adding(days: 10), count: 7) == [10, 40])
    }

    @Test func historyRoundsDownAfterSummingDevices() {
        var l = Ledger()
        l.merge(DeviceDay(day: day, device: .iphone, procrastination: 119, updatedAt: at("2026-10-29 12:00")))
        #expect(l.history(endingBefore: day.adding(days: 1), count: 1) == [1])
        l.merge(DeviceDay(day: day, device: .mac, procrastination: 59, updatedAt: at("2026-10-29 12:00")))
        #expect(l.history(endingBefore: day.adding(days: 1), count: 1) == [2])    // 178 s
    }

    @Test func aDayWithAZeroIsStillTracked() {
        let l = ledger([0, 15])
        #expect(l.history(endingBefore: firstDay.adding(days: 2), count: 7) == [0, 15])
    }

    @Test func roundTripsThroughJSON() throws {
        var l = Ledger()
        l.merge(deviceDay(day, .mac, procrastination: 3, productive: 4, focus: 5))
        let back = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(l))
        #expect(back.days == l.days)
    }
}
