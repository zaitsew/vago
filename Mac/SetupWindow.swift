import AppKit
import Observation
import SwiftUI
import VagoKit

/// Names for guarded places: "instagram.com" reads as "Instagram".
enum GuardNames {
    private static let known = [
        "youtube": "YouTube", "tiktok": "TikTok", "linkedin": "LinkedIn", "x": "X", "twitter": "Twitter",
        "netflix": "Netflix", "twitch": "Twitch", "reddit": "Reddit", "facebook": "Facebook", "instagram": "Instagram",
        "telegram": "Telegram", "whatsapp": "WhatsApp", "discord": "Discord", "pinterest": "Pinterest",
    ]

    static func pretty(host: String) -> String {
        let parts = host.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return host.capitalized }
        let label = parts[parts.count - 2]
        return known[label] ?? (label.prefix(1).uppercased() + label.dropFirst())
    }

    static func pretty(_ place: GuardedPlace) -> GuardedPlace {
        var place = place
        if let host = place.host { place.name = pretty(host: host) }
        return place
    }

    static func place(from sample: ActivitySample) -> GuardedPlace {
        if let host = sample.host { return GuardedPlace(name: pretty(host: host), host: host) }
        return GuardedPlace(name: sample.appName, bundleID: sample.bundleID)
    }

    /// "https://www.Instagram.com/reels" becomes the place instagram.com; nil when it is not a host.
    static func place(fromSite text: String) -> GuardedPlace? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["https://", "http://"] where t.hasPrefix(prefix) { t.removeFirst(prefix.count) }
        if let slash = t.firstIndex(of: "/") { t = String(t[..<slash]) }
        if t.hasPrefix("www.") { t.removeFirst(4) }
        guard t.contains("."), !t.contains(" "), !t.hasSuffix("."), !t.hasPrefix(".") else { return nil }
        return GuardedPlace(name: pretty(host: t), host: t)
    }

    /// "Instagram (pause), YouTube (block) · 30 min a day · Mon–Fri 09:00–18:00".
    static func summary(_ list: GuardList) -> String {
        guard !list.places.isEmpty else { return "Not set up" }
        let places = list.places.map { "\($0.name) (\($0.mode == .block ? "block" : "pause"))" }.joined(separator: ", ")
        return "\(places) · \(list.budgetMinutes) min a day · \(hours(list.workHours))"
    }

    static func hours(_ h: WorkHours) -> String {
        func clock(_ m: Int) -> String { String(format: "%02d:%02d", m / 60, m % 60) }
        let order = [2, 3, 4, 5, 6, 7, 1]
        let names = [1: "Sun", 2: "Mon", 3: "Tue", 4: "Wed", 5: "Thu", 6: "Fri", 7: "Sat"]
        let days = order.filter { h.weekdays.contains($0) }
        let label: String
        if days == [2, 3, 4, 5, 6] {
            label = "Mon–Fri"
        } else if days.count == 7 {
            label = "every day"
        } else {
            label = days.map { names[$0] ?? "" }.joined(separator: " ")
        }
        return "\(label) \(clock(h.start))–\(clock(h.end))"
    }
}

/// One line of the setup: a place, whether it is guarded, and its mode.
struct SetupRow: Identifiable, Equatable {
    var place: GuardedPlace
    var selected: Bool
    var id: UUID { place.id }
}

/// What the setup edits before Done: proposals from today's sessions, the budget and the work hours.
@MainActor
@Observable
final class SetupDraft {
    var rows: [SetupRow]
    var budget: Int
    var startMinutes: Int
    var endMinutes: Int
    var weekdays: Set<Int>
    var newSite = ""
    /// The place in front, offered as "Add Instagram".
    var front: GuardedPlace?

    init(rows: [SetupRow], budget: Int = GuardList.defaultBudgetMinutes, hours: WorkHours = WorkHours(), front: GuardedPlace? = nil) {
        self.rows = rows
        self.budget = budget
        startMinutes = hours.start
        endMinutes = hours.end
        weekdays = hours.weekdays
        self.front = front
    }

