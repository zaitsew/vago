import Foundation
import VagoKit
import WidgetKit

/// The desktop widget's data: a snapshot file the widget reads, written next to `flush`.
extension AppModel {
    /// Today's merged numbers for the widget. Hours are Mac and iPhone separately.
    func widgetSnapshot(now: Date) -> WidgetSnapshot {
        let phone = ledger.days[Ledger.key(today.day, .iphone)]
        let totals = ledger.share(for: today.day)
        return WidgetSnapshot(
            day: today.day,
            percent: totals.percent,
            productiveMinutes: totals.productive / 60,
            neutralMinutes: totals.neutral / 60,
            wasteMinutes: totals.procrastination / 60,
            limitMinutes: limit.current,
            macHours: ledger.hours(for: today.day, devices: [.mac]),
            iphoneHours: phone == nil ? [] : ledger.hours(for: today.day, devices: [.iphone]),
            iphoneUpdatedAt: phone?.updatedAt,
            updatedAt: now,
            mood: mood.emoji
        )
    }

    /// Writes the snapshot at most once a minute, sooner when the percent or the day changed, and
    /// asks WidgetKit to reload at most every 5 minutes, sooner on the same two changes.
    func writeWidgetSnapshot(now: Date, force: Bool = false) {
        let percent = share.percent
        let changed = widgetLast.day != today.day || widgetLast.percent != percent
        guard force || changed || now.timeIntervalSince(widgetLast.written) >= 60 else { return }
        guard WidgetSnapshot.write(widgetSnapshot(now: now)) else {
            // No App Group container (an unsigned build): try again in a minute, not every flush.
            widgetLast.written = now
            return
        }
        let reload = changed || now.timeIntervalSince(widgetLast.reloaded) >= 5 * 60
        widgetLast.written = now
        widgetLast.day = today.day
        widgetLast.percent = percent
        if reload {
            widgetLast.reloaded = now
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
