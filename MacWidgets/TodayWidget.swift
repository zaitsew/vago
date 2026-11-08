import SwiftUI
import VagoKit
import WidgetKit

/// "Vago — today": the productive share across devices. The Mac app writes `widget.json`
/// (`WidgetSnapshot`); this only reads it.
struct TodayWidget: Widget {
    let kind = "VagoMacToday"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .widgetURL(URL(string: "vago://day"))
        }
        .configurationDisplayName("Vago — today")
        .description("Your productive share today, across your Mac and iPhone.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, snapshot: .sample(at: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : TodayEntry(date: .now, snapshot: WidgetSnapshot.read()))
    }

    /// One entry, read again every 15 minutes. The app also asks for a reload when the percent
    /// changes. A re-read after 04:00 sees the new day, so yesterday's number is never shown.
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date()
        let entry = TodayEntry(date: now, snapshot: WidgetSnapshot.read())
        completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(15 * 60))))
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    let entry: TodayEntry
    /// Set only outside WidgetKit (previews, offscreen rendering), where the environment has none.
    var familyOverride: WidgetFamily?

    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    private var display: WidgetSnapshot.Display { WidgetSnapshot.display(entry.snapshot, now: entry.date) }
    /// Only a snapshot of today is ever drawn.
    private var snapshot: WidgetSnapshot? { display == .missing || display == .otherDay ? nil : entry.snapshot }
    private var tint: Color { Palette.color(snapshot?.tint) }

    var body: some View {
        Group {
            if family == .systemMedium {
                HStack(alignment: .top, spacing: 14) {
                    summary.frame(maxWidth: .infinity, alignment: .leading)
                    strip.frame(maxWidth: .infinity)
                }
            } else {
                summary.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .containerBackground(for: .widget) {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                tint.opacity(snapshot?.tint == nil ? 0 : 0.14)
            }
        }
    }

    // MARK: Left side: the number

    private var summary: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(heroText)
                    .font(.system(size: 50, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(tint)
                if let snapshot { Text(snapshot.mood).font(.title2) }
            }
            Text(captionText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            Text(footerText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var heroText: String {
        switch display {
        case .ready: snapshot?.percent.map { "\($0)%" } ?? "—"
        default: "—"
        }
    }

    private var captionText: String {
        guard let snapshot else {
            return display == .missing ? "Open Vago" : "New day. Open Vago to start counting."
        }
        switch display {
        case .early(let minutes): return "\(minutes) min so far"
        default:
            return "\(Self.minutes(snapshot.productiveMinutes * 60)) work · \(Self.minutes(snapshot.wasteMinutes * 60)) waste"
        }
    }

    private var footerText: String {
        guard let snapshot else { return "no data for today" }
        return "as of \(snapshot.updatedAt.formatted(date: .omitted, time: .shortened))"
    }

    /// "3h 12m" or "40m", the same as the app's captions.
    private static func minutes(_ seconds: Int) -> String { Format.minutes(seconds) }

    // MARK: Right side: the strip (medium only)

    private var strip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer(minLength: 0)
            if let snapshot {
                DayStrip(
                    lanes: [
                        .init(name: "Mac", hours: snapshot.macHours, hasData: true),
                        .init(name: "iPhone", hours: snapshot.iphoneHours, hasData: !snapshot.iphoneHours.isEmpty,
                              note: snapshot.iphoneHours.isEmpty ? "no iPhone data" : nil),
                    ],
                    laneHeight: 40, labelWidth: 38, cellSpacing: 1, labelEvery: 4,
                    nowSlot: DayKey.hourSlot(of: entry.date)
                )
            } else {
                Text("Day strip appears once Vago has counted today.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
    }
}

extension WidgetSnapshot {
    /// Sample numbers for the gallery and for previews.
    static func sample(at date: Date) -> WidgetSnapshot {
        var mac = (0..<DayKey.hoursPerDay).map { HourSlot(slot: $0) }
        var phone = mac
        for slot in 3...9 { mac[slot] = HourSlot(slot: slot, productive: 2400, procrastination: 300, neutral: 600) }
        for slot in 5...9 { phone[slot] = HourSlot(slot: slot, procrastination: 420) }
        return WidgetSnapshot(
            day: DayKey.of(date), percent: 82, productiveMinutes: 190, neutralMinutes: 45, wasteMinutes: 50,
            limitMinutes: 30, macHours: mac, iphoneHours: phone, iphoneUpdatedAt: date, updatedAt: date, mood: "🙂"
        )
    }
}
