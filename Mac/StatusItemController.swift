import AppKit
import SwiftUI
import VagoKit

/// The menu-bar item and the popover behind it.
@MainActor
final class StatusItemController: NSObject {
    private let model: AppModel
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var shown = ""

    init(model: AppModel) {
        self.model = model
        super.init()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverView(model: model))
        if let button = item.button {
            button.target = self
            button.action = #selector(toggle(_:))
            button.setAccessibilityLabel("Vago")
        }
        update()
    }

    /// Redraws the title: the readout tinted by mood, or the focus tree and minutes left.
    func update() {
        let (text, tint) = model.menuBar
        let key = "\(text)|\(tint?.rawValue ?? "-")"
        guard key != shown else { return }
        shown = key
        let color: NSColor = switch tint {
        case .green: .systemGreen
        case .yellow: .systemYellow
        case .red: .systemRed
        case nil: .labelColor
        }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        item.button?.attributedTitle = NSAttributedString(string: text, attributes: [.foregroundColor: color, .font: font])
    }

    func showPopover() {
        guard let button = item.button, !popover.isShown else { return }
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    @objc private func toggle(_ sender: Any?) {
        if popover.isShown { popover.performClose(sender) } else { showPopover() }
    }
}
