import DeviceActivity
import Foundation
import ManagedSettings

// Names and small value types shared by the app and every extension. Computed properties,
// not stored ones: the Screen Time name types are not Sendable, and a global `let` of a
// non-Sendable type is an error under strict concurrency.

extension DeviceActivityName {
    /// The daily schedule that carries the threshold events (04:00 to 03:59, repeating).
    static var daily: DeviceActivityName { DeviceActivityName("daily") }
    /// One intent-check pass: its threshold event re-applies the ambiguous shield.
    static var pass: DeviceActivityName { DeviceActivityName("pass") }
    /// A focus session: its interval end lifts the focus shield.
    static var focus: DeviceActivityName { DeviceActivityName("focus") }
}

extension ManagedSettingsStore.Name {
    /// Shield on the ambiguous selection (the "Work or scroll?" gate).
    static var ambiguous: ManagedSettingsStore.Name { ManagedSettingsStore.Name("ambiguous") }
    /// Shield on procrastination + ambiguous apps during a focus session.
    static var focus: ManagedSettingsStore.Name { ManagedSettingsStore.Name("focus") }
}

extension DeviceActivityEvent.Name {
    /// The single event of a `pass` activity.
    static var passLimit: DeviceActivityEvent.Name { DeviceActivityEvent.Name("pass.limit") }
}

/// The three app selections the owner picks.
enum SelectionKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case procrastination, ambiguous, productive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .procrastination: "Procrastination"
        case .ambiguous: "Both work and scroll"
        case .productive: "Work"
        }
    }
}

/// A usage threshold on one of the two counted selections. The event name carries
/// both parts: "p.12" is 12 minutes on the procrastination selection, "a.45" is 45 on the ambiguous one.
struct UsageEvent: Equatable, Sendable {
    enum Source: String, Sendable {
        case procrastination = "p"
        case ambiguous = "a"
    }

    var source: Source
    var minute: Int

    /// Every minute to 45, every 5 to 120, every 15 to 240. 68 thresholds per selection.
    static let minutes: [Int] =
        Array(1...45) + Array(stride(from: 50, through: 120, by: 5)) + Array(stride(from: 135, through: 240, by: 15))

    var name: DeviceActivityEvent.Name { DeviceActivityEvent.Name("\(source.rawValue).\(minute)") }

    init(source: Source, minute: Int) {
        self.source = source
        self.minute = minute
    }

    init?(name: DeviceActivityEvent.Name) {
        let parts = name.rawValue.split(separator: ".")
        guard parts.count == 2,
              let source = Source(rawValue: String(parts[0])),
              let minute = Int(parts[1]), minute > 0
        else { return nil }
        self.init(source: source, minute: minute)
    }
}

/// An intent-check pass: the owner chose "Work" or "Scroll" at the shield.
struct Pass: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case work, scroll }

    /// Minutes of use a pass allows.
    static let workMinutes = 15
    static let scrollMinutes = 5
    /// The `pass` schedule runs this long. Apple's minimum is 15 minutes; an unused pass ends here.
    static let windowMinutes = 60
    /// A threshold callback can arrive late. Minutes reported up to this long after the pass
    /// ended still belong to it, because the shield is back and no new use is possible.
    static let graceSeconds: TimeInterval = 600

    var kind: Kind
    var start: Date
    /// Set when the shield came back. `nil` while the pass is open.
    var endedAt: Date?

    var thresholdMinutes: Int { kind == .work ? Self.workMinutes : Self.scrollMinutes }
    var isOpen: Bool { endedAt == nil }

    /// Whether ambiguous minutes reported at `now` belong to this pass.
    func covers(_ now: Date) -> Bool {
        guard let endedAt else { return true }
        return now.timeIntervalSince(endedAt) <= Self.graceSeconds
    }
}
