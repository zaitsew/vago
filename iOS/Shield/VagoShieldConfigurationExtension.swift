import Foundation
import ManagedSettings
import ManagedSettingsUI
import UIKit
import VagoKit

/// What the shield says. During a focus session: the tree and the minutes left, one button.
/// Otherwise the intent check: mood, today's count, "Work" or "Scroll".
final class VagoShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration { make() }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        make()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration { make() }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        make()
    }

    private func make() -> ShieldConfiguration {
        let store = VagoStore()
        let now = Date()
        let accent = UIColor.systemIndigo

        if let focus = store.activeFocus(now: now) {
            let left = max(1, Int((focus.remaining(at: now) / 60).rounded(.up)))
            return ShieldConfiguration(
                backgroundBlurStyle: .systemUltraThinMaterial,
                title: .init(text: "\(focus.stage(at: now)) Focus — \(left) min left", color: .label),
                subtitle: .init(text: "This app waits until the tree has grown.", color: .secondaryLabel),
                primaryButtonLabel: .init(text: "Back to focus", color: .white),
                primaryButtonBackgroundColor: accent
            )
        }

        let snapshot = store.snapshot(now: now)
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterial,
            title: .init(text: "\(snapshot.mood.emoji) Work or scroll?", color: .label),
            subtitle: .init(text: "\(snapshot.minutesUsed) of \(snapshot.limitMinutes) min today", color: .secondaryLabel),
            primaryButtonLabel: .init(text: "Work · \(Pass.workMinutes) min", color: .white),
            primaryButtonBackgroundColor: accent,
            secondaryButtonLabel: .init(text: "Scroll · \(Pass.scrollMinutes) min", color: accent)
        )
    }
}
