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
        guard !list.places.isEmpty else { return String(localized: "Not set up", comment: "Settings: summary of the guarded places before setup.") }
        let places = list.places.map { place in
            place.mode == .block
                ? String(localized: "\(place.name) (block)", comment: "Settings summary: a guarded place that is blocked in work hours. The argument is the place name.")
                : String(localized: "\(place.name) (pause)", comment: "Settings summary: a guarded place that pauses. The argument is the place name.")
        }.joined(separator: ", ")
        return String(localized: "\(places) · \(list.budgetMinutes) min a day · \(hours(list.workHours))", comment: "Settings summary of the guard. First argument: the places; second: the daily budget in minutes; third: the work hours.")
    }

    static func hours(_ h: WorkHours) -> String {
        func clock(_ m: Int) -> String { String(format: "%02d:%02d", m / 60, m % 60) }
        let order = [2, 3, 4, 5, 6, 7, 1]
        let names = [
            1: String(localized: "Sun", comment: "Short weekday name."), 2: String(localized: "Mon", comment: "Short weekday name."),
            3: String(localized: "Tue", comment: "Short weekday name."), 4: String(localized: "Wed", comment: "Short weekday name."),
            5: String(localized: "Thu", comment: "Short weekday name."), 6: String(localized: "Fri", comment: "Short weekday name."),
            7: String(localized: "Sat", comment: "Short weekday name."),
        ]
        let days = order.filter { h.weekdays.contains($0) }
        let label: String
        if days == [2, 3, 4, 5, 6] {
            label = String(localized: "Mon–Fri", comment: "Work-days label.")
        } else if days.count == 7 {
            label = String(localized: "every day", comment: "Work-days label.")
        } else {
            label = days.map { names[$0] ?? "" }.joined(separator: " ")
        }
        return String(localized: "\(label) \(clock(h.start))–\(clock(h.end))", comment: "Work hours. First argument: the days; then the start and end clock times. Example: Mon–Fri 09:00–18:00.")
    }
}

extension GuardNames {
    /// "Mon–Fri 9–18": the work hours for the summary bar, hours without leading zeros.
    static func hoursShort(_ h: WorkHours) -> String {
        func clock(_ m: Int) -> String { m % 60 == 0 ? "\(m / 60)" : String(format: "%d:%02d", m / 60, m % 60) }
        let days = hours(h).split(separator: " ").dropLast().joined(separator: " ")
        return String(localized: "\(days) \(clock(h.start))–\(clock(h.end))",
                      comment: "Short work hours for the setup summary. First argument: the days; then the start and end hours. Example: Mon–Fri 9–18.")
    }

    /// "18:00": a clock time from minutes after midnight.
    static func clock(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }

    /// "this week" once 7 days are kept, "in the last 3 days" before, "today" for one day.
    static func period(days: Int) -> String {
        if days >= PlaceWeek.keptDays { return String(localized: "this week", comment: "Setup: the period the minutes on the tiles cover, once 7 days are kept.") }
        if days <= 1 { return String(localized: "today", comment: "Setup: the period the minutes on the tiles cover when only today is known.") }
        return String(localized: "in the last \(days) days", comment: "Setup: the period the minutes on the tiles cover. The argument is the number of days kept, from 2 to 6.")
    }
}

/// One tile or bar of the setup: a place, whether it is guarded, its mode, and what it took.
struct SetupRow: Identifiable, Equatable {
    var place: GuardedPlace
    var selected: Bool
    var seconds = 0
    var id: UUID { place.id }
}

/// What the setup edits before Done: the places that took the most time, the budget and the work hours.
@MainActor
@Observable
final class SetupDraft {
    static let tileCount = 6

    var rows: [SetupRow]
    var budget: Int
    var startMinutes: Int
    var endMinutes: Int
    var weekdays: Set<Int>
    var newSite = ""
    /// How many days of data the minutes cover.
    var days: Int

    init(rows: [SetupRow], budget: Int = GuardList.defaultBudgetMinutes, hours: WorkHours = WorkHours(), days: Int = 1) {
        self.rows = rows
        self.budget = budget
        startMinutes = hours.start
        endMinutes = hours.end
        weekdays = hours.weekdays
        self.days = days
    }

