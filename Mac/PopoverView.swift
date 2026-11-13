import SwiftUI
import VagoKit

/// The window behind the menu-bar item. The share, the waste limit and the footer stay fixed;
/// the day strip (one lane per device) and the rows sit in a scroll view that is capped, so the
/// popover never grows past the screen. Detail lives in the Day window, settings in their own.
struct PopoverView: View {
    let model: AppModel
    static let width: CGFloat = 340
    @State private var listHeight: CGFloat = 0

    /// The most the scrolling middle may take: the visible screen height minus the fixed
    /// header and footer (about 190 points) and a 40-point margin.
    private var maxListHeight: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 800
        return max(160, screen - 190 - 40)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ModeRow(model: model)
            Divider()
            Hero(share: model.share)
            LimitRow(model: model)
            Divider()
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
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
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(max(listHeight, 1), maxListHeight))
            Divider()
            Footer(model: model)
        }
        .padding(16)
        .frame(width: Self.width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Hero: the productive share

struct Hero: View {
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
                Text(pause == .idle ? String(localized: "Paused · no input", comment: "Popover status while no input was seen for two minutes.") : String(localized: "Paused · screen locked", comment: "Popover status while the screen is locked."))
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
        let word = now.unclear ? String(localized: "unsure", comment: "Popover Now line: the place has no clear call yet.") : Words.bucket(now.bucket)
        Circle()
            .fill(now.unclear ? Palette.neutral : Palette.style(for: now.bucket))
            .frame(width: 7, height: 7)
        HStack(spacing: 0) {
            Text("Now: ").foregroundStyle(.secondary)
            Text(verbatim: now.label).lineLimit(1).truncationMode(.middle)
            Text(verbatim: " — \(word)").foregroundStyle(.secondary).fixedSize()
        }
        .font(.callout)
        .help(Self.help(now))
        Spacer(minLength: 4)
        // A neutral rule (Finder, Settings) is not worth a correction.
        if !(now.source == .rule && now.bucket == .neutral) {
            Menu {
                Section(String(localized: "Count \(now.label) as", comment: "Menu header above the Work, Neutral and Waste choices. The argument is the place name.")) {
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
        case .rule: now.reason == CallReason.corrected ? String(localized: "You corrected this place", comment: "Tooltip of the Now line.") : String(localized: "Settled by a rule", comment: "Tooltip of the Now line.")
        case .answer: String(localized: "Your answer today", comment: "Tooltip of the Now line.")
        case .judge: String(localized: "AI: \(Format.reason(now.reason))", comment: "Tooltip of the Now line. The argument is the AI judge's one-sentence reason.")
        case .fallback: now.unclear ? String(localized: "AI unsure: \(Format.reason(now.reason)). Counted as neutral.", comment: "Tooltip of the Now line. The argument is the AI judge's reason.") : Format.reason(now.reason)
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
                Text(trees == 0 ? String(localized: "Focus", comment: "Popover focus row label before any tree was grown.") : String(localized: "🌳 \(trees) this week", comment: "Popover focus row: trees grown in the last 7 days. The argument is the count."))
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
                Text(verbatim: String(localized: "\(streak / 60) min at the Mac — \(move.title)", comment: "Popover move row. First argument: minutes at the Mac; second: the name of the suggested move."))
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
                Text(verbatim: streak > 0 ? String(localized: "\(Format.minutes(streak)) at the Mac · \(moves)", comment: "Popover move row. First argument: a duration; second: the moves-today phrase.") : String(localized: "On a break · \(moves)", comment: "Popover move row while the owner is on a break. The argument is the moves-today phrase."))
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
        return n == 1 ? String(localized: "1 move today", comment: "Popover: one move done today.") : String(localized: "\(n) moves today", comment: "Popover: moves done today. The argument is the count.")
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
