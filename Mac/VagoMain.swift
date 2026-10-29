import AppKit
import VagoKit

@main
@MainActor
enum VagoMain {
    // The delegate must outlive `run()`; NSApplication keeps only a weak reference to it.
    private static let delegate = AppDelegate()

    static func main() {
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel()
        let status = StatusItemController(model: model)
        let nudger = Nudger { [weak model] key, bucket in model?.answerNudge(key: key, as: bucket) }
        model.nudger = nudger
        model.onChange = { [weak status] in status?.update() }
        model.attachSync()
        let tracker = Tracker(model: model)
        tracker.start()
        self.model = model
        self.status = status
        self.nudger = nudger
        self.tracker = tracker

        if !model.onboarded {
            // First run: ask for Accessibility now, and explain Automation in the popover.
            Permissions.requestAccessibility()
            model.markOnboarded()
            DispatchQueue.main.async { status.showPopover() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        tracker?.stop()
        model?.flush(force: true)
    }
}
