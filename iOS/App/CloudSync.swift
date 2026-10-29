import Foundation
import VagoKit

/// `DeviceDay` values in iCloud's key-value store, one JSON value per `day/<id>/<device>` key
/// (docs/ARCHITECTURE.md). This iPhone writes `.iphone`; the Mac writes `.mac`.
///
/// The wire format is VagoKit's `DeviceDay.encoded()` / `DeviceDay(encoded:)`, shared with the Mac app.
@MainActor
enum CloudSync {
    private static var store: NSUbiquitousKeyValueStore { .default }

    static var isSignedIn: Bool { FileManager.default.ubiquityIdentityToken != nil }

    /// Writes every iPhone day in the ledger that iCloud does not have yet or has older.
    static func push(_ ledger: Ledger, today: DayKey) {
        for value in ledger.days.values where value.device == .iphone {
            let key = Ledger.key(value.day, .iphone)
            if let stored = store.object(forKey: key).flatMap({ DeviceDay(encoded: $0) }),
               stored.updatedAt >= value.updatedAt { continue }
            store.set(value.encoded(), forKey: key)
        }
        // Keep the store well under its 1024-key limit: drop this iPhone's keys beyond the ledger window.
        let cutoff = today.adding(days: -VagoStore.ledgerDays)
        for key in store.dictionaryRepresentation.keys where key.hasPrefix("day/") && key.hasSuffix("/iphone") {
            let id = key.dropFirst(4).dropLast(7)
            if DayKey(id: String(id)) < cutoff { store.removeObject(forKey: key) }
        }
        store.synchronize()
    }

    /// Merges the Mac's days from the store. Returns whether the ledger changed.
    static func pull(into ledger: inout Ledger, today: DayKey) -> Bool {
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
