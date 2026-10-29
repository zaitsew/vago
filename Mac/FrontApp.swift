import AppKit

/// The app that has the keyboard focus right now.
struct FrontApp: Sendable, Equatable {
    var pid: pid_t
    var bundleID: String
    var name: String

    @MainActor
    static func current() -> FrontApp? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return FrontApp(
            pid: app.processIdentifier,
            bundleID: app.bundleIdentifier ?? "pid.\(app.processIdentifier)",
            name: app.localizedName ?? app.bundleIdentifier ?? "Unknown"
        )
    }
}

/// Browsers whose front tab Vago reads through Apple Events (docs/ARCHITECTURE.md).
enum Browser {
    enum Family: Sendable { case safari, chromium }

    static let families: [String: Family] = [
        "com.apple.Safari": .safari,
        "com.google.Chrome": .chromium,
        "company.thebrowser.Browser": .chromium,      // Arc
        "com.brave.Browser": .chromium,
        "com.microsoft.edgemac": .chromium,
        "company.thebrowser.dia": .chromium,          // Dia
    ]

    static func family(of bundleID: String) -> Family? { families[bundleID] }
}
