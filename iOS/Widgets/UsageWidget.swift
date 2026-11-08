import SwiftUI
import VagoKit
import WidgetKit

/// Today's productive share and timeline across devices, tinted by the share.
/// The kind stays "VagoUsage" so widgets already on a Home Screen keep working.
struct UsageWidget: Widget {
    let kind = "VagoUsage"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageProvider()) { entry in
            UsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Vago — today")
        .description("Productive share and today's timeline across your devices.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        var mac = (0..<DayKey.hoursPerDay).map { HourSlot(slot: $0) }
        var phone = mac
        for slot in 3...9 { mac[slot] = HourSlot(slot: slot, productive: 2400, procrastination: 300, neutral: 600) }
        for slot in 5...9 { phone[slot] = HourSlot(slot: slot, procrastination: 420) }
        return UsageEntry(date: .now, snapshot: Snapshot(
            day: DayKey.of(.now), procrastination: 12 * 60, productive: 3 * 3600, focus: 0, iphone: nil, mac: nil,
            limitMinutes: 30, share: ProductiveShare(productive: 3 * 3600, neutral: 1800, procrastination: 12 * 60),
            macHours: mac, iphoneHours: phone
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        // The monitor reloads this timeline at every threshold. The 15-minute refresh is the
        // fallback for when the system skips those reloads (the widget reload budget), and it
        // is also when the Mac's day is read from iCloud again.
        completion(Timeline(entries: [entry()], policy: .after(.now.addingTimeInterval(15 * 60))))
    }

    /// The App Group ledger with the Mac's day pulled from iCloud's key-value store, so the Mac's
    /// minutes appear without the app being opened. Not written back: the monitor owns the stored ledger.
    private func entry() -> UsageEntry {
        let now = Date()
        let store = VagoStore()
        var ledger = store.ledger()
        CloudRead.mergeMac(into: &ledger, today: DayKey.of(now))
        return UsageEntry(date: now, snapshot: store.snapshot(now: now, ledger: ledger))
    }
}

struct UsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    private var snapshot: Snapshot { entry.snapshot }
    private var share: ProductiveShare { snapshot.share }
    private var tint: Color { share.tint?.color ?? Color.secondary }
    private var wasteLine: String { "\(snapshot.minutesUsed)/\(snapshot.limitMinutes)m waste" }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(share.percent ?? 0), in: 0...100) {
                Text("%")
            } currentValueLabel: {
                Text(share.percent.map(String.init) ?? "—").monospacedDigit()
            }
            .gaugeStyle(.accessoryCircular)
            .containerBackground(.fill.tertiary, for: .widget)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(share.percent.map { "\($0)% productive" } ?? "— productive")
                    .font(.headline.monospacedDigit())
                Gauge(value: min(snapshot.limitFill, 1)) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
                Text(wasteLine).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            .containerBackground(.fill.tertiary, for: .widget)
        case .accessoryInline:
            Text("\(share.text) · \(snapshot.minutesUsed)/\(snapshot.limitMinutes)m")
                .monospacedDigit()
                .containerBackground(.fill.tertiary, for: .widget)
        case .systemMedium:
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(share.text)
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .foregroundStyle(tint)
                    Text(caption)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    Spacer(minLength: 0)
                    HStack(spacing: 4) {
                        Text(snapshot.mood.emoji)
                        Text(wasteLine).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 6) {
                    DayStrip(mac: snapshot.macHours, iphone: snapshot.iphoneHours,
                             interactive: false, laneHeight: 30, spacing: 1.5)
                    Spacer(minLength: 0)
                    Text("updated \((snapshot.updatedAt ?? entry.date).formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
            }
            .containerBackground(for: .widget) { tint.opacity(0.14) }
        default:
            VStack(alignment: .leading, spacing: 4) {
                Text(share.text)
                    .font(.system(size: 50, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(tint)
                Text(share.percent == nil ? "building today's picture" : "productive")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Text(snapshot.mood.emoji)
                    Text(wasteLine).monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.footnote)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(for: .widget) { tint.opacity(0.14) }
        }
    }

    private var caption: String {
        guard share.percent != nil else { return "Building today's picture" }
        return "\(Spoken.duration(share.productive)) work · \(Spoken.duration(share.procrastination)) waste"
    }
}
