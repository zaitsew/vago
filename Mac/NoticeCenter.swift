import AppKit
import Foundation
import SwiftUI
import UserNotifications
import VagoKit

/// What one drift notice says and how it is drawn: the text, the picture on the right, and how the
/// system groups and ranks it. Pure data, so the banner, the attachment and the mock all read the same.
///
/// A statement, never a question. Both variants carry the "Switch to work" button.
/// - A: title "Procrastination · Instagram", body "18 min left of 30 today", the pill and a budget bar.
/// - B: title "18 of 30 min left", subtitle "Instagram counts as waste", a budget ring.
struct NoticePayload: Equatable, Sendable {
    enum Art: Sendable { case pillBar, ring }

    var title: String
    var subtitle: String
    var body: String
    var art: Art
    var placeKey: String
    var usedMinutes: Int
    var budgetMinutes: Int
    /// One identifier per day: a new notice replaces the one on screen, so they never stack.
    var identifier: String
    var relevance: Double

    static let thread = "vago.drift"

    var leftMinutes: Int { budgetMinutes - usedMinutes }
    var isOver: Bool { leftMinutes < 0 }
    /// 0...1 of the budget used.
    var fractionUsed: Double { budgetMinutes > 0 ? min(1, Double(usedMinutes) / Double(budgetMinutes)) : 1 }
    /// What the bar and the ring fill: the part of the budget left, so the picture matches
    /// the "min left" number. Over budget it is a full ring in the over-budget colour.
    var fractionShown: Double { fractionUsed >= 1 ? 1 : max(0.02, 1 - fractionUsed) }

    static func make(variant: Variant, placeName: String, placeKey: String, usedMinutes: Int,
                     budgetMinutes: Int, day: DayKey) -> NoticePayload {
        let left = budgetMinutes - usedMinutes
        let title: String
        let subtitle: String
        let body: String
        switch variant {
        case .a:
            title = String(localized: "Procrastination · \(placeName)", comment: "Drift notice title, variant A. The argument is the place name.")
            subtitle = ""
            body = left > 0
                ? String(localized: "\(left) min left of \(budgetMinutes) today", comment: "Drift notice body: minutes left of the daily budget. First argument: minutes left; second: the budget.")
                : left == 0
                ? String(localized: "Budget used: \(budgetMinutes) of \(budgetMinutes) min today", comment: "Drift notice body when the budget is exactly used up. The arguments are the budget in minutes, twice.")
                : String(localized: "\(-left) min over your \(budgetMinutes) today", comment: "Drift notice body when over budget. First argument: minutes over; second: the budget in minutes.")
        case .b:
            title = left > 0
                ? String(localized: "\(left) of \(budgetMinutes) min left", comment: "Drift notice title, variant B: minutes left of the daily budget. First argument: minutes left; second: the budget.")
                : left == 0
                ? String(localized: "Budget used: \(budgetMinutes) min", comment: "Drift notice title, variant B, when the budget is exactly used up. The argument is the budget in minutes.")
                : String(localized: "\(-left) min over budget", comment: "Drift notice title, variant B, when over budget. The argument is minutes over.")
            subtitle = String(localized: "\(placeName) counts as waste", comment: "Drift notice subtitle, variant B. The argument is the place name.")
            body = ""
        }
        // Closer to the limit ranks higher in the notification summary; over budget ranks first.
        let relevance = left < 0 ? 1.0 : max(0.3, budgetMinutes > 0 ? Double(usedMinutes) / Double(budgetMinutes) : 1)
        return NoticePayload(title: title, subtitle: subtitle, body: body, art: variant == .a ? .pillBar : .ring,
                             placeKey: placeKey, usedMinutes: usedMinutes, budgetMinutes: budgetMinutes,
                             identifier: "vago.drift.\(day.id)", relevance: relevance)
    }
}

/// The picture on the right of the banner. Colour lives here: the pill in the mode colour and a
/// budget bar or ring that goes green, then orange, then red.
struct NoticeArt: View {
    var payload: NoticePayload

