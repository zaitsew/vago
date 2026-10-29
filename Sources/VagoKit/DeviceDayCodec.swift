import Foundation

/// The one wire format for `DeviceDay` values in the iCloud key-value store, shared by the
/// iPhone app and the Mac app: JSON with ISO 8601 dates, stored as `Data` under
/// `Ledger.key(day, device)`.
extension DeviceDay {
    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(self)) ?? Data()
    }

    /// Reads `encoded()` output. Also accepts numeric dates and a UTF-8 `String` holding the
    /// JSON, so a value written by an early build still merges. Nil for anything else.
    public init?(encoded value: Any) {
        let data: Data
        switch value {
        case let d as Data: data = d
        case let s as String: data = Data(s.utf8)
        default: return nil
        }
        let iso = JSONDecoder()
        iso.dateDecodingStrategy = .iso8601
        if let day = try? iso.decode(DeviceDay.self, from: data) { self = day; return }
        if let day = try? JSONDecoder().decode(DeviceDay.self, from: data) { self = day; return }
        return nil
    }
}
