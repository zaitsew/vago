import SwiftUI
import VagoKit

/// The three bucket colours of the day strip: work green, neutral gray, waste red.
enum StripColor {
    static let work = Color.green
    static let neutral = Color.gray
    static let waste = Color.red
}

/// The hours a strip shows: from the first to the last hour with data, and at least 07:00 to 23:00.
/// Slots count from 04:00, so 07:00 is slot 3 and 23:00 is slot 19.
struct StripRange {
    let slots: ClosedRange<Int>

    init(_ lanes: [[HourSlot]]) {
        var low = 3, high = 19
        for lane in lanes {
            for hour in lane where hour.total > 0 {
                low = min(low, hour.slot)
                high = max(high, hour.slot)
            }
        }
        slots = low...high
    }
}

/// One hour of one lane: a stacked bar, waste on top, then neutral, then work at the bottom.
/// The cell is one hour tall in the sense that a full 60 minutes fills it.
struct HourBar: View {
    let hour: HourSlot?
    let height: CGFloat

    var body: some View {
        let hour = hour ?? HourSlot(slot: 0)
        let scale = CGFloat(max(3600, hour.total))
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            segment(hour.procrastination, StripColor.waste, scale)
            segment(hour.neutral, StripColor.neutral, scale)
            segment(hour.productive, StripColor.work, scale)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }

    @ViewBuilder
    private func segment(_ seconds: Int, _ color: Color, _ scale: CGFloat) -> some View {
        if seconds > 0 {
            Rectangle().fill(color).frame(height: max(1.5, height * CGFloat(seconds) / scale))
        }
    }
}

/// The day by hour, two lanes (Mac on top, iPhone below). `interactive` adds tap-for-detail;
/// the widget uses the plain strip.
struct DayStrip: View {
    let mac: [HourSlot]
    let iphone: [HourSlot]
    var interactive = true
    var laneHeight: CGFloat = 34
    var spacing: CGFloat = 3

    @State private var selected: Int?

    private func hour(_ lane: [HourSlot], _ slot: Int) -> HourSlot? {
        lane.first { $0.slot == slot }
    }

    var body: some View {
        let range = StripRange([mac, iphone])
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                if interactive {
                    VStack(spacing: 4) {
                        laneIcon("laptopcomputer")
                        laneIcon("iphone")
                    }
                    .frame(width: 18)
                    .padding(.top, 0)
                }
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(Array(range.slots), id: \.self) { slot in
                        column(slot, first: range.slots.lowerBound)
                    }
                }
            }
            if interactive {
                Text(selected.map { Self.detail(slot: $0, mac: mac, iphone: iphone) } ?? "Tap an hour for details")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(selected == nil ? .tertiary : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentTransition(.opacity)
                    .animation(.smooth(duration: 0.15), value: selected)
            }
        }
    }

    private func laneIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(height: laneHeight)
    }

    private func column(_ slot: Int, first: Int) -> some View {
        let dimmed = selected != nil && selected != slot
        return VStack(spacing: 4) {
            HourBar(hour: hour(mac, slot), height: laneHeight)
            HourBar(hour: hour(iphone, slot), height: laneHeight)
            Text((slot - first) % 3 == 0 ? String(format: "%02d", DayKey.clockHour(ofSlot: slot)) : " ")
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .opacity(dimmed ? 0.4 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            guard interactive else { return }
            selected = selected == slot ? nil : slot
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.detail(slot: slot, mac: mac, iphone: iphone))
        .accessibilityAddTraits(interactive ? .isButton : [])
    }

    /// "14:00 · Mac 42m work · iPhone 11m waste".
    static func detail(slot: Int, mac: [HourSlot], iphone: [HourSlot]) -> String {
        func part(_ name: String, _ lane: [HourSlot]) -> String {
            guard let h = lane.first(where: { $0.slot == slot }), h.total > 0 else { return "\(name) —" }
            var bits: [String] = []
            if h.productive > 0 { bits.append("\(Spoken.minutes(h.productive)) work") }
            if h.neutral > 0 { bits.append("\(Spoken.minutes(h.neutral)) neutral") }
            if h.procrastination > 0 { bits.append("\(Spoken.minutes(h.procrastination)) waste") }
            return "\(name) " + bits.joined(separator: ", ")
        }
        let clock = String(format: "%02d:00", DayKey.clockHour(ofSlot: slot))
        return "\(clock) · \(part("Mac", mac)) · \(part("iPhone", iphone))"
    }
}
