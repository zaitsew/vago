import Foundation
import VagoKit

/// `DeviceDay` values in iCloud's key-value store, one JSON value per `day/<id>/<device>` key
/// (docs/ARCHITECTURE.md). This iPhone writes `.iphone`; the Mac writes `.mac`.
///
/// Values are written as JSON `Data` with `JSONEncoder`'s defaults. The reader also accepts a
/// UTF-8 `String` and ISO 8601 dates, so a Mac that writes either way still merges.
@MainActor
enum CloudSync {
    private static var store: NSUbiquitousKeyValueStore { .default }

    static var isSignedIn: Bool { FileManager.default.ubiquityIdentityToken != nil }

    /// Writes this iPhone's recent days. A key is rewritten only when the stored value is older.
    static func push(_ ledger: Ledger, today: DayKey) {
        let days = (0...1).map { today.adding(days: -$0) }
        for day in days {
            guard let value = ledger.days[Ledger.key(day, .iphone)] else { continue }
            let key = Ledger.key(day, .iphone)
            if let stored = decode(store.object(forKey: key)), stored.updatedAt >= value.updatedAt { continue }
            if let data = try? JSONEncoder().encode(value) { store.set(data, forKey: key) }
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
            guard let day = decode(raw), day.device == .mac, day.day >= cutoff else { continue }
            let before = ledger.days[Ledger.key(day.day, .mac)]
            ledger.merge(day)
            if ledger.days[Ledger.key(day.day, .mac)] != before { changed = true }
        }
        return changed
    }

    private static func decode(_ raw: Any?) -> DeviceDay? {
        let data: Data?
        switch raw {
        case let value as Data: data = value
        case let value as String: data = value.data(using: .utf8)
        default: data = nil
        }
        guard let data else { return nil }
        if let day = try? JSONDecoder().decode(DeviceDay.self, from: data) { return day }
        let iso = JSONDecoder()
        iso.dateDecodingStrategy = .iso8601
        return try? iso.decode(DeviceDay.self, from: data)
    }
}