    static let side: CGFloat = 160

    static func budgetColor(_ fractionUsed: Double) -> Color {
        fractionUsed < 0.67 ? .green : fractionUsed < 1 ? .orange : .red
    }

    var body: some View {
        let color = Self.budgetColor(payload.fractionUsed)
        ZStack {
            Color(white: 0.97)
            switch payload.art {
            case .pillBar: pillBar(color)
            case .ring: ring(color)
            }
        }
        .frame(width: Self.side, height: Self.side)
        .environment(\.colorScheme, .light)
    }

    private var numberText: String { payload.isOver ? "+\(-payload.leftMinutes)" : "\(payload.leftMinutes)" }
    private var captionText: String {
        payload.isOver
            ? String(localized: "min over", comment: "Notice picture caption under the number when over budget.")
            : String(localized: "min left", comment: "Notice picture caption under the number of minutes left.")
    }

    private func pillBar(_ color: Color) -> some View {
        VStack(spacing: 8) {
            ModeBadge(mode: .procrastination).scaleEffect(1.5).frame(height: 28)
            Text(verbatim: numberText).font(.system(size: 48, weight: .heavy, design: .rounded)).foregroundStyle(color).minimumScaleFactor(0.6)
            Text(verbatim: captionText).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            Capsule().fill(Color.gray.opacity(0.2)).frame(width: 112, height: 10)
                .overlay(alignment: .leading) { Capsule().fill(color).frame(width: 112 * max(0.04, payload.fractionShown)) }
        }
    }

    private func ring(_ color: Color) -> some View {
        ZStack {
            Circle().stroke(Color.gray.opacity(0.2), lineWidth: 14)
            Circle().trim(from: 0, to: payload.fractionShown)
                .stroke(color, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(verbatim: numberText).font(.system(size: 40, weight: .heavy, design: .rounded)).foregroundStyle(color).minimumScaleFactor(0.6)
                Text(verbatim: captionText).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
        .padding(22)
    }

    /// The picture as PNG bytes, drawn at runtime.
    @MainActor
    static func png(_ payload: NoticePayload) -> Data? {
        let renderer = ImageRenderer(content: NoticeArt(payload: payload))
        renderer.scale = 3
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

/// The drift notice: a local notification when the owner moves from work into procrastination.
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
        center.setNotificationCategories([Self.category()])
    }

    static func category() -> UNNotificationCategory {
        let action = UNNotificationAction(identifier: actionID,
                                          title: String(localized: "Switch to work", comment: "Drift notice button: counts the place as work."),
                                          options: [])
        return UNNotificationCategory(identifier: categoryID, actions: [action], intentIdentifiers: [])
    }

    /// Asked for once, when setup finishes.
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error { NSLog("Vago: notification authorization failed: %@", error.localizedDescription) }
        }
    }

    /// Posts the notice, replacing today's earlier one (same identifier) in the one drift thread.
    @MainActor
    func post(_ payload: NoticePayload) {
        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.subtitle = payload.subtitle
        content.body = payload.body
        content.userInfo = ["placeKey": payload.placeKey]
        content.categoryIdentifier = Self.categoryID
        content.threadIdentifier = NoticePayload.thread
        content.relevanceScore = payload.relevance
        content.interruptionLevel = .active
        if let attachment = Self.attachment(for: payload) { content.attachments = [attachment] }
        let request = UNNotificationRequest(identifier: payload.identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { NSLog("Vago: drift notice failed: %@", error.localizedDescription) }
        }
    }

    /// The picture, written to a temporary file the system takes over.
    @MainActor
    private static func attachment(for payload: NoticePayload) -> UNNotificationAttachment? {
        guard let data = NoticeArt.png(payload) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vago-notice-\(UUID().uuidString).png")
        do {
            try data.write(to: url)
            return try UNNotificationAttachment(identifier: "art", url: url, options: nil)
        } catch {
            NSLog("Vago: notice picture failed: %@", error.localizedDescription)
            return nil
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
