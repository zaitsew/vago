import Foundation
import VagoKit

/// Reads the Mac's days from iCloud's key-value store. Shared by the app (`CloudSync`) and the
/// widget, which pulls the Mac's day itself so its timeline does not wait for the app to open.
///
/// The store needs the `com.apple.developer.ubiquity-kvstore-identifier` entitlement. Without it
/// (an unsigned build, or a profile that lacks it) the store is empty and nothing is merged.
enum CloudRead {
    /// Merges the Mac's days from the store into `ledger`. Returns whether the ledger changed.
    @discardableResult
    static func mergeMac(into ledger: inout Ledger, today: DayKey) -> Bool {
        let store = NSUbiquitousKeyValueStore.default
        store.synchronize()
        let cutoff = today.adding(days: -VagoStore.ledgerDays)
        var changed = false
        for (key, raw) in store.dictionaryRepresentation where key.hasPrefix("day/") && key.hasSuffix("/mac") {
            guard let day = DeviceDay(encoded: raw), day.device == .mac, day.day >= cutoff else { continue }
            let before = ledger.days[Ledger.key(day.day, .mac)]
            ledger.merge(day)
            if ledger.days[Ledger.key(day.day, .mac)] != before { changed = true }
        }
        return changed
    }
}
