import Foundation
import Testing
@testable import VagoKit

@Suite("Adaptive limit")
struct AdaptiveLimitTests {
    @Test func startsAtSixtyWithNoBaseline() {
        let limit = AdaptiveLimit()
        #expect(limit.current == 60)
        #expect(limit.baseline == nil)
        #expect(limit.lastDay == nil)
    }

    @Test func calibrationHoldsSixtyUntilThreeDaysHaveFinished() {
        for minutes: [Int?] in [[], [20], [20, 20]] {
            let limit = rolled(minutes)
            #expect(limit.current == 60)
            #expect(limit.baseline == nil)
        }
    }

    @Test func threeFinishedDaysSetTheBaselineAtTheirMedian() {
        let limit = rolled([20, 50, 40])
        #expect(limit.baseline == 40)
        #expect(limit.current == 40)
    }

    @Test func baselineIsNeverBelowTheTarget() {
        let limit = rolled([5, 10, 15])
        #expect(limit.baseline == 30)
        #expect(limit.current == 30)
    }

    @Test func baselineRoundsToFiveMinutes() {
        #expect(rolled([41, 44, 47]).baseline == 45)
    }

    @Test func calibrationDaysNeedNotBeConsecutive() {
        let limit = rolled([60, nil, 60, nil, 60])
        #expect(limit.baseline == 60)
    }

    @Test func todaysDataDoesNotCount() {
        // Day 3 is today: only days 0-2 have finished.
        var limit = AdaptiveLimit()
        limit.roll(to: firstDay.adding(days: 3), ledger: ledger([60, 60, 60, 5]))
        #expect(limit.baseline == 60)
        #expect(limit.current == 60)
    }

    @Test func devicesAddUpInTheCalibrationDays() {
        var l = Ledger()
        for i in 0..<3 {
            l.merge(deviceDay(firstDay.adding(days: i), .iphone, procrastination: 25))
            l.merge(deviceDay(firstDay.adding(days: i), .mac, procrastination: 25))
        }
        var limit = AdaptiveLimit()
        limit.roll(to: firstDay.adding(days: 3), ledger: l)
        #expect(limit.baseline == 50)
    }

    @Test func goodDaysWalkTheLimitDownAndItStopsAtThirty() {
        // Calibration at 60, then 25-minute days. The 7-day median cap (median + 10) pulls
        // the limit down faster than 5 a day once the quiet days outnumber the calibration days.
        let minutes = Array(repeating: 60, count: 3) + Array(repeating: 25, count: 12)
        let l = ledger(minutes)
        var limit = AdaptiveLimit()
        var seen: [Int] = []
        for k in 3...minutes.count {
            limit.roll(to: firstDay.adding(days: k), ledger: l)
            seen.append(limit.current)
        }
        #expect(seen.prefix(7) == [60, 55, 50, 45, 35, 30, 30])
        #expect(seen.allSatisfy { $0 >= 30 })
        #expect(seen.suffix(5).allSatisfy { $0 == 30 })
    }

    @Test func eachGoodDayTakesFiveOffWhenTheMedianAllowsIt() {
        // 40-minute days against a baseline of 90: the median stays high, so the limit steps by 5.
        let limit = rolled([90, 90, 90, 40, 40])
        #expect(limit.current == 80)                  // 90 -> 85 -> 80
    }

    @Test func dayExactlyAtTheLimitCountsAsGood() {
        let limit = rolled([60, 60, 60, 60])          // limit 60, used 60
        #expect(limit.current == 55)
    }

    @Test func aBadDayEasesTheLimitByFive() {
        let limit = rolled([60, 60, 60, 20, 83])      // day 3: 60 -> 55; day 4: 83 > 150% of 55 -> 60
        #expect(limit.current == 60)
    }

    @Test func exactlyOneAndAHalfTimesDoesNotEase() {
        // Baseline 45; a quiet day takes it to 40; 60 minutes is exactly 150% of 40.
        #expect(rolled([45, 45, 45, 20, 60]).current == 40)
        #expect(rolled([45, 45, 45, 20, 61]).current == 45)
    }

    @Test func aBadDayNeverLiftsTheLimitAboveTheBaseline() {
        #expect(rolled([40, 40, 40, 20]).current == 35)
        #expect(rolled([40, 40, 40, 20, 60]).current == 40)
        #expect(rolled([40, 40, 40, 20, 60, 90, 200]).current == 40)
    }

