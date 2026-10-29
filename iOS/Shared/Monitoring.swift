import DeviceActivity
import FamilyControls
import Foundation
import VagoKit

/// Starts and stops the three `DeviceActivity` schedules. Used by the app (daily, focus)
/// and by the shield action extension (pass).
enum VagoMonitoring {
    /// One daily schedule, 04:00 to 03:59, repeating. Threshold events on the procrastination
    /// and the ambiguous selection. `includesPastActivity` keeps the day's total when the
    /// schedule is restarted in the afternoon (a changed selection, a manual restart).
    static func startDaily(_ store: VagoStore = VagoStore()) throws {
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        for (source, kind) in [(UsageEvent.Source.procrastination, SelectionKind.procrastination),
                               (.ambiguous, .ambiguous)] {
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
        let schedule = oneShot(from: pass.start, minutes: Pass.windowMinutes)
        try DeviceActivityCenter().startMonitoring(.pass, during: schedule, events: [.passLimit: event])
    }

    /// A focus session: no events, only the interval end matters.
    static func startFocus(_ session: FocusSession) throws {
        let schedule = oneShot(from: session.start, minutes: max(session.minutes, 15))
        try DeviceActivityCenter().startMonitoring(.focus, during: schedule)
    }

    static func stop(_ names: DeviceActivityName...) {
        DeviceActivityCenter().stopMonitoring(names)
    }

    /// A non-repeating schedule that begins at the start of `date`'s minute.
    private static func oneShot(from date: Date, minutes: Int) -> DeviceActivitySchedule {
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)) ?? date
        let end = start.addingTimeInterval(TimeInterval(minutes * 60))
        let fields: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute]
        return DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(fields, from: start),
            intervalEnd: calendar.dateComponents(fields, from: end),
            repeats: false
        )
    }
}
