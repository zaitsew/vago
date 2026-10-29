import SwiftUI
import VagoKit

struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    MoodRing(snapshot: model.snapshot)
                    HStack(spacing: 12) {
                        StatTile(title: "Work", minutes: model.snapshot.productive / 60, symbol: "briefcase")
                        StatTile(title: "Focus", minutes: model.snapshot.focus / 60, symbol: "leaf")
                    }
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

/// Big mood emoji inside a ring that fills with the share of the limit used.
struct MoodRing: View {
    let snapshot: Snapshot

    var body: some View {
        let tint = snapshot.mood.tint.color
        ZStack {
            Circle().stroke(tint.opacity(0.18), lineWidth: 18)
            Circle()
                .trim(from: 0, to: min(snapshot.share, 1))
                .stroke(tint, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth, value: snapshot.share)
            VStack(spacing: 6) {
                Text(snapshot.mood.emoji)
                    .font(.system(size: 88))
                    .contentTransition(.opacity)
                Text("\(snapshot.minutesUsed) / \(snapshot.limitMinutes) min")
                    .font(.title2.weight(.semibold).monospacedDigit())
                Text("procrastination, all devices")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 280, height: 280)
        .padding(.top, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Procrastination today")
        .accessibilityValue("\(snapshot.minutesUsed) of \(snapshot.limitMinutes) minutes")
    }
}

struct StatTile: View {
    let title: String
    let minutes: Int
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("\(minutes) min")
                .font(.title3.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16))
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
            Text(name)
            Spacer()
            if let day {
                Text("\(day.procrastination / 60) min").monospacedDigit().foregroundStyle(.secondary)
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