    @Test func aMiddlingDayChangesNothing() {
        // Limit 55 after a quiet day; 70 minutes is over the limit but under 150%.
        #expect(rolled([60, 60, 60, 20, 70]).current == 55)
    }

    @Test func daysWithoutDataChangeNothing() {
        #expect(rolled([60, 60, 60, nil, nil]).current == 60)
        #expect(rolled([60, 60, 60, nil, nil, 20]).current == 55)
    }

    @Test func rollingSeveralDaysAtOnceEqualsRollingDayByDay() {
        let minutes: [Int?] = [60, 60, 60, 25, nil, 25, 90, 25, 25, nil, 25, 25]
        let l = ledger(minutes)
        var batch = AdaptiveLimit()
        batch.roll(to: dayAfter(minutes), ledger: l)
        var daily = AdaptiveLimit()
        for k in 1...minutes.count { daily.roll(to: firstDay.adding(days: k), ledger: l) }
        #expect(batch == daily)
    }

    @Test func firstRollAfterALongBreakAppliesEveryFinishedDayInOrder() {
        // Baseline 120; seven quiet days applied in one roll: 115, 110, 105, then the median cap bites.
        let limit = rolled([120, 120, 120, 10, 10, 10, 10])
        #expect(limit.baseline == 120)
        #expect(limit.current == 30)
    }

    @Test func rollingTwiceToTheSameDayChangesNothing() {
        let l = ledger([60, 60, 60, 20, 20])
        var limit = AdaptiveLimit()
        limit.roll(to: firstDay.adding(days: 5), ledger: l)
        let once = limit
        limit.roll(to: firstDay.adding(days: 5), ledger: l)
        #expect(limit == once)
    }

    @Test func rollingToAnEarlierDayChangesNothing() {
        let l = ledger([60, 60, 60, 20, 20])
        var limit = AdaptiveLimit()
        limit.roll(to: firstDay.adding(days: 5), ledger: l)
        let before = limit
        limit.roll(to: firstDay.adding(days: 2), ledger: l)
        #expect(limit == before)
    }

    @Test func theBaselineIsSetOnce() {
        var l = ledger([60, 60, 60])
        var limit = AdaptiveLimit()
        limit.roll(to: firstDay.adding(days: 3), ledger: l)
        #expect(limit.baseline == 60)
        // Later days, however different, never move the baseline.
        l = ledger([60, 60, 60, 5, 5, 5, 5, 5, 5])
        limit.roll(to: firstDay.adding(days: 9), ledger: l)
        #expect(limit.baseline == 60)
    }

    @Test func theSevenDayMedianCapsTheLimit() {
        // Baseline 120. After days 3-5 (10 min each) the 7-day window holds [120,120,120,10,10,10]:
        // median 65, cap 75. The step alone would give 105.
        #expect(rolled([120, 120, 120, 10, 10, 10]).current == 75)
        // The cap uses only the last seven tracked days.
        #expect(rolled([120, 120, 120, 10, 10, 10, 10]).current == 30)
    }

    @Test func limitsAreAlwaysWholeFivesBetweenTargetAndBaseline() {
        // A deterministic spread of days, rolled one at a time.
        var seed = 12_345
        func next() -> Int { seed = (seed &* 1_103_515_245 &+ 12_345) & 0x7fffffff; return seed }
        let minutes: [Int?] = [47, 52, 38] + (0..<60).map { _ in next() % 11 == 0 ? nil : next() % 120 }
        let l = ledger(minutes)
        var limit = AdaptiveLimit()
        for k in 1...minutes.count {
            limit.roll(to: firstDay.adding(days: k), ledger: l)
            #expect(limit.current % 5 == 0)
            #expect(limit.current >= AdaptiveLimit.targetMinutes)
            if let baseline = limit.baseline { #expect(limit.current <= baseline) }
        }
    }

    @Test func sameInputsGiveTheSameAnswer() {
        let minutes: [Int?] = [60, 60, 60, 25, 30, 90]
        #expect(rolled(minutes) == rolled(minutes))
    }

    @Test func roundTripsThroughJSON() throws {
        let limit = rolled([60, 60, 60, 20])
        let back = try JSONDecoder().decode(AdaptiveLimit.self, from: JSONEncoder().encode(limit))
        #expect(back == limit)
    }
}
