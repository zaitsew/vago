import AppIntents
import Foundation
import VagoKit

/// How long a focus block runs. The same two lengths as the Focus tab.
enum FocusLength: String, AppEnum {
    case short, long

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Focus length"
    static let caseDisplayRepresentations: [FocusLength: DisplayRepresentation] = [
        .short: "25 minutes",
        .long: "50 minutes",
    ]

    var minutes: Int { self == .short ? 25 : 50 }
}

/// "How focused am I today?" Minutes of procrastination against the limit, work and focus.
struct TodayFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Today's Focus"
    static let description = IntentDescription(
        "Today's minutes of procrastination against your daily limit, plus work and focus minutes, across your devices."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let sentence = FocusControl.today().summary.sentence
        return .result(value: sentence, dialog: IntentDialog(stringLiteral: sentence))
    }
}

/// "What is my limit?" The adaptive daily limit, what is used and what is left.
struct DailyLimitIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Daily Limit"
    static let description = IntentDescription(
        "Your procrastination limit for today in minutes, and how much of it is left."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let (summary, limit) = FocusControl.today()
        let used = summary.procrastinationMinutes
        let spoken = used >= limit
            ? "Your limit today is \(limit) minutes. You are over it, at \(used)."
            : "Your limit today is \(limit) minutes. \(used) used, \(limit - used) left."
        return .result(value: limit, dialog: IntentDialog(stringLiteral: spoken))
    }
}

/// Starts a focus block: distracting apps are paused until the tree is grown.
struct StartFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Focus Block"
    static let description = IntentDescription(
        "Starts a 25 or 50 minute focus block. Distracting apps are paused until it ends."
    )

    @Parameter(title: "Length", default: .short)
    var length: FocusLength

    static var parameterSummary: some ParameterSummary {
        Summary("Start a \(\.$length) focus block")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let session = try FocusControl.start(minutes: length.minutes)
        await FocusControl.refreshSurfaces()
        return .result(dialog: IntentDialog(stringLiteral: "\(session.stage(at: .now)) Focus for \(session.minutes) minutes. Distracting apps are paused."))
    }
}

/// Gives up the running block. The tree wilts; the focus time so far still counts.
struct StopFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Focus Block"
    static let description = IntentDescription(
        "Stops the running focus block and lifts the pause on apps. Focus time so far still counts."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let minutes = FocusControl.stop() else {
            return .result(dialog: "No focus block is running.")
        }
        await FocusControl.refreshSurfaces()
        return .result(dialog: IntentDialog(stringLiteral: "🥀 Focus block stopped after \(minutes) min. Apps are open again."))
    }
}

/// The phrases Siri and Spotlight offer without any setup.
struct VagoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TodayFocusIntent(),
            phrases: [
                "How focused am I in \(.applicationName)",
                "Today in \(.applicationName)",
                "\(.applicationName) today",
            ],
            shortTitle: "Today",
            systemImageName: "face.smiling"
        )
        AppShortcut(
            intent: DailyLimitIntent(),
            phrases: [
                "My limit in \(.applicationName)",
                "What is my \(.applicationName) limit",
            ],
            shortTitle: "Daily Limit",
            systemImageName: "gauge.with.dots.needle.50percent"
        )
        AppShortcut(
            intent: StartFocusIntent(),
            phrases: [
                "Start focus in \(.applicationName)",
                "Start a \(.applicationName) focus block",
            ],
            shortTitle: "Start Focus",
            systemImageName: "leaf"
        )
        AppShortcut(
            intent: StopFocusIntent(),
            phrases: [
                "Stop focus in \(.applicationName)",
                "Stop the \(.applicationName) focus block",
            ],
            shortTitle: "Stop Focus",
            systemImageName: "leaf.arrow.triangle.circlepath"
        )
    }
}
