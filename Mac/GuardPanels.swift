import AppKit
import SwiftUI
import VagoKit

/// The pause and block panels of the guard. One pause at a time; one block per entry into a blocked
/// place. Both float without taking the focus from the app the owner is in, except the block panel
/// that needs typing.
@MainActor
final class GuardPanels {
    private final class Panel: NSPanel {
        var keyable = false
        override var canBecomeKey: Bool { keyable }
        override var canBecomeMain: Bool { false }
    }

    private final class Host<Content: View>: NSHostingView<Content> {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    private var pausePanel: Panel?
    private var pausePlace: UUID?
    private var blockPanel: Panel?
    private var blockTask: Task<Void, Never>?

    /// The pause panel: a floating card (variant A) or a shade over the screen (variant B).
    func showPause(place: GuardedPlace, overBudget: Bool, usedMinutes: Int, budgetMinutes: Int, variant: Variant,
                   close: @escaping @MainActor () -> Void, open: @escaping @MainActor () -> Void) {
        closePause()
        let view = PauseContent(
            placeName: place.name, usedMinutes: usedMinutes, budgetMinutes: budgetMinutes, overBudget: overBudget,
            variant: variant, startedAt: Date(),
            onClose: { [weak self] in self?.closePause(); close() },
            onOpen: { [weak self] in self?.closePause(); open() }
        )
        pausePanel = present(view, shade: variant == .b, keyable: false)
        pausePlace = place.id
    }

    /// Closes the pause panel unless it is for `place`, the guarded place now in front.
    func dismissPause(unlessPlace place: UUID?) {
        guard pausePanel != nil, pausePlace != place else { return }
        closePause()
    }

