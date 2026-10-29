import SwiftUI
import VagoKit

struct FocusView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    if let session = model.activeFocus {
                        GrowingTree(session: session)
                        Button("Give up", role: .destructive) { model.abandonFocus() }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                    } else {
                        VStack(spacing: 16) {
                            Text("🌱").font(.system(size: 96))
                            Text("Plant a tree").font(.title2.weight(.semibold))
                            Text("Pick a length. Distracting apps are paused until the tree is grown.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            HStack(spacing: 12) {
                                Button("25 min") { model.startFocus(minutes: 25) }
                                    .buttonStyle(.borderedProminent)
                                Button("50 min") { model.startFocus(minutes: 50) }
                                    .buttonStyle(.bordered)
                            }
                            .controlSize(.large)
                        }
                        .padding(.top, 24)
                    }
                    Garden(sessions: model.thisWeek)
                }
                .padding()
            }
            .navigationTitle("Focus")
        }
    }
}

/// The seedling grows over the session: its size and stage follow the clock.
struct GrowingTree: View {
    let session: FocusSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let fraction = session.fraction(at: now)
            VStack(spacing: 16) {
                ZStack {
                    Circle().stroke(.green.opacity(0.18), lineWidth: 14)
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(.green, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(session.stage(at: now))
                        .font(.system(size: 96))
                        .scaleEffect(0.55 + 0.45 * fraction)
                        .animation(.spring(duration: 0.8), value: session.stage(at: now))
                }
                .frame(width: 240, height: 240)
                Text(timerInterval: now...max(session.end, now.addingTimeInterval(1)), countsDown: true)
                    .font(.largeTitle.weight(.semibold).monospacedDigit())
                Text("\(session.minutes)-minute session")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 16)
        .accessibilityElement(children: .combine)
    }
}

/// This week's trees: grown ones stand, wilted and abandoned ones lie faded.
struct Garden: View {
    let sessions: [FocusSession]

    private var grown: Int { sessions.filter { $0.state == .grown }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Garden").font(.headline)
                Spacer()
                Text("\(grown) \(grown == 1 ? "tree" : "trees") this week")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if sessions.isEmpty {
                Text("Nothing planted yet this week.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                    ForEach(Array(sessions.enumerated()), id: \.offset) { _, session in
                        Text(session.state == .grown ? "🌳" : "🥀")
                            .font(.system(size: 34))
                            .opacity(session.state == .grown ? 1 : 0.5)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16))
    }
}
