import Foundation
import Testing
@testable import VagoKit

@Suite("Hours and the productive share")
struct HoursShareTests {
    let day = DayKey(id: "2026-11-08")

    @Test func hourSlotsStartAtFour() {
        #expect(DayKey.hourSlot(of: at("2026-11-08 04:00"), calendar: utc) == 0)
        #expect(DayKey.hourSlot(of: at("2026-11-08 13:59"), calendar: utc) == 9)
        #expect(DayKey.hourSlot(of: at("2026-11-09 00:30"), calendar: utc) == 20)
        #expect(DayKey.hourSlot(of: at("2026-11-09 03:59"), calendar: utc) == 23)
        #expect(DayKey.clockHour(ofSlot: 20) == 0)
    }

    @Test func addCountsTotalsAndHours() {
        var d = DeviceDay(day: day, device: .mac, updatedAt: at("2026-11-08 10:00"))
        d.add(.productive, seconds: 60, at: at("2026-11-08 10:15"), calendar: utc)
        d.add(.procrastination, seconds: 30, at: at("2026-11-08 10:20"), calendar: utc)
        d.add(.neutral, seconds: 10, at: at("2026-11-08 11:00"), calendar: utc)
        d.add(.ambiguous, seconds: 99, at: at("2026-11-08 11:00"), calendar: utc)
        #expect(d.productive == 60 && d.procrastination == 30 && d.neutral == 10)
        #expect(d.hours[6] == HourSlot(slot: 6, productive: 60, procrastination: 30))
        #expect(d.hours[7].neutral == 10)
        #expect(d.productiveByHour.count == 24)
    }

    @Test func moveShiftsACorrectedCall() {
        var d = DeviceDay(day: day, device: .mac, updatedAt: at("2026-11-08 10:00"))
        d.add(.neutral, seconds: 120, at: at("2026-11-08 10:15"), calendar: utc)
        let moved = d.move(500, from: .neutral, to: .procrastination, at: at("2026-11-08 10:15"), calendar: utc)
        #expect(moved == 120)
        #expect(d.neutral == 0 && d.procrastination == 120 && d.hours[6].procrastination == 120 && d.hours[6].neutral == 0)
    }

    @Test func aCorrectionSpanningTwoHoursMovesEachPart() {
        var d = DeviceDay(day: day, device: .mac, updatedAt: at("2026-11-08 10:00"))
        d.add(.neutral, seconds: 600, at: at("2026-11-08 10:55"), calendar: utc)
        d.add(.neutral, seconds: 600, at: at("2026-11-08 11:05"), calendar: utc)
        let moved = d.move(1200, from: .neutral, to: .procrastination, startingAt: at("2026-11-08 10:50"), calendar: utc)
        #expect(moved == 1200)
        #expect(d.hours[6].procrastination == 600 && d.hours[7].procrastination == 600)
        #expect(d.hours[6].neutral == 0 && d.hours[7].neutral == 0)
    }

    @Test func oldValuesDecodeWithoutHours() throws {
        let json = #"{"day":{"id":"2026-11-01"},"device":"iphone","procrastination":60,"productive":120,"focus":0,"updatedAt":"2026-11-01T10:00:00Z"}"#
        let d = try #require(DeviceDay(encoded: Data(json.utf8)))
        #expect(d.neutral == 0 && d.productiveByHour.isEmpty && d.hours.count == 24)
        var round = d
        round.add(.productive, seconds: 1, at: at("2026-11-01 12:00"), calendar: utc)
        #expect(DeviceDay(encoded: round.encoded()) == round)
    }

    @Test func ledgerSumsHoursOverDevices() {
        var mac = DeviceDay(day: day, device: .mac, updatedAt: at("2026-11-08 10:00"))
        var phone = DeviceDay(day: day, device: .iphone, updatedAt: at("2026-11-08 10:00"))
        mac.add(.productive, seconds: 600, at: at("2026-11-08 09:10"), calendar: utc)
        phone.add(.procrastination, seconds: 300, at: at("2026-11-08 09:40"), calendar: utc)
        var l = Ledger()
        l.merge(mac); l.merge(phone)
        #expect(l.hours(for: day)[5] == HourSlot(slot: 5, productive: 600, procrastination: 300))
        #expect(l.hours(for: day, devices: [.iphone])[5].productive == 0)
    }

    @Test func shareIsHundredMinusWaste() {
        #expect(ProductiveShare(productive: 3000, neutral: 1200, procrastination: 600).percent == 87)   // 12.5% waste rounds to 13
        #expect(ProductiveShare(productive: 3000, neutral: 1500, procrastination: 500).percent == 90)
        #expect(ProductiveShare(productive: 3000, neutral: 0, procrastination: 0).text == "100%")
        #expect(ProductiveShare(productive: 0, neutral: 0, procrastination: 1800).percent == 0)
    }

    @Test func shareHidesBelowFifteenMinutes() {
        #expect(ProductiveShare(productive: 0, procrastination: 899).percent == nil)
        #expect(ProductiveShare(productive: 0, procrastination: 899).text == "—")
        #expect(ProductiveShare(productive: 0, procrastination: 900).percent == 0)
    }