    /// The block panel: a card with Close and a deliberate unlock (hold, variant A; type, variant B).
    func showBlock(place: GuardedPlace, until: Date?, variant: Variant,
                   close: @escaping @MainActor () -> Void, unlock: @escaping @MainActor () -> Void) {
        closeBlock()
        let view = BlockContent(
            placeName: place.name, until: until, variant: variant,
            onClose: { [weak self] in self?.closeBlock(); close() },
            onUnlock: { [weak self] in self?.closeBlock(); unlock() }
        )
        blockPanel = present(view, shade: false, keyable: variant == .b)
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

    private func present<Content: View>(_ view: Content, shade: Bool, keyable: Bool) -> Panel {
        let host = Host(rootView: view)
        let screen = Self.screen()
        let frame: NSRect
        if shade {
            frame = screen.frame
        } else {
            let size = host.fittingSize
            let area = screen.visibleFrame
            frame = NSRect(x: area.midX - size.width / 2, y: area.maxY - size.height - 12, width: size.width, height: size.height)
        }
        let panel = Panel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.keyable = keyable
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = !shade
        panel.level = shade ? .statusBar : .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        if keyable { panel.makeKey() }
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
struct PauseContent: View {
    var placeName: String
    var usedMinutes: Int
    var budgetMinutes: Int
    var overBudget: Bool
    var variant: Variant
    var startedAt = Date()
    /// A fixed number of seconds into the pause, for screenshots; nil runs the clock.
    var elapsed: Double?
    var onClose: @MainActor () -> Void = {}
    var onOpen: @MainActor () -> Void = {}

    static let seconds = Double(GuardList.pauseSeconds)

    var body: some View {
        if let elapsed {
            content(elapsed)
        } else {
            TimelineView(.animation) { context in content(context.date.timeIntervalSince(startedAt)) }
        }
    }

    private var statusLine: String {
        overBudget ? "Over budget · \(usedMinutes) of \(budgetMinutes) min today" : "\(usedMinutes) of \(budgetMinutes) min today"
    }

    @ViewBuilder
    private func content(_ elapsed: Double) -> some View {
        let ready = elapsed >= Self.seconds
        if variant == .a {
            card(elapsed, ready: ready)
        } else {
            shade(elapsed, ready: ready)
        }
    }

    private func card(_ elapsed: Double, ready: Bool) -> some View {
        let progress = min(1, max(0, elapsed / Self.seconds))
        let left = Int(max(0, Self.seconds - elapsed).rounded(.up))
        return VStack(spacing: 12) {
            Text(placeName).font(.title3.weight(.semibold))
            Text(statusLine)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(overBudget ? Color.orange : Color.secondary)
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(ready ? Color.green : Color.orange, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if ready {
                    Image(systemName: "checkmark").font(.title2.weight(.semibold)).foregroundStyle(.green)
                } else {
                    Text("\(left)").font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
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

    private func shade(_ elapsed: Double, ready: Bool) -> some View {
        let progress = min(1, max(0, elapsed / Self.seconds))
        // One slow breath over the 5 seconds: the circle grows, then settles.
        let breath = 0.5 - 0.5 * cos(2 * Double.pi * progress)
        let left = Int(max(0, Self.seconds - elapsed).rounded(.up))
        return ZStack {
            Color.black.opacity(0.58)
            VStack(spacing: 18) {
                ZStack {
                    Circle().stroke(.white.opacity(0.25), lineWidth: 2).frame(width: 220, height: 220)
                    Circle().fill(.white.opacity(0.30)).frame(width: 220 * (0.40 + 0.60 * breath), height: 220 * (0.40 + 0.60 * breath))
                    if ready {
                        Image(systemName: "checkmark").font(.system(size: 34, weight: .semibold)).foregroundStyle(.white)
                    } else {
                        Text("\(left)").font(.system(size: 44, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                    }
                }
                Text(placeName).font(.system(size: 34, weight: .semibold)).foregroundStyle(.white)
                Text(statusLine)
                    .font(.title3)
                    .monospacedDigit()
                    .foregroundStyle(overBudget ? Color.orange : Color.white.opacity(0.8))
                PauseButtons(ready: ready, onClose: onClose, onOpen: onOpen)
                    .frame(width: 300)
                    .padding(.top, 6)
            }
        }
    }
}

private struct PauseButtons: View {
    var ready: Bool
    var onClose: @MainActor () -> Void
    var onOpen: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: onClose) {
                Text("Close").frame(maxWidth: .infinity)
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

/// "Instagram is blocked until 18:00": Close, and a deliberate unlock, by holding a button for 3
/// seconds (variant A) or by typing the place's name (variant B).
struct BlockContent: View {
    var placeName: String
    var until: Date?
    var variant: Variant
    var onClose: @MainActor () -> Void
    var onUnlock: @MainActor () -> Void
    /// Fixed hold progress for screenshots; nil follows the press.
    var holdFraction: Double?

    @State private var typed: String
    @FocusState private var focused: Bool

    init(placeName: String, until: Date?, variant: Variant, typed: String = "", holdFraction: Double? = nil,
         onClose: @escaping @MainActor () -> Void = {}, onUnlock: @escaping @MainActor () -> Void = {}) {
        self.placeName = placeName
        self.until = until
        self.variant = variant
        self.holdFraction = holdFraction
        self.onClose = onClose
        self.onUnlock = onUnlock
        _typed = State(initialValue: typed)
    }

    private var title: String {
        guard let until else { return "\(placeName) is blocked" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return "\(placeName) is blocked until \(f.string(from: until))"
    }

    private var typedMatches: Bool {
        typed.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(placeName) == .orderedSame
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "hand.raised.fill").font(.title).foregroundStyle(.orange)
            Text(title).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
            Text("Work hours. Unlocking opens it for \(GuardList.passMinutes) minutes.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: onClose) {
                Text("Close").frame(maxWidth: .infinity)
            }
            .buttonStyle(FilledCloseStyle())
            if variant == .a {
                HoldToUnlock(fractionOverride: holdFraction, onDone: onUnlock)
            } else {
                VStack(spacing: 6) {
                    TextField("Type \u{201C}\(placeName)\u{201D} to unlock", text: $typed)
                        .textFieldStyle(.roundedBorder)
                        .focused($focused)
                        .onSubmit { if typedMatches { onUnlock() } }
                    Button("Unlock", action: onUnlock)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!typedMatches)
                }
                .onAppear { focused = true }
            }
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
