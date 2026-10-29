import DeviceActivity
import FamilyControls
import Foundation
import VagoKit

/// Starts and stops the three `DeviceActivity` schedules. Used by the app (daily, focus)
/// and by the shield action extension (pass).
enum VagoMonitoring {
    /// One daily schedule, 04:00 to 03:59, repeating. Threshold events on the procrastination,
    /// the ambiguous and the productive selection. `includesPastActivity` keeps the day's total when the
    /// schedule is restarted in the afternoon (a changed selection, a manual restart).
    static func startDaily(_ store: VagoStore = VagoStore()) throws {
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        for (source, kind) in [(UsageEvent.Source.procrastination, SelectionKind.procrastination),
                               (.ambiguous, .ambiguous),
                               (.productive, .productive)] {
            let selection = store.selection(kind)
            guard !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
                    || !selection.webDomainTokens.isEmpty else { continue }
            for minute in UsageEvent.minutes {
                let event = UsageEvent(source: source, minute: minute)
                events[event.name] = DeviceActivityEvent(
                    applications: selection.applicationTokens,
                    categories: selection.categoryTokens,
                    webDomains: selection.webDomainTokens,
                    threshold: DateComponents(minute: minute),
                    includesPastActivity: true
                )
            }
        }
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 4, minute: 0),
            intervalEnd: DateComponents(hour: 3, minute: 59),
            repeats: true
        )
        try DeviceActivityCenter().startMonitoring(.daily, during: schedule, events: events)
    }

    /// A pass: watch the ambiguous selection for 15 (work) or 5 (scroll) minutes of use,
    /// inside a 60-minute schedule (Apple's minimum interval is 15 minutes).
    static func startPass(_ pass: Pass, store: VagoStore = VagoStore()) throws {
        let selection = store.selection(.ambiguous)
        let event = DeviceActivityEvent(
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            webDomains: selection.webDomainTokens,
            threshold: DateComponents(minute: pass.thresholdMinutes)
        )
        let start = minuteFloor(pass.start)
        let schedule = oneShot(from: start, to: start.addingTimeInterval(TimeInterval(Pass.windowMinutes * 60)))
        try DeviceActivityCenter().startMonitoring(.pass, during: schedule, events: [.passLimit: event])
    }

    /// A focus session: no events, only the interval end matters. The interval starts at the
    /// minute the session started and ends at the next whole minute at or after the session's
    /// end, so the shield never lifts early. Apple's minimum interval is 15 minutes.
    static func startFocus(_ session: FocusSession) throws {
        let start = minuteFloor(session.start)
        let end = max(minuteCeil(session.end), start.addingTimeInterval(15 * 60))
        try DeviceActivityCenter().startMonitoring(.focus, during: oneShot(from: start, to: end))
    }

    static func stop(_ names: DeviceActivityName...) {
        DeviceActivityCenter().stopMonitoring(names)
    }

    private static func minuteFloor(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
    }

    private static func minuteCeil(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded(.up) * 60)
    }

    /// A non-repeating schedule between two whole-minute dates.
    private static func oneShot(from start: Date, to end: Date) -> DeviceActivitySchedule {
        let calendar = Calendar.current
        let fields: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute]
        return DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(fields, from: start),
            intervalEnd: calendar.dateComponents(fields, from: end),
            repeats: false
        )
    }
}
