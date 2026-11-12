import AppKit
import VagoKit

/// Closes the place in front: the tab for a web place in a known browser (Apple Events), the app
/// otherwise (`NSRunningApplication.hide`).
enum PlaceControl {
    /// Apple Events block on the target app, so they run on their own serial queue.
    private static let queue = DispatchQueue(label: "com.zaitsew.vago.close", qos: .userInitiated)

    @MainActor
    static func close(_ obs: ActivitySample) {
        let bundle = obs.bundleID
        if obs.host != nil, let family = Browser.family(of: bundle) {
            let command = family == .safari ? "close current tab of front window" : "close active tab of front window"
            // "with timeout" keeps a hung browser from blocking the queue for the 2-minute default.
            let source = """
            with timeout of 2 seconds
                tell application id "\(bundle)"
                    \(command)
                end tell
            end timeout
            """
            queue.async {
                var error: NSDictionary?
                NSAppleScript(source: source)?.executeAndReturnError(&error)
                if let error { NSLog("Vago: could not close the tab: %@", String(describing: error[NSAppleScript.errorNumber])) }
            }
        } else {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first?.hide()
        }
    }
}
