import Foundation
import VagoKit

/// A UTC calendar, so tests give the same answer in every time zone.
let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

/// "2026-10-30 02:30" in UTC.
func at(_ text: String) -> Date {
    let f = DateFormatter()
    f.calendar = utc
    f.timeZone = utc.timeZone
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.date(from: text)!
}

func web(_ url: String, title: String? = nil, bundle: String = "com.google.Chrome") -> ActivitySample {
    ActivitySample(bundleID: bundle, appName: "Browser", windowTitle: title, url: URL(string: url))
}

func app(_ bundle: String, name: String = "App", title: String? = nil) -> ActivitySample {
    ActivitySample(bundleID: bundle, appName: name, windowTitle: title)
}

let builtIn = RuleBook.builtIn

/// A judge that answers with a fixed verdict and counts its calls.
actor StubJudge: Judge {
    private(set) var calls = 0
    private(set) var lastGoals = ""
    private let verdict: Verdict?
    private let delay: Duration?

    init(_ verdict: Verdict?, delay: Duration? = nil) {
        self.verdict = verdict
        self.delay = delay
    }

    func judge(_ o: ActivitySample, goals: String) async -> Verdict? {
        calls += 1
        lastGoals = goals
        if let delay { try? await Task.sleep(for: delay) }
        return verdict
    }
}

/// A clock the test moves.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    init(_ date: Date) { self.date = date }
    var now: Date {
        get { lock.withLock { date } }
        set { lock.withLock { date = newValue } }
    }
}

let workVerdict = Verdict(bucket: .productive, confidence: 0.9, reason: "work chat")

/// One DeviceDay, in minutes.
func deviceDay(_ day: DayKey, _ device: Device = .iphone, procrastination: Int = 0, productive: Int = 0, focus: Int = 0, updated: Date = at("2026-10-29 12:00")) -> DeviceDay {
    DeviceDay(day: day, device: device, procrastination: procrastination * 60, productive: productive * 60, focus: focus * 60, updatedAt: updated)
}

let firstDay = DayKey(id: "2026-09-01")

/// A ledger with one iPhone entry per consecutive day from `start`; `nil` leaves a day with no data.
func ledger(_ minutes: [Int?], start: DayKey = firstDay) -> Ledger {
    var l = Ledger()
    for (i, m) in minutes.enumerated() {
        if let m { l.merge(deviceDay(start.adding(days: i), procrastination: m)) }
    }
    return l
}

/// The day after the last entry of `ledger(minutes)`.
func dayAfter(_ minutes: [Int?], start: DayKey = firstDay) -> DayKey { start.adding(days: minutes.count) }

/// Rolls a fresh limit to the day after `minutes` and returns it.
func rolled(_ minutes: [Int?]) -> AdaptiveLimit {
    var limit = AdaptiveLimit()
    limit.roll(to: dayAfter(minutes), ledger: ledger(minutes))
    return limit
}