    convenience init(list: GuardList, proposals: [GuardedPlace], front: ActivitySample?) {
        var rows = list.places.map { SetupRow(place: $0, selected: true) }
        for proposal in proposals where !rows.contains(where: { Self.same($0.place, proposal) }) {
            // A first setup starts with every proposal ticked; later, only what is already guarded.
            rows.append(SetupRow(place: GuardNames.pretty(proposal), selected: list.places.isEmpty))
        }
        let frontPlace = front.map(GuardNames.place(from:)).flatMap { place in
            rows.contains(where: { Self.same($0.place, place) }) ? nil : place
        }
        self.init(rows: rows, budget: list.budgetMinutes, hours: list.workHours, front: frontPlace)
    }

    var selectedCount: Int { rows.filter(\.selected).count }
    var canSelectMore: Bool { selectedCount < GuardList.maxPlaces }

    static func same(_ a: GuardedPlace, _ b: GuardedPlace) -> Bool {
        if let x = a.host?.lowercased(), let y = b.host?.lowercased(), x == y { return true }
        if let x = a.bundleID?.lowercased(), let y = b.bundleID?.lowercased(), x == y { return true }
        return false
    }

    func add(_ place: GuardedPlace) {
        guard !rows.contains(where: { Self.same($0.place, place) }) else { return }
        rows.append(SetupRow(place: place, selected: canSelectMore))
        if let front, Self.same(front, place) { self.front = nil }
    }

    func addTypedSite() {
        guard let place = GuardNames.place(fromSite: newSite) else { return }
        add(place)
        newSite = ""
    }

    /// The list Done saves. `enabled` is set by `AppModel.finishSetup`.
    func result() -> GuardList {
        var list = GuardList(budgetMinutes: budget, workHours: WorkHours(start: startMinutes, end: endMinutes, weekdays: weekdays))
        for row in rows where row.selected { list.add(row.place) }
        return list
    }
}

/// "Guarded places": variant A is one page, variant B is three steps.
struct SetupContent: View {
    @Bindable var draft: SetupDraft
    var variant: Variant
    @State private var step: Int
    var onDone: @MainActor () -> Void
    var onCancel: @MainActor () -> Void

    init(draft: SetupDraft, variant: Variant, step: Int = 1,
         onDone: @escaping @MainActor () -> Void = {}, onCancel: @escaping @MainActor () -> Void = {}) {
        self.draft = draft
        self.variant = variant
        _step = State(initialValue: step)
        self.onDone = onDone
        self.onCancel = onCancel
    }

    var body: some View {
        Group {
            if variant == .a { onePage } else { threeSteps }
        }
        .padding(24)
    }

    // MARK: Variant A: one page

