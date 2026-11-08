import SwiftUI
import VagoKit

/// The window behind the menu-bar item. A short fixed layout: nothing expands or scrolls, so the
/// whole popover always fits on screen. Detail lives in the Day window, settings in their own.
struct PopoverView: View {
    let model: AppModel
    static let width: CGFloat = 340

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Hero(share: model.share)
            LimitRow(model: model)
            Divider()
            DayStrip(
                lanes: DayStrip.lanes(model.ledger, day: model.today.day),
                laneHeight: 18,
                labelWidth: 40,
                nowSlot: DayKey.hourSlot(of: model.clock)
            )
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                NowRow(model: model)
                FocusRow(model: model)
                if model.breaks.enabled { MoveRow(model: model) }
            }
            Divider()
            Footer(model: model)
        }
        .padding(16)
        .frame(width: Self.width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Hero: the productive share

private struct Hero: View {
    let share: ProductiveShare

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Productive today · all devices")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(share.text)
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Palette.color(share.tint))
                .contentTransition(.numericText())
            Text(Format.caption(share))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Mood and the waste limit

private struct LimitRow: View {
    let model: AppModel

    var body: some View {
        let used = model.totals.procrastination
        let limit = model.limit.current
        HStack(spacing: 8) {
            Text(model.mood.emoji).font(.system(size: 16))
            ThinBar(fraction: Double(used) / Double(max(1, limit * 60)), color: Palette.color(model.mood.tint))
            Text("\(used / 60) of \(limit) min waste")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Now: what Vago thinks of the place in front

private struct NowRow: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            if !model.accessibilityGranted {
                Image(systemName: "lock.shield").foregroundStyle(.orange)
                Text("Allow Accessibility to see window titles.")
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                Button("Allow") {
                    if !Permissions.requestAccessibility() { Permissions.openAccessibilitySettings() }
                }
                .controlSize(.small)
            } else if let pause = model.pause {
                Image(systemName: "pause.circle").foregroundStyle(.tertiary)
                Text(pause == .idle ? "Paused · no input" : "Paused · screen locked")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            } else if let now = model.now {
                place(now)
            } else {
                Image(systemName: "circle.dotted").foregroundStyle(.tertiary)
                Text("Watching the front app").font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
        }
        .frame(height: 22)
    }

    @ViewBuilder
    private func place(_ now: NowPlace) -> some View {
        let word = now.unclear ? "unsure" : Words.bucket(now.bucket)
        Circle()
            .fill(now.unclear ? Palette.neutral : Palette.style(for: now.bucket))
            .frame(width: 7, height: 7)
        HStack(spacing: 0) {
            Text("Now: ").foregroundStyle(.secondary)
            Text(now.label).lineLimit(1).truncationMode(.middle)
            Text(" — \(word)").foregroundStyle(.secondary).fixedSize()
        }
        .font(.callout)
        .help(Self.help(now))
        Spacer(minLength: 4)
        // A neutral rule (Finder, Settings) is not worth a correction.
        if !(now.source == .rule && now.bucket == .neutral) {
            Menu {
                Section("Count \(now.label) as") {
                    ForEach([Bucket.productive, .neutral, .procrastination], id: \.self) { bucket in
                        Button(Words.bucket(bucket).capitalized) { model.correctCurrent(as: bucket) }
                            .disabled(!now.unclear && bucket == now.bucket)
                    }
                }
            } label: {
                Text("Wrong?")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .controlSize(.small)
            .foregroundStyle(.secondary)
            .fixedSize()
            .help("Correct this place for today and from now on")
        }
    }

    private static func help(_ now: NowPlace) -> String {
        switch now.source {
        case .rule: now.reason == CallReason.corrected ? "You corrected this place" : "Settled by a rule"
        case .answer: "Your answer today"
        case .judge: "AI: \(Format.reason(now.reason))"
        case .fallback: now.unclear ? "AI unsure: \(Format.reason(now.reason)). Counted as neutral." : Format.reason(now.reason)
        }
    }
}

// MARK: - Focus

private struct FocusRow: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            if let focus = model.focus, focus.state == .growing {
                Text(focus.stage(at: model.clock)).font(.system(size: 16))
                Text("\(Int((focus.remaining(at: model.clock) / 60).rounded(.up))) min left")
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
                    .fixedSize()
                ThinBar(fraction: focus.fraction(at: model.clock), color: Palette.work)
                Button("Stop") { model.giveUpFocus() }
            } else {
                Image(systemName: "leaf").foregroundStyle(.secondary)
                Text(trees == 0 ? "Focus" : "🌳 \(trees) this week")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Focus 25") { model.startFocus(minutes: 25) }
                    .buttonStyle(.borderedProminent)
                Button("Focus 50") { model.startFocus(minutes: 50) }
            }
        }
        .controlSize(.small)
        .frame(height: 22)
    }

    /// Trees grown in the last 7 days: the garden.
    private var trees: Int {
        let weekAgo = model.clock.addingTimeInterval(-7 * 86_400)
        return model.focusLog.filter { $0.state == .grown && $0.start >= weekAgo }.count
    }
}

// MARK: - Move breaks

private struct MoveRow: View {
    let model: AppModel

    var body: some View {
        let streak = model.breaks.streakSeconds(at: model.clock)
        HStack(spacing: 8) {
            if model.breaks.wantsMark(at: model.clock) {
                let move = model.breaks.move
                Text("🚶").font(.system(size: 15))
                Text("\(streak / 60) min at the Mac — \(move.title)")
                    .font(.caption)
                    .lineLimit(2)
                    .help(move.how)
                Spacer(minLength: 4)
                Button("Done") { model.breakDone() }
                    .buttonStyle(.borderedProminent)
                Menu("Later") {
                    Button("Not today") { model.breakNotToday() }
                } primaryAction: {
                    model.breakLater()
                }
                .fixedSize()
            } else {
                Image(systemName: "figure.walk").foregroundStyle(.secondary)
                Text(streak > 0 ? "\(Format.minutes(streak)) at the Mac · \(moves)" : "On a break · \(moves)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Move now") { model.showBreak() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
        .controlSize(.small)
        .frame(minHeight: 22)
    }

    private var moves: String {
        let n = model.movesToday
        return n == 1 ? "1 move today" : "\(n) moves today"
    }
}

// MARK: - Footer

private struct Footer: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            Button { model.openWindow?(.day) } label: {
                Label("Day", systemImage: "chart.bar.xaxis")
            }
            .keyboardShortcut("d")
            Button { model.openWindow?(.settings) } label: {
                Label("Settings…", systemImage: "gearshape")
            }
            .keyboardShortcut(",")
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}