    convenience init(list: GuardList, proposals: [SetupProposal], days: Int) {
        var rows = list.places.map { place in
            SetupRow(place: place, selected: true, seconds: proposals.first { Self.same($0.place, place) }?.seconds ?? 0)
        }
        for proposal in proposals where !rows.contains(where: { Self.same($0.place, proposal.place) }) {
            rows.append(SetupRow(place: GuardNames.pretty(proposal.place), selected: false, seconds: proposal.seconds))
        }
        // Guarded places always stay; the rest fill the wall by minutes. Then the biggest drains come first.
        let guarded = rows.filter(\.selected)
        let others = rows.filter { !$0.selected }.prefix(max(0, Self.tileCount - guarded.count))
        rows = (guarded + others).sorted { $0.seconds > $1.seconds }
        if list.places.isEmpty {
            // A first setup starts with the three biggest drains picked, so Done works at once.
            for i in rows.indices.prefix(GuardList.maxPlaces) where rows[i].seconds > 0 { rows[i].selected = true }
        }
        self.init(rows: rows, budget: list.budgetMinutes, hours: list.workHours, days: days)
    }

    var selectedCount: Int { rows.filter(\.selected).count }
    var canSelectMore: Bool { selectedCount < GuardList.maxPlaces }
    var maxSeconds: Int { max(60, rows.map(\.seconds).max() ?? 60) }
    var period: String { GuardNames.period(days: days) }
    var untilText: String { GuardNames.clock(endMinutes) }

    var workHours: WorkHours { WorkHours(start: startMinutes, end: endMinutes, weekdays: weekdays) }

    /// "3 places · 30 min a day · Mon–Fri 9–18".
    var summary: String {
        let places = selectedCount == 1
            ? String(localized: "1 place", comment: "Setup summary: one guarded place.")
            : String(localized: "\(selectedCount) places", comment: "Setup summary: the number of guarded places.")
        return String(localized: "\(places) · \(budget) min a day · \(GuardNames.hoursShort(workHours))",
                      comment: "Setup summary bar. First argument: a phrase such as 3 places; second: the daily budget in minutes; third: the work hours.")
    }

    static func same(_ a: GuardedPlace, _ b: GuardedPlace) -> Bool {
        if let x = a.host?.lowercased(), let y = b.host?.lowercased(), x == y { return true }
        if let x = a.bundleID?.lowercased(), let y = b.bundleID?.lowercased(), x == y { return true }
        return false
    }

    /// Picks or drops a place. A fourth pick does nothing: the owner drops one first.
    func toggle(_ id: UUID) {
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
        if rows[i].selected { rows[i].selected = false } else if canSelectMore { rows[i].selected = true }
    }

    func setMode(_ id: UUID, _ mode: GuardedPlace.Mode) {
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[i].place.mode = mode
    }

    func add(_ place: GuardedPlace) {
        guard !rows.contains(where: { Self.same($0.place, place) }) else { return }
        rows.append(SetupRow(place: place, selected: canSelectMore))
    }

    func addTypedSite() {
        guard let place = GuardNames.place(fromSite: newSite) else { return }
        add(place)
        newSite = ""
    }

    /// The list Done saves. `enabled` is set by `AppModel.finishSetup`.
    func result() -> GuardList {
        var list = GuardList(budgetMinutes: budget, workHours: workHours)
        for row in rows where row.selected { list.add(row.place) }
        return list
    }
}

// MARK: - Pieces

/// A place's app icon, or a letter monogram in a stable colour.
struct PlaceIcon: View {
    var place: GuardedPlace
    var size: CGFloat

    var body: some View {
        Group {
            if let image = PlaceArt.icon(for: place) {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .fill(PlaceArt.color(for: place.name).gradient)
                    .overlay(
                        Text(verbatim: PlaceArt.monogram(place.name))
                            .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    )
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A small timer ring: what a pause is.
struct PauseGlyph: View {
    var color: Color
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.25), lineWidth: 2.5)
            Circle().trim(from: 0, to: 0.7).stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).rotationEffect(.degrees(-90))
            Text(verbatim: "5").font(.system(size: 8, weight: .bold, design: .rounded)).foregroundStyle(color)
        }
        .frame(width: 20, height: 20)
    }
}

/// The two-state control on a picked place: pause (a timer ring) or block (a lock, until 18:00).
struct ModeChoice: View {
    var mode: GuardedPlace.Mode
    var until: String
    var vertical: Bool
    var onSelect: (GuardedPlace.Mode) -> Void

