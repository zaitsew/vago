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
    /// Productive seconds per hour slot (`DayKey.hourSlot`, 04:00 = slot 0), 24 entries: the minutes
    /// each threshold added, put in the hour its event arrived. Empty in counters stored before hours existed.
    var productiveByHour: [Int] = []
    /// Procrastination seconds per hour slot, 24 entries. Empty in older counters.
    var procrastinationByHour: [Int] = []

    init(day: DayKey) { self.day = day }

    private enum CodingKeys: String, CodingKey {
        case day, procrastinationMinutes, ambiguousMinutes, productiveMinutes, ambiguousAsWork, ambiguousAsScroll
        case lastEventAt, productiveByHour, procrastinationByHour
    }

    /// Counters stored by builds before hours existed decode with empty hour lists.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(DayKey.self, forKey: .day)
        procrastinationMinutes = try c.decodeIfPresent(Int.self, forKey: .procrastinationMinutes) ?? 0
        ambiguousMinutes = try c.decodeIfPresent(Int.self, forKey: .ambiguousMinutes) ?? 0
        productiveMinutes = try c.decodeIfPresent(Int.self, forKey: .productiveMinutes) ?? 0
        ambiguousAsWork = try c.decodeIfPresent(Int.self, forKey: .ambiguousAsWork) ?? 0
        ambiguousAsScroll = try c.decodeIfPresent(Int.self, forKey: .ambiguousAsScroll) ?? 0
        lastEventAt = try c.decodeIfPresent(Date.self, forKey: .lastEventAt)
        productiveByHour = try c.decodeIfPresent([Int].self, forKey: .productiveByHour) ?? []
        procrastinationByHour = try c.decodeIfPresent([Int].self, forKey: .procrastinationByHour) ?? []
    }

    var procrastinationSeconds: Int { (procrastinationMinutes + ambiguousAsScroll) * 60 }
    var productiveSeconds: Int { (productiveMinutes + ambiguousAsWork) * 60 }

    /// Applies one threshold. Returns the minutes it added (0 for a duplicate or an old callback).
    /// The added minutes also go into the hour slot of `now`, as productive or procrastination, so
    /// the hour lists always sum to the part of the totals counted since hours existed.
    @discardableResult
    mutating func apply(_ event: UsageEvent, pass: Pass?, now: Date) -> Int {
        lastEventAt = now
        switch event.source {
        case .procrastination:
            let added = event.minute - procrastinationMinutes
            guard added > 0 else { return 0 }
            procrastinationMinutes = event.minute
            bump(.procrastination, minutes: added, at: now)
            return added
        case .productive:
            let added = event.minute - productiveMinutes
            guard added > 0 else { return 0 }
            productiveMinutes = event.minute
            bump(.productive, minutes: added, at: now)
            return added
        case .ambiguous:
            let added = event.minute - ambiguousMinutes
            guard added > 0 else { return 0 }
            ambiguousMinutes = event.minute
            if let pass, pass.kind == .work, pass.covers(now) {
                ambiguousAsWork += added
                bump(.productive, minutes: added, at: now)
            } else {
                ambiguousAsScroll += added
                bump(.procrastination, minutes: added, at: now)
            }
            return added
        }
    }

    private mutating func bump(_ bucket: Bucket, minutes: Int, at date: Date) {
        let slot = DayKey.hourSlot(of: date)
        func add(_ hours: inout [Int]) {
            if hours.count != DayKey.hoursPerDay {
                hours = (0..<DayKey.hoursPerDay).map { hours.indices.contains($0) ? hours[$0] : 0 }
            }
            hours[slot] += minutes * 60
        }
        if bucket == .productive { add(&productiveByHour) } else { add(&procrastinationByHour) }
    }
}