    private var onePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("Guarded places", "Pick up to three places that eat your day. Each one pauses you or blocks you.")
            placesList(withModes: true)
            addRow
            Text("Pause: a 5-second pause every time it opens. Block: it stays closed in your work hours, and pauses outside them.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            budgetRow
            hoursRow
            Spacer(minLength: 0)
            HStack {
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.selectedCount == 0)
            }
        }
    }

    // MARK: Variant B: three steps

    private var threeSteps: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                ForEach(1...3, id: \.self) { n in
                    Capsule().fill(n <= step ? Color.accentColor : Color.secondary.opacity(0.25)).frame(height: 4)
                }
            }
            Text("Step \(step) of 3").font(.caption).foregroundStyle(.secondary)
            switch step {
            case 1:
                header("Which places?", "Pick up to three places that eat your day.")
                placesList(withModes: false)
                addRow
            case 2:
                header("Pause or block?", "Choose for each place.")
                ForEach($draft.rows) { $row in
                    if row.selected { modeChoice($row) }
                }
            default:
                header("Budget and hours", "A daily budget of waste, and the hours when blocked places stay closed.")
                budgetRow
                hoursRow
            }
            Spacer(minLength: 0)
            HStack {
                if step == 1 {
                    Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                } else {
                    Button("Back") { step -= 1 }
                }
                Spacer()
                if step < 3 {
                    Button("Next") { step += 1 }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(draft.selectedCount == 0)
                } else {
                    Button("Done", action: onDone)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(draft.selectedCount == 0)
                }
            }
        }
    }

    private func modeChoice(_ row: Binding<SetupRow>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(row.wrappedValue.place.name).font(.headline)
            Picker("", selection: row.place.mode) {
                Text("Pause. A 5-second pause each time it opens, all day.")
                    .tag(GuardedPlace.Mode.pause)
                Text("Block in work hours. It does not open in your work hours; unlocking takes a deliberate step.")
                    .tag(GuardedPlace.Mode.block)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
        }
    }

    // MARK: Shared pieces

    private func header(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.title2.weight(.semibold))
            Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func placesList(withModes: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if draft.rows.isEmpty {
                Text("Nothing to propose yet. Add a site below.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach($draft.rows) { $row in
                HStack(spacing: 10) {
                    Toggle(isOn: $row.selected) { Text(row.place.name) }
                        .disabled(!row.selected && !draft.canSelectMore)
                    Spacer(minLength: 8)
                    if withModes {
                        Picker("", selection: $row.place.mode) {
                            Text("Pause").tag(GuardedPlace.Mode.pause)
                            Text("Block").tag(GuardedPlace.Mode.block)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 140)
                        .disabled(!row.selected)
                    }
                }
            }
        }
    }

    private var addRow: some View {
        HStack(spacing: 8) {
            TextField("Add a site, for example reddit.com", text: $draft.newSite)
                .textFieldStyle(.roundedBorder)
                .onSubmit { draft.addTypedSite() }
            Button("Add") { draft.addTypedSite() }
                .disabled(GuardNames.place(fromSite: draft.newSite) == nil)
            if let front = draft.front {
                Button("Add \(front.name)") { draft.add(front) }
            }
        }
    }

    private var budgetRow: some View {
        HStack {
            Text("Daily budget")
            Spacer()
            Stepper(value: $draft.budget, in: 5...240, step: 5) {
                Text("\(draft.budget) min a day").monospacedDigit()
            }
            .fixedSize()
        }
    }

    private var hoursRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Work hours")
                Spacer()
                DatePicker("", selection: timeBinding(\.startMinutes), displayedComponents: .hourAndMinute).labelsHidden()
                Text("to").foregroundStyle(.secondary)
                DatePicker("", selection: timeBinding(\.endMinutes), displayedComponents: .hourAndMinute).labelsHidden()
            }
            HStack(spacing: 4) {
                ForEach(Self.weekdays, id: \.number) { day in
                    Toggle(day.name, isOn: Binding(
                        get: { draft.weekdays.contains(day.number) },
                        set: { on in
                            if on { draft.weekdays.insert(day.number) } else { draft.weekdays.remove(day.number) }
                        }
                    ))
                    .toggleStyle(.button)
                    .controlSize(.small)
                }
                Spacer()
            }
        }
    }

    private static let weekdays: [(number: Int, name: String)] = [
        (2, "Mon"), (3, "Tue"), (4, "Wed"), (5, "Thu"), (6, "Fri"), (7, "Sat"), (1, "Sun"),
    ]

    private func timeBinding(_ path: ReferenceWritableKeyPath<SetupDraft, Int>) -> Binding<Date> {
        Binding(
            get: {
                let m = draft[keyPath: path]
                return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                draft[keyPath: path] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }
}

/// Fills the setup from the model and hands the result back.
struct SetupHost: View {
    let model: AppModel
    let close: @MainActor () -> Void
    @State private var draft: SetupDraft

    init(model: AppModel, close: @escaping @MainActor () -> Void) {
        self.model = model
        self.close = close
        _draft = State(initialValue: model.makeSetupDraft())
    }

    var body: some View {
        SetupContent(draft: draft, variant: model.variants.setup, onDone: {
            model.finishSetup(draft.result())
            close()
        }, onCancel: close)
    }
}

@MainActor
enum SetupWindow {
    static func make(model: AppModel) -> HostedWindow {
        let tall = model.variants.setup == .a
        return HostedWindow(title: "Guarded places", size: NSSize(width: 480, height: tall ? 560 : 500),
                            minSize: NSSize(width: 440, height: 440), resizable: true, autosaveName: "VagoSetup") { host in
            AnyView(SetupHost(model: model, close: { host.close() }))
        }
    }
}
