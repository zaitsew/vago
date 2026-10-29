import SwiftUI
import VagoKit

/// Goals text, launch at login, permissions and Quit.
struct SettingsSection: View {
    let model: AppModel
    @State private var open = false
    @State private var draft = ""

    var body: some View {
        DisclosureGroup("Settings", isExpanded: $open) {
            VStack(alignment: .leading, spacing: 12) {
                goals
                Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                permissions
                status
            }
            .padding(.top, 8)
        }
        .onAppear { draft = model.goals }
        .onChange(of: open) { _, isOpen in if !isOpen { commit() } }
        .onDisappear { commit() }
        Button("Quit Vago") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var goals: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("My goals (the AI judges against these)").font(.caption).foregroundStyle(.secondary)
            TextField("Goals", text: $draft, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
                .onSubmit(commit)
            if draft != model.goals {
                Button("Save goals", action: commit).controlSize(.small)
            }
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Permissions").font(.caption).foregroundStyle(.secondary)
            row("Accessibility", ok: model.accessibilityGranted,
                detail: model.accessibilityGranted ? "window titles" : "off: app names only") {
                if !Permissions.requestAccessibility() { Permissions.openAccessibilitySettings() }
            }
            row("Automation", ok: !model.automation.values.contains(.denied),
                detail: automationDetail) { Permissions.openAutomationSettings() }
        }
    }

    private var automationDetail: String {
        if model.automation.isEmpty { return "asked per browser on first use" }
        return model.automation.sorted { $0.key < $1.key }
            .map { "\(Self.browserName($0.key)) \($0.value == .allowed ? "yes" : "denied")" }
            .joined(separator: ", ")
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(model.judgeAvailable ? "On-device AI judge on" : "On-device AI unavailable: unclear use is asked, not guessed",
                  systemImage: model.judgeAvailable ? "sparkles" : "sparkles.slash")
            Label(model.icloudEnabled ? "iCloud sync on" : "iCloud sync off", systemImage: model.icloudEnabled ? "icloud" : "icloud.slash")
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    private func row(_ name: String, ok: Bool, detail: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
            VStack(alignment: .leading, spacing: 0) {
                Text(name).font(.callout)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings", action: action).controlSize(.small)
        }
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
