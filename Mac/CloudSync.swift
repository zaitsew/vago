import Foundation
import Security
import VagoKit

/// Shares each device's daily totals through iCloud's key-value store.
///
/// One JSON value per `Ledger.key(day, device)`. This Mac writes only its own `mac` key and
/// reads every key. Without the iCloud entitlement (the default build) the store is a no-op and
/// `isEnabled` is false, which Settings shows as "iCloud sync off".
@MainActor
final class CloudSync {
    static let entitlement = "com.apple.developer.ubiquity-kvstore-identifier"

    /// True when this build is signed with the key-value store entitlement.
    let isEnabled: Bool
    private let store = NSUbiquitousKeyValueStore.default
    private var lastWritten: DeviceDay?
    private var observer: NSObjectProtocol?
    private let onRemoteDay: @MainActor (DeviceDay) -> Void

    init(onRemoteDay: @escaping @MainActor (DeviceDay) -> Void) {
        self.onRemoteDay = onRemoteDay
        isEnabled = Self.hasEntitlement()
    }

    /// Reads what iCloud already holds and starts listening for changes from other devices.
    func start() {
        guard isEnabled else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: store, queue: .main
        ) { [weak self] note in
            let keys = (note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]) ?? []
            MainActor.assumeIsolated { self?.ingest(keys: keys) }
        }
        store.synchronize()
        ingest(keys: nil)
    }

    /// Writes `day` if it changed since the last write. `force` ignores that (on quit).
    func write(_ day: DeviceDay, force: Bool = false) {
        guard isEnabled else { return }
        if !force, let last = lastWritten, last.procrastination == day.procrastination,
           last.productive == day.productive, last.focus == day.focus, last.day == day.day { return }
        store.set(day.encoded(), forKey: Ledger.key(day.day, day.device))
        lastWritten = day
        if force { store.synchronize() }
    }

    /// Merges `keys` (or every `day/` key when `nil`) into the app's ledger.
    private func ingest(keys: [String]?) {
        let all = keys ?? Array(store.dictionaryRepresentation.keys)
        for key in all where key.hasPrefix("day/") {
            guard let value = store.object(forKey: key), let day = DeviceDay(encoded: value) else { continue }
            onRemoteDay(day)
        }
    }

    private static func hasEntitlement() -> Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        return SecTaskCopyValueForEntitlement(task, entitlement as CFString, nil) != nil
    }
}
