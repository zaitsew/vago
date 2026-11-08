import AppKit
import SwiftUI
import VagoKit

/// The day across devices: the productive share, the hours, where the time went, and Vago's
/// calls with a one-tap correction. Past days show the share and the hours only: sessions are
/// kept for today.
@MainActor
enum DayWindow {
    static func make(model: AppModel) -> HostedWindow {
        HostedWindow(title: "Today", size: NSSize(width: 720, height: 560), minSize: NSSize(width: 600, height: 440),
                     resizable: true, autosaveName: "VagoDay") { window in
            AnyView(DayView(model: model) { [weak window] title in window?.setTitle(title) })
        }
    }
}

struct DayView: View {
    let model: AppModel
    let setTitle: @MainActor (String) -> Void

    /// nil follows today, also across the 04:00 change.
    @State private var picked: DayKey?
    @State private var filter: DeviceFilter = .all

    enum DeviceFilter: String, CaseIterable, Identifiable {
        case all = "All", mac = "Mac", iphone = "iPhone"
        var id: String { rawValue }
        var devices: [Device] {
            switch self {
            case .all: [.mac, .iphone]
            case .mac: [.mac]
            case .iphone: [.iphone]
            }
        }
    }

    private var day: DayKey { picked ?? model.today.day }
    private var isToday: Bool { day == model.today.day }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                hero
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        DayStrip(
                            lanes: DayStrip.lanes(model.ledger, day: day, devices: filter.devices, notes: true),
                            laneHeight: 64,
                            labelWidth: 52,
                            cellSpacing: 4,
                            tooltips: true,
                            labelEvery: 2,
                            nowSlot: isToday ? DayKey.hourSlot(of: model.clock) : nil
                        )
                        Legend()
                    }
                    .padding(8)
                }
                if isToday {
                    HStack(alignment: .top, spacing: 16) {
                        TopList(title: "Top waste", rows: model.top(.procrastination), color: Palette.waste)
                        TopList(title: "Top work", rows: model.top(.productive), color: Palette.work)
                    }
                    CallsList(model: model)
                } else {
                    Text("Sites, apps and Vago's calls are kept for today only.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { setTitle(Format.dayTitle(day)) }
        .onChange(of: day) { _, new in setTitle(Format.dayTitle(new)) }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Button { go(earlier) } label: { Image(systemName: "chevron.left") }
                .disabled(earlier == nil)
                .help("Previous day")
            Button { go(later) } label: { Image(systemName: "chevron.right") }
                .disabled(isToday)
                .help("Next day")
            Text(isToday ? "Today" : Format.dayTitle(day))
                .font(.title2.weight(.semibold))
                .padding(.leading, 4)
            if !isToday {
                Button("Today") { picked = nil }.controlSize(.small)
            }
            Spacer()
            Picker("Devices", selection: $filter) {
                ForEach(DeviceFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .buttonStyle(.bordered)
    }

    private var earlier: DayKey? { model.ledger.trackedDays().last { $0 < day } }

    private var later: DayKey? {
        guard !isToday else { return nil }
        return model.ledger.trackedDays().first { $0 > day && $0 < model.today.day } ?? model.today.day
    }

    private func go(_ target: DayKey?) {
        guard let target else { return }
        picked = target == model.today.day ? nil : target
    }

    // MARK: Hero

    private var hero: some View {
        let share = model.ledger.share(for: day, devices: filter.devices)
        return HStack(alignment: .center, spacing: 20) {
            Text(share.text)
                .font(.system(size: 56, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Palette.color(share.tint))
            VStack(alignment: .leading, spacing: 4) {
                Text(filter == .all ? "productive, all devices" : "productive on the \(filter.rawValue)")
                    .font(.headline)
                Text(Format.caption(share))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isToday {
                let used = model.totals.procrastination
                VStack(alignment: .trailing, spacing: 4) {
                    Text(model.mood.emoji).font(.system(size: 28))
                    Text("\(used / 60) of \(model.limit.current) min waste")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Legend

private struct Legend: View {
    var body: some View {
        HStack(spacing: 16) {
            item("Work", AnyShapeStyle(Palette.work))
            item("Neutral", Palette.neutral)
            item("Waste", AnyShapeStyle(Palette.waste))
            Spacer()
            Text("A full cell is a full hour. Hover for minutes.")
                .foregroundStyle(.tertiary)
        }
        .font(.caption)
    }

    private func item(_ name: String, _ style: AnyShapeStyle) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(style).frame(width: 10, height: 10)
            Text(name).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Top lists

private struct TopList: View {
    let title: String
    let rows: [(label: String, seconds: Int)]
    let color: Color

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.headline)
                    Spacer()
                    Text("Mac only").font(.caption).foregroundStyle(.tertiary)
                }
                if rows.isEmpty {
                    Text("Nothing yet today").font(.callout).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                } else {
                    let most = max(1, rows.first?.seconds ?? 1)
                    ForEach(rows, id: \.label) { row in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(row.label).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(Format.duration(row.seconds)).monospacedDigit().foregroundStyle(.secondary)
                            }
                            .font(.callout)
                            Capsule()
                                .fill(color.opacity(0.75))
                                .frame(height: 3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .scaleEffect(x: CGFloat(row.seconds) / CGFloat(most), y: 1, anchor: .leading)
                        }
                    }
                }
            }
            .padding(8)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Vago's calls

private struct CallsList: View {
    let model: AppModel

    var body: some View {
        let calls = model.calls
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Vago's calls").font(.headline)
                    Text("Mac · today").font(.caption).foregroundStyle(.tertiary)
                    Spacer()
                    if !model.judgeAvailable {
                        Label("AI unavailable", systemImage: "sparkles.slash").font(.caption).foregroundStyle(.secondary)
                    } else if model.judgeHeld {
                        Label("AI held", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                            .help("Its work calls on mixed apps count as neutral today. A correction lifts the hold.")
                    }
                }
                Text("Vago decided these places on its own. Change one and its minutes move; the place gets a rule.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if calls.isEmpty {
                    Text("No calls yet today.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(Array(calls.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider() }
                        CallRow(item: item) { model.correctCall(item, as: $0) }
                    }
                }
            }
            .padding(8)
        }
    }
}

private struct CallRow: View {
    let item: CallItem
    let correct: (Bucket) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.label).font(.body.weight(.medium)).lineLimit(1).truncationMode(.middle)
                    if item.unsure { Badge(text: "unsure", color: .orange) }
                    if item.corrected { Badge(text: "corrected", color: .secondary) }
                }
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(Format.duration(item.seconds))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Picker("Count as", selection: Binding(get: { selection }, set: { correct($0) })) {
                Text("Work").tag(Bucket.productive)
                Text("Neutral").tag(Bucket.neutral)
                Text("Waste").tag(Bucket.procrastination)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 210)
        }
        .padding(.vertical, 2)
    }

    private var selection: Bucket { item.bucket == .ambiguous ? .procrastination : item.bucket }

    private var reason: String {
        if item.reason == CallReason.corrected { return "You corrected this call." }
        let text = Format.reason(item.reason)
        return item.unsure ? "Unsure: \(text)" : "AI: \(text)"
    }
}

private struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.15)))
    }
}
