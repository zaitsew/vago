import FamilyControls
import SwiftUI
import VagoKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: SelectionKind?

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    ForEach(SelectionKind.allCases) { kind in
                        Button {
                            editing = kind
                        } label: {
                            HStack {
                                Text(kind.title)
                                Spacer()
                                Text(summary(model.count(kind))).foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                            }
                        }
                        .tint(.primary)
                    }
                } header: {
                    Text("Apps")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Both work and scroll apps ask “Work or scroll?” before they open. An app you pick in a more specific list wins: Work beats Both, and Both beats Procrastination.")
                        if model.categoryOverlap {
                            Label("A whole category in a broad list also contains apps from a narrower list, and those minutes are counted twice. Pick single apps instead of categories where you can.", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Section {
                    LabeledContent("Limit today", value: "\(model.limit.current) min")
                    LabeledContent("Baseline") {
                        if let baseline = model.limit.baseline {
                            Text("\(baseline) min")
                        } else {
                            Text("Day \(model.calibrationDay ?? 1) of \(AdaptiveLimit.calibrationDays)")
                        }
                    }
                } header: {
                    Text("Daily limit")
                } footer: {
                    Text("Your limit starts at 60 minutes while Vago learns your habits for three days, then settles at your typical day. It drops 5 minutes after every day you stay under it, rises 5 after a day well over it, and never goes below 30 minutes.")
                }

                Section("iCloud") {
                    LabeledContent("Account", value: model.iCloudSignedIn ? "Signed in" : "Not signed in")
                    LabeledContent("Mac", value: model.snapshot.mac == nil ? "No data yet" : "Syncing")
                }

                Section("Live Activity") {
                    Toggle("Show on Lock Screen", isOn: Binding(
                        get: { model.store.liveActivityEnabled },
                        set: { model.setLiveActivityEnabled($0) }
                    ))
                }

                Section {
                    LabeledContent("Screen Time access", value: model.authorized ? "Allowed" : "Not allowed")
                    LabeledContent("Last report", value: lastReport)
                    Button("Restart counting") { model.restartMonitoring() }
                    if let message = model.errorMessage {
                        Text(message).font(.footnote).foregroundStyle(.red)
                    }
                } header: {
                    Text("Counting")
                } footer: {
                    Text("Screen Time reports usage in steps of a minute, and sometimes late. If “Last report” stays empty while you use a listed app, restart counting.")
                }
            }
            .navigationTitle("Settings")
            .sheet(item: $editing, onDismiss: { model.restartMonitoring() }) { kind in
                PickerSheet(kind: kind)
            }
        }
    }

    private var lastReport: String {
        guard let date = model.counters.lastEventAt else { return "None today" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func summary(_ count: Int) -> String {
        count == 0 ? "None" : "\(count) selected"
    }
}

/// The system picker for one of the three lists.
struct PickerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let kind: SelectionKind

    var body: some View {
        NavigationStack {
            FamilyActivityPicker(selection: Binding(
                get: { model.binding(for: kind) },
                set: { model.setSelection($0, for: kind) }
            ))
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
