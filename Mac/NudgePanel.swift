import AppKit
import SwiftUI

/// A small panel that floats near the top centre of the screen without taking focus from the
/// app the owner is using.
@MainActor
final class NudgePanel {
    struct Button: Identifiable {
        var id: String { title }
        var title: String
        var prominent: Bool
        var action: @MainActor () -> Void
    }

    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private final class Host<Content: View>: NSHostingView<Content> {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    private var panel: Panel?
    private var dismissTask: Task<Void, Never>?
    private(set) var isShowing = false

    func show(title: String, subtitle: String?, buttons: [Button], seconds: Double = 25) {
        close()
        let view = NudgeView(title: title, subtitle: subtitle, buttons: buttons.map { button in
            Button(title: button.title, prominent: button.prominent) { [weak self] in
                button.action()
                self?.close()
            }
        })
        let host = Host(rootView: view)
        let size = host.fittingSize
        let panel = Panel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.setFrameOrigin(Self.origin(for: size))
        panel.orderFrontRegardless()
        self.panel = panel
        isShowing = true
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled { self?.close() }
        }
    }

    func close() {
        dismissTask?.cancel()
        dismissTask = nil
        panel?.orderOut(nil)
        panel = nil
        isShowing = false
    }

    /// Top centre of the screen the pointer is on, just under the menu bar.
    private static func origin(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let area = screen.visibleFrame
        return NSPoint(x: area.midX - size.width / 2, y: area.maxY - size.height - 12)
    }
}

private struct NudgeView: View {
    var title: String
    var subtitle: String?
    var buttons: [NudgePanel.Button]

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            HStack(spacing: 8) {
                ForEach(buttons) { button in
                    if button.prominent {
                        SwiftUI.Button(button.title) { button.action() }.buttonStyle(.borderedProminent)
                    } else {
                        SwiftUI.Button(button.title) { button.action() }.buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.separator))
        .fixedSize()
        .padding(10)
    }
}
