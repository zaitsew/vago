import SwiftUI
import VagoKit
import WidgetKit

/// Today's procrastination against the limit: `Readout.short`, tinted by mood.
struct UsageWidget: Widget {
    let kind = "VagoUsage"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageProvider()) { entry in
            UsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Procrastination today")
        .description("Minutes lost today against your limit.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: .now, snapshot: Snapshot(day: DayKey.of(.now), procrastination: 12 * 60, productive: 0,
                                                  focus: 0, iphone: nil, mac: nil, limitMinutes: 30))
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        // The monitor reloads this timeline at every threshold. The 15-minute refresh is the
        // fallback for when the system skips those reloads (the widget reload budget).
        completion(Timeline(entries: [entry()], policy: .after(.now.addingTimeInterval(15 * 60))))
    }

    private func entry() -> UsageEntry {
        UsageEntry(date: .now, snapshot: VagoStore().snapshot())
    }
}

struct UsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    private var snapshot: Snapshot { entry.snapshot }
    private var tint: Color { snapshot.mood.tint.color }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: min(snapshot.share, 1)) {
                Text(snapshot.mood.emoji)
            } currentValueLabel: {
                Text("\(snapshot.minutesUsed)")
            }
            .gaugeStyle(.accessoryCircular)
            .tint(tint)
            .containerBackground(.fill.tertiary, for: .widget)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.readout).font(.headline)
                Gauge(value: min(snapshot.share, 1)) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(tint)
                Text("of \(snapshot.limitMinutes) min today").font(.caption2).foregroundStyle(.secondary)
            }
            .containerBackground(.fill.tertiary, for: .widget)
        case .accessoryInline:
            Text(snapshot.readout)
                .containerBackground(.fill.tertiary, for: .widget)
        default:
            VStack(spacing: 6) {
                Text(snapshot.mood.emoji).font(.system(size: 44))
                Text("\(snapshot.minutesUsed) / \(snapshot.limitMinutes) min")
                    .font(.headline.monospacedDigit())
                ProgressView(value: min(snapshot.share, 1)).tint(tint)
                Text("procrastination").font(.caption2).foregroundStyle(.secondary)
            }
            .containerBackground(for: .widget) { tint.opacity(0.14) }
        }
    }
}
