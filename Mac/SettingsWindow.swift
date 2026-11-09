import AppKit
import SwiftUI
import VagoKit

/// A normal window hosting a SwiftUI view. Made once, then reused: closing hides it, showing
/// brings the same window to the front.
@MainActor
final class HostedWindow {
    private var window: NSWindow?
    private let title: String
    private let size: NSSize
    private let minSize: NSSize
    private let resizable: Bool
    private let autosaveName: String
    private let content: @MainActor (HostedWindow) -> AnyView

    init(title: String, size: NSSize, minSize: NSSize, resizable: Bool, autosaveName: String,
         content: @escaping @MainActor (HostedWindow) -> AnyView) {
        self.title = title
        self.size = size
        self.minSize = minSize
        self.resizable = resizable
        self.autosaveName = autosaveName
        self.content = content
    }

    func show() {
        let window = self.window ?? make()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    /// The window title; the Day window sets it to the date it shows.
    func setTitle(_ text: String) {
        window?.title = text
    }

    private func make() -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable { style.insert(.resizable) }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = title
        let host = NSHostingController(rootView: content(self))
        host.sizingOptions = []                    // the window keeps its size; SwiftUI fills it
        window.contentViewController = host
        window.setContentSize(size)
        window.contentMinSize = minSize
        window.center()
        window.setFrameAutosaveName(autosaveName)
        return window
    }
}

/// Settings: goals, launch at login, move reminders, permissions, the AI judge, sync, and the
/// rules Vago learned.
@MainActor
enum SettingsWindow {
    static func make(model: AppModel) -> HostedWindow {
        HostedWindow(title: "Vago Settings", size: NSSize(width: 480, height: 600), minSize: NSSize(width: 420, height: 420),
                     resizable: true, autosaveName: "VagoSettings") { _ in
            AnyView(SettingsView(model: model))
        }
    }
}

struct SettingsView: View {
    let model: AppModel
    @State private var draft = ""
    @State private var confirmForget = false

    var body: some View {
        Form {
            Section {
                TextField("Goals", text: $draft, prompt: Text(PersistedState.defaultGoals), axis: .vertical)
                    .lineLimit(3...6)
                    .labelsHidden()
                    .onSubmit(commit)
                HStack {
                    Text("Vago's AI judges every unclear place against these.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Save", action: commit)
                        .disabled(draft == model.goals)
                }
            } header: {
                Text("Goals")
            }

            Section("General") {
                Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                Toggle("Move reminders", isOn: Binding(get: { model.breaks.enabled }, set: { model.setBreaksEnabled($0) }))
                Picker("Remind after", selection: Binding(get: { model.breaks.streakMinutes }, set: { model.setBreakMinutes($0) })) {
                    ForEach(BreakCoach.streakChoices, id: \.self) { Text("\($0) min at the Mac").tag($0) }
                }
                .disabled(!model.breaks.enabled)
            }

            Section("Permissions") {
                PermissionRow(name: "Accessibility", ok: model.accessibilityGranted,
                              detail: model.accessibilityGranted ? "Window titles of every app" : "Off: Vago sees app names only") {
                    if !Permissions.requestAccessibility() { Permissions.openAccessibilitySettings() }
                }
                PermissionRow(name: "Automation", ok: !model.automation.values.contains(.denied), detail: automationDetail) {
                    Permissions.openAutomationSettings()
                }
            }

            Section("Autonomy") {
                LabeledContent {
                    Text(judge.state).foregroundStyle(judge.color)
                } label: {
                    Label("On-device AI judge", systemImage: judge.symbol)
                    Text(judge.detail)
                }
                LabeledContent {
                    HStack(spacing: 8) {
                        Text("\(model.learnedRuleCount)").monospacedDigit()
                        Button("Forget learned rules…") { confirmForget = true }
                            .disabled(model.learnedRuleCount == 0)
                    }
                } label: {
                    Label("Learned rules", systemImage: "brain")
                    Text("From your corrections, and from places the AI called the same way on three days.")
                }
            }

            Section("Lab") {
                Picker(selection: Binding(get: { model.eveningReviewStyle }, set: { model.setEveningReviewStyle($0) })) {
                    ForEach(EveningReviewStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                } label: {
                    Text("Evening review")
                    Text("What Review opens: the Day window, one card at a time, or one list.")
                }
            }

            Section("Sync") {
                LabeledContent {
                    Text(model.icloudEnabled ? "On" : "Off").foregroundStyle(.secondary)
                } label: {
                    Label("iCloud", systemImage: model.icloudEnabled ? "icloud" : "icloud.slash")
                    Text(model.icloudEnabled ? "Daily totals are shared with the iPhone" : "Needs the development profile: scripts/make-mac-profile.sh")
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Forget \(model.learnedRuleCount) learned rules?", isPresented: $confirmForget) {
            Button("Forget", role: .destructive) { model.forgetLearnedRules() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Vago forgets the rules from your corrections and from its own repeated calls. Built-in rules stay.")
        }
        .onAppear { draft = model.goals }
        .onDisappear(perform: commit)
    }

    private var judge: (state: String, detail: String, symbol: String, color: Color) {
        if !model.judgeAvailable {
            return ("Unavailable", "Apple Intelligence is off or still downloading. Mixed apps count as waste, unknown ones as neutral.",
                    "sparkles.slash", .secondary)
        }
        if model.judgeHeld {
            return ("Held", "It called most feed time work on three days. Its work calls on mixed apps count as neutral until a normal day or your next correction.",
                    "exclamationmark.triangle", .orange)
        }
        return ("On", "Decides unclear places on this Mac. Nothing leaves the Mac.", "sparkles", .green)
    }

    private var automationDetail: String {
        if model.automation.isEmpty { return "Each browser asks the first time it is in front" }
        return model.automation.sorted { $0.key < $1.key }
            .map { "\(Self.browserName($0.key)) \($0.value == .allowed ? "allowed" : "denied")" }
            .joined(separator: ", ")
    }

    private func commit() {
        guard draft != model.goals else { return }
        model.setGoals(draft)
        draft = model.goals
    }

    private static func browserName(_ bundleID: String) -> String {
        switch bundleID {
        case "com.apple.Safari": "Safari"
        case "com.google.Chrome": "Chrome"
        case "company.thebrowser.Browser": "Arc"
        case "com.brave.Browser": "Brave"
        case "com.microsoft.edgemac": "Edge"
        case "company.thebrowser.dia": "Dia"
        default: bundleID
        }
    }
}

private struct PermissionRow: View {
    let name: String
    let ok: Bool
    let detail: String
    let action: () -> Void

    var body: some View {
        LabeledContent {
            Button("Open Settings", action: action)
        } label: {
            Label {
                Text(name)
            } icon: {
                Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(ok ? .green : .orange)
            }
            Text(detail)
        }
    }
}
