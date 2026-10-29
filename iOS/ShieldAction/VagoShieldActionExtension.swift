import DeviceActivity
import Foundation
import ManagedSettings
import VagoKit

/// The two buttons of the intent check. "Work" and "Scroll" lift the shield for a pass;
/// the monitor extension puts it back when the pass is used up.
final class VagoShieldActionExtension: ShieldActionDelegate {
    override func handle(action: ShieldAction, for application: ApplicationToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(respond(to: action))
    }

    override func handle(action: ShieldAction, for webDomain: WebDomainToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(respond(to: action))
    }

    override func handle(action: ShieldAction, for category: ActivityCategoryToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(respond(to: action))
    }

    private func respond(to action: ShieldAction) -> ShieldActionResponse {
        let store = VagoStore()
        let now = Date()
        // During focus there is one button, "Back to focus". It closes the app.
        if store.activeFocus(now: now) != nil { return .close }

        switch action {
        case .primaryButtonPressed: grant(.work, store: store, now: now)
        case .secondaryButtonPressed: grant(.scroll, store: store, now: now)
        default: break
        }
        return .close
    }

    /// Starts the `pass` monitoring first, then lifts the shield. If monitoring cannot start,
    /// the shield stays: a pass nothing can end would turn the gate into an open door.
    private func grant(_ kind: Pass.Kind, store: VagoStore, now: Date) {
        let pass = Pass(kind: kind, start: now, endedAt: nil)
        do {
            try VagoMonitoring.startPass(pass, store: store)
        } catch {
            store.lastError = "Could not start a pass: \(error.localizedDescription)"
            return
        }
        store.setPass(pass)
        VagoShields.liftAmbiguous()
    }
}
