import AppKit
import VagoKit

@main
@MainActor
enum VagoMain {
    // The delegate must outlive `run()`; NSApplication keeps only a weak reference to it.
    private static let delegate = AppDelegate()

    static func main() {
        #if DEBUG
        // `--render-variants <dir>` writes the PNGs of the new screens from sample data and exits.
        // It runs before any model exists: nothing under Application Support is read or written.
        if let dir = RenderVariants.directory(in: CommandLine.arguments) {
            NSApplication.shared.setActivationPolicy(.accessory)
            exit(RenderVariants.run(into: dir) ? 0 : 1)
        }
        #endif
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var tracker: Tracker?
    private var status: StatusItemController?
    private var nudger: Nudger?
    /// A `vago://day` that arrived before launch finished (a widget tap while Vago was closed).
    private var openDayWhenReady = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel()
        let status = StatusItemController(model: model)
        let nudger = Nudger()
        model.nudger = nudger
        model.notices.onSwitchToWork = { [weak model] key in model?.setToggle(key, to: .productive) }
        model.notices.start()
        model.startControlBridge()
        model.onChange = { [weak status] in status?.update() }
        model.attachSync()
        let tracker = Tracker(model: model)
        tracker.start()
        self.model = model
        self.status = status
        self.nudger = nudger
        self.tracker = tracker

        if openDayWhenReady {
            openDayWhenReady = false
            NSApp.activate()
            status.open(.day)
        }

        if !model.onboarded {
            // First run: ask for Accessibility now, and explain Automation in the popover.
            Permissions.requestAccessibility()
            model.markOnboarded()
            DispatchQueue.main.async { status.showPopover() }
        }

        if !model.guardList.enabled, !model.setupOffered {
            // The first run of the core loop: pick the guarded places once.
            model.setupOffered = true
            model.dirty = true
            DispatchQueue.main.async { status.open(.setup) }
        }
    }

    /// `vago://day` (the widget's tap) opens the Day window.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == "vago" && ($0.host ?? "") == "day" }) else { return }
        guard let status else { openDayWhenReady = true; return }
        NSApp.activate()
        status.open(.day)
    }

    func applicationWillTerminate(_ notification: Notification) {
        tracker?.stop()
        model?.flush(force: true)
    }
}
