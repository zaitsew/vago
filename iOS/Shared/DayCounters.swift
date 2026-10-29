import Foundation
import VagoKit

/// Today's counters, written by the monitor extension.
///
/// Threshold events report "N minutes of use so far today", so each counter only moves up:
/// a duplicate or out-of-order callback with a smaller N changes nothing. New ambiguous
/// minutes (the step from the last N to this N) count as productive when a work pass covers
/// them and as procrastination otherwise.
struct DayCounters: Codable, Equatable, Sendable {
    var day: DayKey
    /// Highest threshold reached on the procrastination selection.
    var procrastinationMinutes = 0
    /// Highest threshold reached on the ambiguous selection.
    var ambiguousMinutes = 0
    /// Highest threshold reached on the productive selection.
    var productiveMinutes = 0
    /// Ambiguous minutes counted as productive (work passes).
    var ambiguousAsWork = 0
    /// Ambiguous minutes counted as procrastination (scroll passes and no pass).
    var ambiguousAsScroll = 0
    /// When the monitor last reported anything. Shown in Settings to spot a silent monitor.
    var lastEventAt: Date?

    init(day: DayKey) { self.day = day }

    var procrastinationSeconds: Int { (procrastinationMinutes + ambiguousAsScroll) * 60 }
    var productiveSeconds: Int { (productiveMinutes + ambiguousAsWork) * 60 }

    /// Applies one threshold. Returns the minutes it added (0 for a duplicate or an old callback).
    @discardableResult
    mutating func apply(_ event: UsageEvent, pass: Pass?, now: Date) -> Int {
        lastEventAt = now
        switch event.source {
        case .procrastination:
            let added = event.minute - procrastinationMinutes
            guard added > 0 else { return 0 }
            procrastinationMinutes = event.minute
            return added
        case .productive:
            let added = event.minute - productiveMinutes
            guard added > 0 else { return 0 }
            productiveMinutes = event.minute
            return added
        case .ambiguous:
            let added = event.minute - ambiguousMinutes
            guard added > 0 else { return 0 }
            ambiguousMinutes = event.minute
            if let pass, pass.kind == .work, pass.covers(now) {
                ambiguousAsWork += added
            } else {
                ambiguousAsScroll += added
            }
            return added
        }
    }
}
