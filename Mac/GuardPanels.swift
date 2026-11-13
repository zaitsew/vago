import AppKit
import SwiftUI
import VagoKit

/// The pause and block panels of the guard. One pause at a time; one block per entry into a blocked
/// place. Both float without taking the focus from the app the owner is in.
@MainActor
final class GuardPanels {
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private final class Host<Content: View>: NSHostingView<Content> {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    private var pausePanel: Panel?
    private var pausePlace: UUID?
    private var blockPanel: Panel?
    private var blockTask: Task<Void, Never>?

    /// The pause panel: a floating card at the top of the screen.
    func showPause(place: GuardedPlace, overBudget: Bool, usedMinutes: Int, budgetMinutes: Int,
                   close: @escaping @MainActor () -> Void, open: @escaping @MainActor () -> Void) {
        closePause()
        let view = PauseContent(
            placeName: place.name, usedMinutes: usedMinutes, budgetMinutes: budgetMinutes, overBudget: overBudget,
            startedAt: Date(),
            onClose: { [weak self] in self?.closePause(); close() },
            onOpen: { [weak self] in self?.closePause(); open() }
        )
        pausePanel = present(view)
        pausePlace = place.id
    }

    /// Closes the pause panel unless it is for `place`, the guarded place now in front.
    func dismissPause(unlessPlace place: UUID?) {
        guard pausePanel != nil, pausePlace != place else { return }
        closePause()
    }

    /// The block panel: a card with Close and a deliberate unlock (hold the button for 3 seconds).
    func showBlock(place: GuardedPlace, until: Date?,
                   close: @escaping @MainActor () -> Void, unlock: @escaping @MainActor () -> Void) {
        closeBlock()
        let view = BlockContent(
            placeName: place.name, until: until,
            onClose: { [weak self] in self?.closeBlock(); close() },
            onUnlock: { [weak self] in self?.closeBlock(); unlock() }
        )
        blockPanel = present(view)
        blockTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            self?.closeBlock()
        }
    }

    func dismissAll() {
        closePause()
        closeBlock()
    }

    private func closePause() {
        pausePanel?.orderOut(nil)
        pausePanel = nil
        pausePlace = nil
    }

    private func closeBlock() {
        blockTask?.cancel()
        blockTask = nil
        blockPanel?.orderOut(nil)
        blockPanel = nil
    }

    private func present<Content: View>(_ view: Content) -> Panel {
        let host = Host(rootView: view)
        let size = host.fittingSize
        let area = Self.screen().visibleFrame
        let frame = NSRect(x: area.midX - size.width / 2, y: area.maxY - size.height - 12, width: size.width, height: size.height)
        let panel = Panel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        return panel
    }

    /// The screen the pointer is on.
    private static func screen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}

// MARK: - Pause

/// The 5-second pause. Close is the big button, "Open for 5 min" the small one; both wake after 5 seconds.
/// Over budget, the ready state keeps the warning colour and shows an exclamation mark, never a check.
struct PauseContent: View {
    var placeName: String
    var usedMinutes: Int
    var budgetMinutes: Int
    var overBudget: Bool
    var startedAt = Date()
    /// A fixed number of seconds into the pause, for screenshots; nil runs the clock.
    var elapsed: Double?
    var onClose: @MainActor () -> Void = {}
    var onOpen: @MainActor () -> Void = {}

    static let seconds = Double(GuardList.pauseSeconds)

    var body: some View {
        if let elapsed {
            card(elapsed)
        } else {
            TimelineView(.animation) { context in card(context.date.timeIntervalSince(startedAt)) }
        }
    }

    private var statusLine: String {
        overBudget
            ? String(localized: "Over budget · \(usedMinutes) of \(budgetMinutes) min today",
                     comment: "Pause card status when today's waste passed the budget. First number: minutes used; second: the budget.")
            : String(localized: "\(usedMinutes) of \(budgetMinutes) min today",
                     comment: "Pause card status: minutes of waste used today, then the daily budget.")
    }

