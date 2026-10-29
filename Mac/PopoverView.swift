import SwiftUI
import VagoKit

/// The window behind the menu-bar item.
struct PopoverView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Header(model: model)
            if !model.accessibilityGranted { AccessibilityCallout() }
            Divider()
            TodaySection(model: model)
            FocusSection(model: model)
            if !model.reviewItems.isEmpty { ReviewSection(model: model) }
            Divider()
            SettingsSection(model: model)
        }
        .padding(16)
        .frame(width: 344)
    }
}

// MARK: - Header

private struct Header: View {
    let model: AppModel

    var body: some View {
        let used = model.totals.procrastination
        let limit = model.limit.current
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Text(model.mood.emoji).font(.system(size: 52))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(used / 60) of \(limit) min")
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                    Text("procrastination today, all devices")
                        .font(.caption).foregroundStyle(.secondary)
                    if let pause = model.pause {
                        Text(pause == .idle ? "Paused: no input" : "Paused: screen locked")
                            .font(.caption2).foregroundStyle(.tertiary)
                    } else if let label = model.currentLabel {
                        Text("Now: \(label)").font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
            }
            ProgressView(value: min(1, Double(used) / Double(max(1, limit * 60))))
                .tint(tint)
        }
    }

    private var tint: Color {
        switch model.mood.tint {
        case .green: .green
        case .yellow: .yellow
        case .red: .red
        }
    }
}

// MARK: - Today

private struct TodaySection: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Stat(title: "Work", value: Format.duration(model.totals.productive))
                Stat(title: "Focus", value: Format.duration(model.totals.focus))
                Stat(title: "Limit", value: "\(model.limit.current)m")
            }
            VStack(alignment: .leading, spacing: 3) {
                deviceLine("Mac", .mac)
                deviceLine("iPhone", .iphone)
            }
            if !model.topDistractions.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Top distractions").font(.caption).foregroundStyle(.secondary)
                    ForEach(model.topDistractions, id: \.label) { row in
                        HStack {
                            Text(row.label).lineLimit(1)
                            Spacer()
                            Text(Format.duration(row.seconds)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }

    private func deviceLine(_ name: String, _ device: Device) -> some View {
        HStack {
            Text(name)
            Spacer()
            if let s = model.seconds(of: device) {
                Text("\(Format.duration(s.procrastination)) waste · \(Format.duration(s.productive)) work")
                    .monospacedDigit().foregroundStyle(.secondary)
            } else {
                Text(device == .iphone ? "no data yet" : "—").foregroundStyle(.tertiary)
            }
        }
        .font(.callout)
    }
}

private struct Stat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Focus

private struct FocusSection: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let focus = model.focus, focus.state == .growing {
                HStack {
                    Text(focus.stage(at: model.clock)).font(.title)
                    VStack(alignment: .leading) {
                        Text("Focus: \(Int((focus.remaining(at: model.clock) / 60).rounded(.up))) min left").font(.callout.weight(.medium))
                        Text(focus.distractedSeconds == 0 ? "No distractions" : "Distracted \(focus.distractedSeconds)s, wilts after \(FocusSession.wiltThresholdSeconds)s")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Give up") { model.giveUpFocus() }
                }
                ProgressView(value: focus.fraction(at: model.clock))
            } else {
                HStack {
                    Text("Focus").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Start 25") { model.startFocus(minutes: 25) }.buttonStyle(.borderedProminent)
                    Button("Start 50") { model.startFocus(minutes: 50) }
                }
                if let toast = model.lastToast {
                    Text(toast).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Review

private struct ReviewSection: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Was this work?").font(.caption).foregroundStyle(.secondary)
            ForEach(model.reviewItems) { item in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(item.label) · \(Format.duration(item.seconds))").font(.callout).lineLimit(1)
                        Text("AI: \(Format.reason(item.reason))").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    Button("Work") { model.answerReview(item, as: .productive) }
                    Button("Waste") { model.answerReview(item, as: .procrastination) }
                }
            }
        }
    }
}

// MARK: - First-run callout

private struct AccessibilityCallout: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Window titles are off").font(.callout.weight(.medium))
            Text("Allow Accessibility so Vago can read the front window title. Browsers ask for Automation the first time you use them. Until then Vago sees app names only.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Allow Accessibility") {
                if !Permissions.requestAccessibility() { Permissions.openAccessibilitySettings() }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Formatting

enum Format {
    /// "12m", "1h 05m", "45s" for under a minute.
    static func duration(_ seconds: Int) -> String {
        let s = max(0, seconds)
        if s < 60 { return "\(s)s" }
        let m = s / 60
        return m < 60 ? "\(m)m" : String(format: "%dh %02dm", m / 60, m % 60)
    }

    /// The classifier prefixes guesses with "unsure: "; the popover already says "AI".
    static func reason(_ text: String) -> String {
        text.hasPrefix("unsure: ") ? String(text.dropFirst(8)) : text
    }
}
