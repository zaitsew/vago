import Foundation
import Testing
@testable import VagoKit

@Suite("Summary")
struct SummaryTests {
    let today = DayKey(id: "2026-10-29")

    @Test func todaySumsDevicesInWholeMinutes() {
        var l = Ledger()
        l.merge(deviceDay(today, .iphone, procrastination: 12, productive: 30, focus: 25))
        var mac = deviceDay(today, .mac, procrastination: 3, productive: 60)
        mac.procrastination += 59                      // 3 min 59 s: floors to 3 after summing 12 + 3m59s
        l.merge(mac)
        let s = l.summary(for: today, limitMinutes: 30)
        #expect(s.tracked)
        #expect(s.procrastinationMinutes == 15)        // (720 + 239) / 60
        #expect(s.productiveMinutes == 90)
        #expect(s.focusMinutes == 25)
        #expect(s.remainingMinutes == 15)
        #expect(s.mood == "neutral" && s.emoji == "😐")
    }

    @Test func overTheLimitHasNoMinutesLeft() {
        var l = Ledger()
        l.merge(deviceDay(today, procrastination: 40))
        let s = l.summary(for: today, limitMinutes: 30)
        #expect(s.remainingMinutes == 0)
        #expect(s.mood == "upset")
        #expect(s.sentence.contains("over the limit"))
    }

    @Test func anEmptyDayIsUntracked() {
        let s = Ledger().summary(for: today, limitMinutes: 60)
        #expect(!s.tracked)
        #expect(s.procrastinationMinutes == 0)
        #expect(s.mood == "beaming")
    }

    @Test func pastDaysCarryNoLimit() {
        var l = Ledger()
        l.merge(deviceDay(today.adding(days: -1), procrastination: 20))
        let s = l.summary(for: today.adding(days: -1))
        #expect(s.limitMinutes == nil && s.mood == nil && s.remainingMinutes == nil)
        #expect(s.sentence.hasPrefix("20 min on procrastination."))
    }

    @Test func weekListsSevenDaysOldestFirstAndSkipsUntrackedInAverages() {
        var l = Ledger()
        l.merge(deviceDay(today.adding(days: -6), procrastination: 40, productive: 100, focus: 10))
        l.merge(deviceDay(today.adding(days: -3), procrastination: 20, productive: 200, focus: 30))
        l.merge(deviceDay(today, procrastination: 30, productive: 60, focus: 0))
        let w = l.weekSummary(endingOn: today, limitMinutes: 30)
        #expect(w.days.count == 7)
        #expect(w.from == "2026-10-23" && w.to == "2026-10-29")
        #expect(w.trackedDays == 3)
        #expect(w.averageProcrastinationMinutes == 30)  // (40 + 20 + 30) / 3
        #expect(w.averageProductiveMinutes == 120)      // 360 / 3
        #expect(w.totalFocusMinutes == 40)
        #expect(w.daysUnderTarget == 2)                 // 20 and 30 are at or under 30
        #expect(w.bestDay == "2026-10-26" && w.worstDay == "2026-10-23")
        #expect(w.days.last?.limitMinutes == 30)
        #expect(w.days.first?.limitMinutes == nil)
        #expect(w.days.filter { !$0.tracked }.count == 4)
    }

    @Test func weekWithoutDataSaysSo() {
        let w = Ledger().weekSummary(endingOn: today, limitMinutes: 60)
        #expect(w.trackedDays == 0)
        #expect(w.averageProcrastinationMinutes == nil && w.bestDay == nil)
        #expect(w.sentence == "No tracked days in the last 7 days.")
    }

    @Test func weekCrossesAMonthBoundary() {
        let w = Ledger().weekSummary(endingOn: DayKey(id: "2026-11-02"), limitMinutes: 60)
        #expect(w.days.map(\.day) == ["2026-10-27", "2026-10-28", "2026-10-29", "2026-10-30", "2026-10-31", "2026-11-01", "2026-11-02"])
    }
}
