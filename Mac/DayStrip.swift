import SwiftUI
import VagoKit

/// A day as a row of hour cells per device. Each cell is a stacked bar: work at the bottom,
/// then neutral, then waste; a full cell is a full hour. Used small in the popover and large in
/// the Day window.
///
/// Hours shown: from the first to the last hour with data, never less than 07:00–23:00.
struct DayStrip: View {
    struct Lane: Identifiable {
        var id: String { name }
        var name: String
        var hours: [HourSlot]
        /// False when this device has no value for the day: the lane is drawn empty and dim.
        var hasData: Bool
        /// A small line under the lane ("iPhone minutes come from Screen Time …").
        var note: String? = nil
    }

    var lanes: [Lane]
    var laneHeight: CGFloat = 20
    var labelWidth: CGFloat = 44
    var cellSpacing: CGFloat = 2
    /// Hover text per hour cell ("14:00 · 42m work · 11m waste").
    var tooltips = false
    /// Label every n-th clock hour on the axis.
    var labelEvery = 3
    /// The hour slot of "now", drawn a little stronger; nil for past days.
    var nowSlot: Int?

    /// 07:00 and 23:00 as hour slots (slot 0 is 04:00).
    static let minimumRange = 3...19

    var range: ClosedRange<Int> {
        let used = lanes.flatMap { lane in lane.hours.filter { $0.total > 0 }.map(\.slot) } + (nowSlot.map { [$0] } ?? [])
        let lo = min(used.min() ?? Self.minimumRange.lowerBound, Self.minimumRange.lowerBound)
        let hi = max(used.max() ?? Self.minimumRange.upperBound, Self.minimumRange.upperBound)
        return max(0, lo)...min(DayKey.hoursPerDay - 1, hi)
    }

    var body: some View {
        let slots = Array(range)
        VStack(alignment: .leading, spacing: 4) {
            ForEach(lanes) { lane in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(lane.name)
                            .font(.caption)
                            .foregroundStyle(lane.hasData ? HierarchicalShapeStyle.secondary : HierarchicalShapeStyle.tertiary)
                            .frame(width: labelWidth, alignment: .leading)
                        HStack(alignment: .bottom, spacing: cellSpacing) {
                            ForEach(slots, id: \.self) { slot in
                                let hour = lane.hours.indices.contains(slot) ? lane.hours[slot] : HourSlot(slot: slot)
                                HourCell(hour: hour, height: laneHeight, isNow: slot == nowSlot)
                                    .modifier(Tooltip(text: tooltips ? Self.tooltip(hour, lane: lane.name) : nil))
                            }
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                Color.clear.frame(width: labelWidth, height: 1)
                HStack(spacing: cellSpacing) {
                    ForEach(slots, id: \.self) { slot in
                        let clock = DayKey.clockHour(ofSlot: slot)
                        Text(verbatim: clock % labelEvery == 0 ? "\(clock)" : " ")
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .fixedSize()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            ForEach(lanes.compactMap(\.note), id: \.self) { note in
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, labelWidth + 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    static func tooltip(_ h: HourSlot, lane: String) -> String {
        var parts = [String(format: "%02d:00", h.clockHour), lane]
        if h.total == 0 { return parts.joined(separator: " · ") + " · " + String(localized: "nothing", comment: "Hour tooltip of the day strip when no time was counted in that hour.") }
        if h.productive > 0 { parts.append(String(localized: "\(Format.minutes(h.productive)) work", comment: "Hour tooltip: work time in that hour. The argument is a duration.")) }
        if h.neutral > 0 { parts.append(String(localized: "\(Format.minutes(h.neutral)) neutral", comment: "Hour tooltip: neutral time in that hour. The argument is a duration.")) }
        if h.procrastination > 0 { parts.append(String(localized: "\(Format.minutes(h.procrastination)) waste", comment: "Hour tooltip: waste time in that hour. The argument is a duration.")) }
        return parts.joined(separator: " · ")
    }

    private var accessibilitySummary: String {
        lanes.map { lane in
            let busiest = lane.hours.max { $0.procrastination < $1.procrastination }
            guard lane.hasData, let busiest, busiest.procrastination > 0 else { return String(localized: "\(lane.name): no waste", comment: "Accessibility summary of one day-strip lane with no waste. The argument is the device name.") }
            return String(localized: "\(lane.name): most waste at \(busiest.clockHour):00", comment: "Accessibility summary of one day-strip lane. First argument: the device name; second: the hour of the day with the most waste.")
        }
        .joined(separator: ". ")
    }
}

/// One hour: a faint full-height track with the stacked bar on top of it.
private struct HourCell: View {
    let hour: HourSlot
    let height: CGFloat
    let isNow: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: min(3, height / 6), style: .continuous)
        ZStack(alignment: .bottom) {
            shape.fill(Palette.empty)
            VStack(spacing: 0) {
                bar(hour.procrastination, Palette.style(for: .procrastination))
                bar(hour.neutral, Palette.neutral)
                bar(hour.productive, Palette.style(for: .productive))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(shape)
        .overlay {
            if isNow { shape.strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 1) }
        }
    }

    /// A segment's height: its share of a full hour, at least one point when there is any use.
    private func bar(_ seconds: Int, _ style: AnyShapeStyle) -> some View {
        let scale = height / 3600
        let total = max(1, hour.total)
        let fullHeight = min(height, CGFloat(hour.total) * scale)
        let h = seconds > 0 ? max(1, fullHeight * CGFloat(seconds) / CGFloat(total)) : 0
        return Rectangle().fill(style).frame(height: h)
    }
}

/// `.help` only when there is text, so the popover's small strip shows no tooltips.
private struct Tooltip: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        if let text { content.help(text) } else { content }
    }
}

extension DayStrip {
    static var iphoneNote: String { String(localized: "iPhone minutes come from Screen Time reports and can lag a few minutes.", comment: "Note under the iPhone lane of the day strip.") }

    /// One lane per device in `devices`, Mac first, from the merged ledger.
    static func lanes(_ ledger: Ledger, day: DayKey, devices: [Device] = [.mac, .iphone], notes: Bool = false) -> [Lane] {
        [Device.mac, .iphone].filter(devices.contains).map { device in
            Lane(
                name: device == .mac ? String(localized: "Mac", comment: "Device name, the day-strip lane label.") : String(localized: "iPhone", comment: "Device name, the day-strip lane label."),
                hours: ledger.hours(for: day, devices: [device]),
                hasData: ledger.days[Ledger.key(day, device)] != nil,
                note: notes && device == .iphone ? iphoneNote : nil
            )
        }
    }
}
