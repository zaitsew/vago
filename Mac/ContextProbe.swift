import AppKit
import ApplicationServices

/// What the probe found out about the front app's window.
struct ProbedContext: Sendable, Equatable {
    enum Status: Sendable, Equatable {
        case ok
        case automationDenied        // the owner refused (or has not yet allowed) Apple Events for this browser
        case accessibilityDenied     // no Accessibility: only the app name is known
        case unavailable             // the app had no window, or did not answer in time
    }
    var title: String?
    var url: URL?
    var status: Status
    var at: Date
}

/// Reads a browser's front tab (Apple Events) or any app's focused window title (Accessibility).
///
/// `NSAppleScript` and the Accessibility API both block on the target app, so every read runs on
/// one serial queue away from the main thread, and the tracker uses the last answer for the
/// current second. One read at a time per app; a slow app never stacks up requests.
actor ContextProbe {
    private var cache: [pid_t: ProbedContext] = [:]
    private var inFlight: [pid_t: Task<ProbedContext, Never>] = [:]
    private let worker = ProbeWorker()

    /// The newest answer for `app`, if any.
    func latest(for app: FrontApp) -> ProbedContext? { cache[app.pid] }

    /// Reads now (or joins the read already running) and caches the answer.
    @discardableResult
    func refresh(_ app: FrontApp) async -> ProbedContext {
        if let running = inFlight[app.pid] { return await running.value }
        let worker = self.worker
        let task = Task { await worker.read(app) }
        inFlight[app.pid] = task
        let result = await task.value
        inFlight[app.pid] = nil
        cache[app.pid] = result
        if cache.count > 40 { cache = cache.filter { $0.value.at > Date().addingTimeInterval(-300) } }
        return result
    }

    /// Starts a read without waiting for it, unless one is already running.
    func refreshInBackground(_ app: FrontApp) {
        guard inFlight[app.pid] == nil else { return }
        Task { await self.refresh(app) }
    }
}

/// Owns the serial queue the blocking calls run on.
private final class ProbeWorker: @unchecked Sendable {
    // @unchecked Sendable: the only state is a serial queue; all reads of the scripts and
    // Accessibility elements happen on it, one at a time.
    private let queue = DispatchQueue(label: "com.zaitsew.vago.probe", qos: .userInitiated)

    func read(_ app: FrontApp) async -> ProbedContext {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: Self.readNow(app))
            }
        }
    }

    private static func readNow(_ app: FrontApp) -> ProbedContext {
        let now = Date()
        var automationDenied = false
        if let family = Browser.family(of: app.bundleID) {
            switch Self.readBrowser(app.bundleID, family: family) {
            case .success(let tab):
                return ProbedContext(title: tab.title, url: tab.url, status: .ok, at: now)
            case .failure(let reason):
                automationDenied = reason == .denied
                // Fall through: the window title through Accessibility still tells something.
            }
        }
        guard AXIsProcessTrusted() else {
            return ProbedContext(title: nil, url: nil, status: automationDenied ? .automationDenied : .accessibilityDenied, at: now)
        }
        let title = focusedWindowTitle(pid: app.pid)
        return ProbedContext(title: title, url: nil, status: automationDenied ? .automationDenied : (title == nil ? .unavailable : .ok), at: now)
    }

    // MARK: Accessibility

    private static func focusedWindowTitle(pid: pid_t) -> String? {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.4)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID()
        else { return nil }
        // The type id check above makes this cast safe.
        let windowElement = unsafeDowncast(window as AnyObject, to: AXUIElement.self)
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &title) == .success,
              let text = title as? String, !text.isEmpty
        else { return nil }
        return text
    }

    // MARK: Apple Events

    private struct Tab { var url: URL?; var title: String? }
    private enum Failure: Error { case denied, other }

    private static func readBrowser(_ bundleID: String, family: Browser.Family) -> Result<Tab, Failure> {
        let body: String
        switch family {
        case .safari:
            body = "return (URL of front document) & linefeed & (name of front document)"
        case .chromium:
            body = "return (URL of active tab of front window) & linefeed & (title of active tab of front window)"
        }
        // "with timeout" keeps a hung browser from blocking the queue for the 2-minute default.
        let source = """
        with timeout of 2 seconds
            tell application id "\(bundleID)"
                \(body)
            end tell
        end timeout
        """
        guard let script = NSAppleScript(source: source) else { return .failure(.other) }
        var error: NSDictionary?
        let output = script.executeAndReturnError(&error)
        if let error {
            let code = (error[NSAppleScript.errorNumber] as? Int) ?? 0
            // -1743: not authorised to send Apple Events. -1744: the user is being asked.
            return .failure(code == -1743 || code == -1744 ? .denied : .other)
        }
        guard let text = output.stringValue else { return .failure(.other) }
        let parts = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let url = parts.first.flatMap { URL(string: $0) }
        let title = parts.count > 1 ? parts[1] : nil
        return .success(Tab(url: url?.scheme == nil ? nil : url, title: title?.isEmpty == true ? nil : title))
    }
}
