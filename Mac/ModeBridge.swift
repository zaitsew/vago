import Foundation
import VagoKit

/// What the Mac app tells the Control Center control: the place in front and its mode.
/// Written to `mode.json` in the App Group container. Compiled into the app and the widget extension.
struct ModeSnapshot: Codable, Equatable, Sendable {
    var placeKey: String
    var label: String
    var mode: Mode
    var updatedAt: Date

    var isWork: Bool { mode == .work }

    static let idle = ModeSnapshot(placeKey: "", label: "Vago", mode: .neutral, updatedAt: .distantPast)
}

/// A switch the control asks for. The app applies it and deletes the file.
struct ModeRequest: Codable, Equatable, Sendable {
    var placeKey: String
    var work: Bool
    var at: Date
}

/// The files and the Darwin notification the app and the control share (`docs/ARCHITECTURE.md`).
enum ModeBridge {
    static let snapshotName = "mode.json"
    static let requestName = "mode-request.json"
    static let darwinName = "com.zaitsew.vago.mac.mode-request"
    static let controlKind = "com.zaitsew.vago.mac.mode"

    private static func url(_ name: String) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.groupID)?
            .appendingPathComponent(name)
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    static func readSnapshot() -> ModeSnapshot? {
        guard let url = url(snapshotName), let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder().decode(ModeSnapshot.self, from: data)
    }

    @discardableResult
    static func writeSnapshot(_ snapshot: ModeSnapshot) -> Bool {
        guard let url = url(snapshotName), let data = try? encoder().encode(snapshot) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    @discardableResult
    static func writeRequest(_ request: ModeRequest) -> Bool {
        guard let url = url(requestName), let data = try? encoder().encode(request) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// The pending request, deleted as it is read.
    static func takeRequest() -> ModeRequest? {
        guard let url = url(requestName), let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.removeItem(at: url)
        return try? decoder().decode(ModeRequest.self, from: data)
    }

    /// Tells the app a request is waiting.
    static func postRequestNotification() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(darwinName as CFString), nil, nil, true
        )
    }
}