    private func card(_ elapsed: Double) -> some View {
        let ready = elapsed >= Self.seconds
        let progress = min(1, max(0, elapsed / Self.seconds))
        let left = Int(max(0, Self.seconds - elapsed).rounded(.up))
        let ring: Color = overBudget ? .orange : (ready ? .green : .orange)
        return VStack(spacing: 12) {
            Text(verbatim: placeName).font(.title3.weight(.semibold))
            Text(verbatim: statusLine)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(overBudget ? Color.orange : Color.secondary)
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(ring, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if ready {
                    Image(systemName: overBudget ? "exclamationmark" : "checkmark")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(ring)
                } else {
                    Text(verbatim: "\(left)").font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                }
            }
            .frame(width: 64, height: 64)
            .padding(.vertical, 2)
            PauseButtons(ready: ready, onClose: onClose, onOpen: onOpen)
        }
        .padding(20)
        .frame(width: 300)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.separator))
        .padding(10)
    }
}

private struct PauseButtons: View {
    var ready: Bool
    var onClose: @MainActor () -> Void
    var onOpen: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: onClose) {
                Text("Close", comment: "Big button of the pause and block cards: closes the place.").frame(maxWidth: .infinity)
            }
            .buttonStyle(FilledCloseStyle())
            .disabled(!ready)
            Button("Open for \(GuardList.passMinutes) min", action: onOpen)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!ready)
        }
    }
}

// MARK: - Block

/// "Instagram is blocked until 18:00": Close, and a deliberate unlock by holding a button for 3 seconds.
struct BlockContent: View {
    var placeName: String
    var until: Date?
    var onClose: @MainActor () -> Void = {}
    var onUnlock: @MainActor () -> Void = {}
    /// Fixed hold progress for screenshots; nil follows the press.
    var holdFraction: Double?

    private var title: String {
        guard let until else {
            return String(localized: "\(placeName) is blocked", comment: "Block card title when no end time is known. The argument is the place name.")
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return String(localized: "\(placeName) is blocked until \(f.string(from: until))",
                      comment: "Block card title. First argument: the place name; second: the clock time the work hours end, such as 18:00.")
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "hand.raised.fill").font(.title).foregroundStyle(.orange)
            Text(verbatim: title).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
            Text("Work hours. Unlocking opens it for \(GuardList.passMinutes) minutes.",
                 comment: "Block card explanation. The argument is the number of minutes an unlock lasts.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: onClose) {
                Text("Close", comment: "Big button of the pause and block cards: closes the place.").frame(maxWidth: .infinity)
            }
            .buttonStyle(FilledCloseStyle())
            HoldToUnlock(fractionOverride: holdFraction, onDone: onUnlock)
        }
        .padding(20)
        .frame(width: 320)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.separator))
        .padding(10)
    }
}

/// A button that fires after a 3-second press-and-hold; letting go early cancels.
struct HoldToUnlock: View {
    static let seconds = 3.0
    var fractionOverride: Double?
    var onDone: @MainActor () -> Void
    @State private var pressStart: Date?

    var body: some View {
        TimelineView(.animation(paused: pressStart == nil || fractionOverride != nil)) { context in
            let fraction = fractionOverride ?? pressStart.map { min(1, context.date.timeIntervalSince($0) / Self.seconds) } ?? 0
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.quaternary)
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.orange.opacity(0.55))
                        .frame(width: geo.size.width * fraction)
                }
                Text("Hold to unlock").font(.callout).frame(maxWidth: .infinity)
            }
            .frame(height: 26)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: Self.seconds, maximumDistance: 80, perform: onDone) { pressing in
            pressStart = pressing ? Date() : nil
        }
        .accessibilityLabel("Hold for 3 seconds to unlock")
    }
}

/// The big primary button of the pause and block panels. An explicit fill, because
/// `.borderedProminent` goes grey in a panel that is never key.
struct FilledCloseStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(nsColor: .systemBlue).opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4))
            )
            .contentShape(Rectangle())
    }
}
