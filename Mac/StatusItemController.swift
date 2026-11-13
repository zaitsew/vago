import AppKit
import SwiftUI
import VagoKit

/// The menu-bar item, the popover behind it, and the Day and Settings windows it opens.
/// Left click toggles the popover; right click shows a short menu.
@MainActor
final class StatusItemController: NSObject {
    private let model: AppModel
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private lazy var settings = SettingsWindow.make(model: model)
    private lazy var day = DayWindow.make(model: model)
    private var review: HostedWindow?
    private var setup: HostedWindow?
    private var shown = ""

    init(model: AppModel) {
        self.model = model
        super.init()
        popover.behavior = .transient
        let host = NSHostingController(rootView: PopoverView(model: model))
        host.sizingOptions = [.preferredContentSize]   // the popover follows the fixed SwiftUI layout
        popover.contentViewController = host
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Vago")
        }
        model.openWindow = { [weak self] window in self?.open(window) }
        update()
    }

    /// Redraws the title: mood and share tinted by mood, or the focus tree and minutes left.
    func update() {
        let (text, tint) = model.menuBar
        let mode = model.currentMode
        let key = "\(text)|\(tint?.rawValue ?? "-")|\(mode.rawValue)"
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
        item.button?.image = ModeBadgeImage.make(mode: mode, scale: NSScreen.main?.backingScaleFactor ?? 2)
        item.button?.imagePosition = .imageLeading
        item.button?.toolTip = String(localized: "Vago · \(ModeBadge.name(mode))", comment: "Tooltip of the menu-bar item. The argument is the mode name.")
    }

    func showPopover() {
        guard let button = item.button, !popover.isShown else { return }
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func open(_ window: AppWindow) {
        popover.performClose(nil)
        switch window {
        case .day: day.show()
        case .settings: settings.show()
        case .eveningReview:
            // A fresh window each time: it snapshots today's unsure places when it opens.
            review?.close()
            let fresh = EveningReviewWindow.make(model: model)
            review = fresh
            fresh.show()
        case .setup:
            // A fresh window each time: it starts from today's proposals and the current list.
            setup?.close()
            let fresh = SetupWindow.make(model: model)
            setup = fresh
            fresh.show()
        }
    }

    @objc private func clicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    private func showMenu() {
        guard let button = item.button else { return }
        popover.performClose(nil)
        let menu = NSMenu()
        menu.autoenablesItems = false
        let switchItem = menu.addItem(withTitle: switchTitle(), action: #selector(toggleMode), keyEquivalent: "")
        switchItem.target = self
        switchItem.isEnabled = model.toggleTarget != nil
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Day", comment: "Right-click menu item: opens the Day window."), action: #selector(openDay), keyEquivalent: "d").target = self
        menu.addItem(withTitle: String(localized: "Settings…", comment: "Right-click menu item: opens Settings."), action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Quit Vago", comment: "Right-click menu item: quits the app."), action: #selector(quit), keyEquivalent: "q").target = self
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
    }

    private func switchTitle() -> String {
        guard let target = model.toggleTarget else { return String(localized: "Switch place to work", comment: "Right-click menu item before any place was seen.") }
        let name = model.displayName(target)
        return model.toggleIsWork
            ? String(localized: "Switch \(name) to procrastination", comment: "Right-click menu item. The argument is the place name.")
            : String(localized: "Switch \(name) to work", comment: "Right-click menu item. The argument is the place name.")
    }

    @objc private func toggleMode() { model.toggleCurrent() }
    @objc private func openDay() { open(.day) }
    @objc private func openSettings() { open(.settings) }
    @objc private func quit() { NSApp.terminate(nil) }
}
