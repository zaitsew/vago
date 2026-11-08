import SwiftUI
import VagoKit

struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ShareHero(snapshot: model.snapshot)
                    WasteCard(snapshot: model.snapshot)
                    DayStripCard(snapshot: model.snapshot)
                    DeviceLines(snapshot: model.snapshot)
                    FocusCard()
                    if let message = model.errorMessage {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("Today")
        }
    }
}

/// The main number: the productive share of the day, across devices.
struct ShareHero: View {
    let snapshot: Snapshot

    var body: some View {
        let share = snapshot.share
        VStack(spacing: 6) {
            Text(share.text)
                .font(.system(size: 104, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(share.tint?.color ?? Color.secondary)
                .contentTransition(.numericText())
                .animation(.smooth, value: share.percent)
            Text(share.percent == nil ? "Building today's picture" : "productive today")
                .font(.headline)
            if share.percent != nil {
                Text(caption)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private var caption: String {
        let s = snapshot.share
        return "\(Spoken.duration(s.productive)) work · \(Spoken.duration(s.neutral)) neutral · \(Spoken.duration(s.procrastination)) waste"
    }
}

/// The mood emoji and a bar of waste against today's limit.
struct WasteCard: View {
    let snapshot: Snapshot

    var body: some View {
        let tint = snapshot.mood.tint.color
        HStack(spacing: 14) {
            Text(snapshot.mood.emoji)
                .font(.system(size: 40))
                .contentTransition(.opacity)
            VStack(alignment: .leading, spacing: 8) {
                Text("\(snapshot.minutesUsed) of \(snapshot.limitMinutes) min waste")
                    .font(.headline.monospacedDigit())
                ProgressView(value: min(snapshot.limitFill, 1))
                    .tint(tint)
                    .animation(.smooth, value: snapshot.limitFill)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Waste today")
        .accessibilityValue("\(snapshot.minutesUsed) of \(snapshot.limitMinutes) minutes")
    }
}

/// The day by hour on both devices, with the freshness note.
struct DayStripCard: View {
    let snapshot: Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your day").font(.headline)
                Spacer()
                legend
            }
            DayStrip(mac: snapshot.macHours, iphone: snapshot.iphoneHours)
            caption
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16))
    }

    private var legend: some View {
        HStack(spacing: 10) {
            key("work", StripColor.work)
            key("neutral", StripColor.neutral)
            key("waste", StripColor.waste)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func key(_ name: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(name)
        }
    }

    @ViewBuilder
    private var caption: some View {
        if let updated = snapshot.macUpdatedAt {
            Text("iPhone minutes come from Screen Time reports and can lag. Mac updated \(Text(updated, style: .relative)) ago.")
        } else {
            Text("iPhone minutes come from Screen Time reports and can lag. No Mac data yet.")
        }
    }
}

struct DeviceLines: View {
    let snapshot: Snapshot

    var body: some View {
        VStack(spacing: 0) {
            line("iPhone", symbol: "iphone", day: snapshot.iphone)
            Divider().padding(.leading, 44)
            line("Mac", symbol: "laptopcomputer", day: snapshot.mac)
        }
        .padding(.horizontal)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16))
    }

    private func line(_ name: String, symbol: String, day: DeviceDay?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 32).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                if let day {
                    Text("\(Spoken.duration(day.productive)) work")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let day {
                let share = ProductiveShare(productive: day.productive, neutral: day.neutral,
                                            procrastination: day.procrastination)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(share.text)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(share.tint?.color ?? Color.secondary)
                    Text("\(day.procrastination / 60) min waste")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("no data yet").foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 12)
    }
}

/// Start a session, or see the running one.
struct FocusCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let session = model.activeFocus {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack {
                        Text(session.stage(at: context.date)).font(.largeTitle)
                        VStack(alignment: .leading) {
                            Text("Focus").font(.headline)
                            Text(timerInterval: context.date...max(session.end, context.date.addingTimeInterval(1)), countsDown: true)
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            } else {
                Text("Focus").font(.headline)
                HStack(spacing: 12) {
                    Button("Start 25") { model.startFocus(minutes: 25) }
                        .buttonStyle(.borderedProminent)
                    Button("Start 50") { model.startFocus(minutes: 50) }
                        .buttonStyle(.bordered)
                }
                .controlSize(.large)
                Text("Procrastination and mixed apps are paused while the tree grows.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16))
    }
}