    @Test func shareNeverRoundsAwayTheLastMinutes() {
        #expect(ProductiveShare(productive: 100_000, procrastination: 60).percent == 99)
        #expect(ProductiveShare(productive: 1, procrastination: 100_000).percent == 1)
    }

    @Test func shareTint() {
        #expect(ProductiveShare(productive: 9000, procrastination: 1000).tint == .green)   // 90%
        #expect(ProductiveShare(productive: 7600, procrastination: 2400).tint == .yellow)  // 76%
        #expect(ProductiveShare(productive: 7000, procrastination: 3000).tint == .red)
    }

    @Test func summaryCarriesTheShare() {
        var mac = DeviceDay(day: day, device: .mac, updatedAt: at("2026-11-08 10:00"))
        mac.add(.productive, seconds: 3600, at: at("2026-11-08 10:00"), calendar: utc)
        mac.add(.procrastination, seconds: 400, at: at("2026-11-08 10:00"), calendar: utc)
        var l = Ledger()
        l.merge(mac)
        let s = l.summary(for: day, limitMinutes: 30)
        #expect(s.productivePercent == 90)
        #expect(s.sentence.hasPrefix("90% productive."))
    }
}

@Suite("Autonomy")
struct AutonomyTests {
    let today = DayKey(id: "2026-11-08")

    func judged(_ bucket: Bucket, ambiguous: Bool = true, confidence: Double = 0.9) -> Classification {
        Classification(bucket: bucket, unclear: false, reason: "x", source: .judge, ambiguous: ambiguous,
                       confidence: confidence, verdict: bucket)
    }

    @Test func auditHoldsAfterThreeWorkHeavyDays() {
        var a = JudgeAudit()
        for back in 1...3 {
            a.record(judged(.productive), seconds: 40 * 60, day: today.adding(days: -back))
            a.record(judged(.procrastination), seconds: 5 * 60, day: today.adding(days: -back))
        }
        #expect(!a.trusted(on: today))
        a.corrected(on: today)
        #expect(a.trusted(on: today))
    }

    @Test func auditTrustsWithOneBalancedDay() {
        var a = JudgeAudit()
        for back in 1...3 { a.record(judged(.productive), seconds: 40 * 60, day: today.adding(days: -back)) }
        a.record(judged(.procrastination), seconds: 20 * 60, day: today.adding(days: -2))
        #expect(a.trusted(on: today))
    }

    @Test func auditIgnoresSmallDaysAndUnknownPlaces() {
        var a = JudgeAudit()
        for back in 1...3 {
            a.record(judged(.productive), seconds: 20 * 60, day: today.adding(days: -back))
            a.record(judged(.productive, ambiguous: false), seconds: 60 * 60, day: today.adding(days: -back))
        }
        #expect(a.trusted(on: today))
    }

    @Test func memoryLearnsAfterThreeSureDays() {
        var m = VerdictMemory()
        let o = web("https://swiftbysundell.com/articles/x", title: "Article")
        let c = judged(.productive, ambiguous: false, confidence: 0.9)
        #expect(m.note(o, c, day: today) == nil)
        #expect(m.note(o, c, day: today) == nil)                 // the same day counts once
        #expect(m.note(o, c, day: today.adding(days: 1)) == nil)
        let rule = m.note(o, c, day: today.adding(days: 2))
        #expect(rule?.host == "swiftbysundell.com" && rule?.pathPrefix == "/articles" && rule?.source == .auto)
        #expect(rule?.bucket == .productive)
    }

    @Test func memoryNeverLearnsAmbiguousPlaces() {
        var m = VerdictMemory()
        let o = web("https://youtube.com/watch?v=1")
        for i in 0..<5 { #expect(m.note(o, judged(.productive), day: today.adding(days: i)) == nil) }
    }

    @Test func memoryStartsOverWhenTheJudgeChangesItsMind() {
        var m = VerdictMemory()
        let o = app("com.example.reader")
        _ = m.note(o, judged(.productive, ambiguous: false), day: today)
        _ = m.note(o, judged(.procrastination, ambiguous: false), day: today.adding(days: 1))
        #expect(m.note(o, judged(.procrastination, ambiguous: false), day: today.adding(days: 2)) == nil)
        #expect(m.note(o, judged(.procrastination, ambiguous: false), day: today.adding(days: 3))?.bundleID == "com.example.reader")
    }

    @Test func adoptedRulesSitBehindCorrections() {
        var book = builtIn
        let o = app("com.example.reader")
        book.learn(from: o, bucket: .procrastination)
        book.adopt(Rule(bundleID: "com.example.reader", bucket: .productive, source: .auto))
        #expect(book.bucket(for: o) == .procrastination)
        #expect(!book.rules.contains { $0.source == .auto })

        var fresh = builtIn
        fresh.adopt(Rule(bundleID: "com.example.reader", bucket: .productive, source: .auto))
        #expect(fresh.bucket(for: o) == .productive)
        #expect(fresh.customRules.count == 1)
        fresh.learn(from: o, bucket: .procrastination)            // a correction replaces the auto rule
        #expect(fresh.bucket(for: o) == .procrastination && fresh.customRules.count == 1)
    }
}
