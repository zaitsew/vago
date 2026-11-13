import AppIntents
import SwiftUI
import VagoKit
import WidgetKit

/// "Vago mode" in Control Center: on = the place in front counts as work. The app writes
/// `mode.json` (`ModeSnapshot`); a tap writes a request file and posts a Darwin notification, and
/// the app applies the switch (`AppModel.applyModeRequest`).
struct VagoModeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ModeBridge.controlKind, provider: ModeValueProvider()) { snapshot in
            ControlWidgetToggle(isOn: snapshot.isWork, action: SetModeIntent()) {
                Label(snapshot.label, systemImage: Self.symbol(snapshot.mode))
            } valueLabel: { isOn in
                Text(verbatim: isOn ? String(localized: "Work", comment: "Control Center value label: on.") : (snapshot.mode == .neutral ? String(localized: "Neutral", comment: "Control Center value label: neutral.") : String(localized: "Waste", comment: "Control Center value label: procrastination.")))
            }
            .tint(Self.color(snapshot.mode))
        }
        .displayName("Vago mode")
        .description("Switch the place in front between work and procrastination.")
    }

    private static func symbol(_ mode: Mode) -> String {
        switch mode {
        case .work: "briefcase.fill"
        case .procrastination: "flame.fill"
        case .neutral: "moon.fill"
        }
    }

    private static func color(_ mode: Mode) -> Color {
        switch mode {
        case .work: .green
        case .procrastination: .red
        case .neutral: .gray
        }
    }
}

struct ModeValueProvider: ControlValueProvider {
    var previewValue: ModeSnapshot {
        ModeSnapshot(placeKey: "instagram.com", label: "Instagram", mode: .procrastination, updatedAt: .now)
    }

    func currentValue() async throws -> ModeSnapshot {
        ModeBridge.readSnapshot() ?? .idle
    }
}

struct SetModeIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Switch Vago mode"

    @Parameter(title: "Work")
    var value: Bool

    func perform() async throws -> some IntentResult {
        let key = ModeBridge.readSnapshot()?.placeKey ?? ""
        ModeBridge.writeRequest(ModeRequest(placeKey: key, work: value, at: .now))
        ModeBridge.postRequestNotification()
        return .result()
    }
}
