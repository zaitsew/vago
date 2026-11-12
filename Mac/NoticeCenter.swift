import Foundation
import UserNotifications

/// The drift notice: a local notification when the owner moves from work into procrastination.
/// A statement, never a question. Variant A is the text only; variant B adds a "Switch to work" action.
final class NoticeCenter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    // @unchecked Sendable: `onSwitchToWork` is set once at launch, before notifications can arrive.
    static let categoryID = "vago.drift"
    static let actionID = "vago.switch-to-work"

    /// Called with the place key when the owner taps "Switch to work". Set by the app delegate.
    var onSwitchToWork: (@MainActor @Sendable (String) -> Void)?

    /// Makes this the delegate and registers the action. Called at launch.
    func start() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let action = UNNotificationAction(identifier: Self.actionID, title: "Switch to work", options: [])
        let category = UNNotificationCategory(identifier: Self.categoryID, actions: [action], intentIdentifiers: [])
        center.setNotificationCategories([category])
    }

    /// Asked for once, when setup finishes.
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error { NSLog("Vago: notification authorization failed: %@", error.localizedDescription) }
        }
    }

    func postDrift(placeName: String, placeKey: String, usedMinutes: Int, budgetMinutes: Int, withAction: Bool) {
        let content = UNMutableNotificationContent()
        content.title = "Procrastination · \(placeName)"
        content.body = "\(usedMinutes) of \(budgetMinutes) min today"
        content.userInfo = ["placeKey": placeKey]
        if withAction { content.categoryIdentifier = Self.categoryID }
        let request = UNNotificationRequest(identifier: "vago.drift", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { NSLog("Vago: drift notice failed: %@", error.localizedDescription) }
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Shows the banner even while Vago is the active app.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == Self.actionID,
              let key = response.notification.request.content.userInfo["placeKey"] as? String else { return }
        let handler = onSwitchToWork
        await MainActor.run { handler?(key) }
    }
}
