import AppKit
import CoreGraphics
import VagoKit

/// Is anyone at the Mac? Tracking stops while the screen is locked, the Mac sleeps, the session
/// is switched away, or there has been no input for too long (docs/ARCHITECTURE.md, Idle).
@MainActor
final class Presence {
    static let idleSeconds: TimeInterval = 120
    static let videoIdleSeconds: TimeInterval = 20 * 60
    private static let videoHosts = ["youtube.com", "netflix.com", "twitch.tv", "primevideo.com"]
    private static let videoBundles: Set<String> = ["com.netflix.Netflix", "tv.twitch"]

    private(set) var locked = false
    private(set) var asleep = false
    private(set) var sessionActive = true
    private var tokens: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    init() {
        locked = Self.screenIsLockedNow()
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        observe(workspace, NSWorkspace.willSleepNotification) { $0.asleep = true }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.asleep = true }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.asleep = false }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.asleep = false }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.sessionActive = false }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionActive = true }
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.locked = true }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.locked = false }
    }

    isolated deinit {
        for entry in tokens { entry.center.removeObserver(entry.token) }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ change: @escaping @MainActor (Presence) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                change(self)
            }
        }
        tokens.append((center, token))
    }

    /// True when the screen is on, unlocked and in the foreground session.
    var isPresent: Bool { !locked && !asleep && sessionActive }

    /// Re-reads the lock flag from the window server; the distributed notifications can be missed
    /// when the app starts while the screen is already locked.
    func refresh() {
        if locked != Self.screenIsLockedNow() { locked = Self.screenIsLockedNow() }
    }

    private static func screenIsLockedNow() -> Bool {
        guard let info = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (info["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }

    /// Seconds since the last key press, click or mouse move.
    static func secondsSinceInput() -> TimeInterval {
        let anyEvent = CGEventType(rawValue: UInt32.max) ?? .null
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyEvent)
    }

    /// The idle threshold for `o`: long on video sites, where watching needs no input.
    static func idleThreshold(for o: ActivitySample) -> TimeInterval {
        if videoBundles.contains(o.bundleID) { return videoIdleSeconds }
        if let host = o.host, videoHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return videoIdleSeconds }
        return idleSeconds
    }
}