    var body: some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 8))
        layout {
            option(.pause)
            option(.block)
        }
    }

    private func option(_ value: GuardedPlace.Mode) -> some View {
        let on = mode == value
        let tint = on ? Color.accentColor : Color.secondary
        return Button { onSelect(value) } label: {
            HStack(spacing: 8) {
                if value == .pause {
                    PauseGlyph(color: tint)
                } else {
                    Image(systemName: "lock.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(tint).frame(width: 20, height: 20)
                }
                VStack(alignment: .leading, spacing: 0) {
                    if value == .pause {
                        Text("Pause", comment: "Setup: the place waits 5 seconds each time it opens.").font(.callout.weight(.semibold))
                        Text("5 s wait", comment: "Setup: caption under Pause. The wait before the place opens.").font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Text("Block", comment: "Setup: the place stays closed in work hours.").font(.callout.weight(.semibold))
                        Text("until \(until)", comment: "Setup: caption under Block. The argument is the clock time the work hours end, such as 18:00.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(on ? Color.primary : Color.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(on ? Color.accentColor.opacity(0.16) : Color.gray.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(on ? Color.accentColor : .clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The adjust card behind "Change": the budget and the work hours. Both are already set.
struct SetupAdjust: View {
    @Bindable var draft: SetupDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Daily budget", comment: "Setup adjust card: row label for the daily waste budget.")
                Spacer()
                Stepper(value: $draft.budget, in: 5...240, step: 5) {
                    Text("\(draft.budget) min a day", comment: "Setup adjust card: the daily budget in minutes.").monospacedDigit()
                }
                .fixedSize()
            }
            HStack {
                Text("Work hours", comment: "Setup adjust card: row label for the work hours.")
                Spacer()
                DatePicker("", selection: timeBinding(\.startMinutes), displayedComponents: .hourAndMinute).labelsHidden()
                Text("to", comment: "Setup adjust card: between the start and end time of the work hours.").foregroundStyle(.secondary)
                DatePicker("", selection: timeBinding(\.endMinutes), displayedComponents: .hourAndMinute).labelsHidden()
            }
            HStack(spacing: 4) {
                ForEach(Self.weekdays, id: \.number) { day in
                    let on = draft.weekdays.contains(day.number)
                    Button {
                        if on { draft.weekdays.remove(day.number) } else { draft.weekdays.insert(day.number) }
                    } label: {
                        Text(verbatim: day.name)
                            .font(.system(size: 12, weight: on ? .semibold : .regular))
                            .foregroundStyle(on ? Color.white : Color.secondary)
                            .frame(width: 40, height: 24)
                            .background(Capsule().fill(on ? Color.accentColor : Color.gray.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    private static let weekdays: [(number: Int, name: String)] = [
        (2, String(localized: "Mon", comment: "Short weekday name.")), (3, String(localized: "Tue", comment: "Short weekday name.")),
        (4, String(localized: "Wed", comment: "Short weekday name.")), (5, String(localized: "Thu", comment: "Short weekday name.")),
        (6, String(localized: "Fri", comment: "Short weekday name.")), (7, String(localized: "Sat", comment: "Short weekday name.")),
        (1, String(localized: "Sun", comment: "Short weekday name.")),
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

// MARK: - The setup

/// "What should Vago guard?" Variant A is a wall of tiles, variant B the week ranked as bars.
/// Both: tap up to three places; a picked place shows its pause / block control; the budget and the
/// work hours are already set and sit behind one "Change" control; Done works at once.
struct SetupContent: View {
    @Bindable var draft: SetupDraft
    var variant: Variant
    @State private var showAdjust = false
    @State private var adding = false
    var onDone: @MainActor () -> Void
    var onCancel: @MainActor () -> Void

    init(draft: SetupDraft, variant: Variant, adding: Bool = false,
         onDone: @escaping @MainActor () -> Void = {}, onCancel: @escaping @MainActor () -> Void = {}) {
        self.draft = draft
        self.variant = variant
        _adding = State(initialValue: adding)
        self.onDone = onDone
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if draft.rows.isEmpty {
                Text("Nothing seen yet. Add a site you lose time on.", comment: "Setup empty state before any waste was seen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else if variant == .a {
                wall
            } else {
                ranked
            }
            addSite
            if !draft.canSelectMore {
                Text("Three is the most. Tap a picked place to swap it.", comment: "Setup hint once three places are picked.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            summaryBar
        }
        .padding(24)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("What should Vago guard?", comment: "Setup title.").font(.title2.weight(.semibold))
            Text("Tap up to three places. Time spent \(draft.period).", comment: "Setup subtitle. The argument is a period such as this week or in the last 3 days.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Variant A: a wall of tiles

    private var wall: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
            ForEach($draft.rows) { $row in
                tile($row)
            }
        }
    }

    private func tile(_ row: Binding<SetupRow>) -> some View {
        let value = row.wrappedValue
        let blocked = !value.selected && !draft.canSelectMore
        return ZStack {
            if value.selected {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        PlaceIcon(place: value.place, size: 22)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(verbatim: value.place.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                            if value.seconds > 0 {
                                Text(verbatim: Format.minutes(value.seconds)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        Button { withAnimation(.snappy(duration: 0.2)) { draft.toggle(value.id) } } label: {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                                .font(.title3).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(Text("Stop guarding this place", comment: "Setup: tooltip of the check on a picked tile; a click unpicks it."))
                        .accessibilityLabel(Text("Stop guarding \(value.place.name)", comment: "Setup: accessibility label of the check on a picked tile."))
                    }
                    ModeChoice(mode: value.place.mode, until: draft.untilText, vertical: true) { draft.setMode(value.id, $0) }
                }
                .padding(10)
            } else {
                Button { withAnimation(.snappy(duration: 0.2)) { draft.toggle(value.id) } } label: {
                    VStack(spacing: 8) {
                        PlaceIcon(place: value.place, size: 52)
                        Text(verbatim: value.place.name).font(.headline).lineLimit(1)
                        Text(verbatim: value.seconds > 0 ? Format.minutes(value.seconds) : " ")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 148)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(value.selected ? Color.accentColor.opacity(0.08) : Color.gray.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(value.selected ? Color.accentColor : .clear, lineWidth: 2))
        .opacity(blocked ? 0.6 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: value.place.name))
    }

    // MARK: Variant B: your week, ranked

    private var ranked: some View {
        VStack(spacing: 8) {
            ForEach($draft.rows) { $row in
                bar($row)
            }
        }
    }

    private func bar(_ row: Binding<SetupRow>) -> some View {
        let value = row.wrappedValue
        let blocked = !value.selected && !draft.canSelectMore
        let color = value.selected ? Color.accentColor : PlaceArt.color(for: value.place.name)
        let fraction = value.seconds > 0 ? max(0.06, Double(value.seconds) / Double(draft.maxSeconds)) : 0.02
        return VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.snappy(duration: 0.2)) { draft.toggle(value.id) } } label: {
                HStack(spacing: 12) {
                    PlaceIcon(place: value.place, size: 34)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(verbatim: value.place.name).font(.headline).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(verbatim: value.seconds > 0 ? Format.minutes(value.seconds) : " ")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        GeometryReader { geo in
                            Capsule().fill(Color.gray.opacity(0.14))
                                .overlay(alignment: .leading) { Capsule().fill(color).frame(width: geo.size.width * fraction) }
                        }
                        .frame(height: 10)
                    }
                    Image(systemName: value.selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(value.selected ? Color.accentColor : Color.secondary.opacity(0.5))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if value.selected {
                ModeChoice(mode: value.place.mode, until: draft.untilText, vertical: false) { draft.setMode(value.id, $0) }
                    .padding(.leading, 46)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(value.selected ? Color.accentColor.opacity(0.07) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(value.selected ? Color.accentColor.opacity(0.6) : Color.gray.opacity(0.18), lineWidth: 1))
        .opacity(blocked ? 0.65 : 1)
    }

    // MARK: Shared

    @ViewBuilder
    private var addSite: some View {
        if adding {
            HStack(spacing: 8) {
                TextField("A site, for example reddit.com", text: $draft.newSite)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTyped)
                Button("Add", action: addTyped).disabled(GuardNames.place(fromSite: draft.newSite) == nil)
            }
        } else {
            Button { adding = true } label: {
                Label { Text("Add a site", comment: "Setup: small button that reveals a field to add a site that is not proposed.") } icon: { Image(systemName: "plus") }
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private func addTyped() {
        draft.addTypedSite()
        adding = false
    }

    private var summaryBar: some View {
        VStack(spacing: 12) {
            Divider()
            HStack(spacing: 10) {
                Text(verbatim: draft.summary).font(.callout).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.85)
                Button { showAdjust = true } label: {
                    Text("Change", comment: "Setup: opens the budget and work-hours card.").font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .popover(isPresented: $showAdjust, arrowEdge: .top) { SetupAdjust(draft: draft) }
                Spacer(minLength: 8)
                Button(action: onCancel) { Text("Cancel", comment: "Button that closes a dialog or window without saving.") }
                    .keyboardShortcut(.cancelAction)
                Button(action: onDone) { Text("Done", comment: "Button that finishes a flow.").frame(width: 84) }
                    .buttonStyle(FilledCloseStyle())
                    .frame(width: 84)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.selectedCount == 0)
            }
        }
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
        let wall = model.variants.setup == .a
        return HostedWindow(title: String(localized: "Guarded places", comment: "Title of the setup window."),
                            size: NSSize(width: wall ? 600 : 540, height: wall ? 570 : 760),
                            minSize: NSSize(width: 520, height: 520), resizable: true, autosaveName: "VagoSetup2") { host in
            AnyView(SetupHost(model: model, close: { host.close() }))
        }
    }
}
