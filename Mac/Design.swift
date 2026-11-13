import Foundation
import SwiftUI
import VagoKit

/// One of the two designs of a new screen. The owner reviews both; nothing is decided in code.
enum Variant: String, Codable, Sendable, CaseIterable {
    case a, b
    var label: String { rawValue.uppercased() }
}

/// The new screens that still have two designs. The others were decided on 13 November 2026:
/// mode icon B (the pill), toggle B (resets), pause A (the card), block A (hold to unlock).
enum DesignScreen: String, Codable, Sendable, CaseIterable {
    case setup, notice

    var title: String {
        switch self {
        case .setup: String(localized: "Setup", comment: "Name of a screen that has two designs, in the hidden design-variants section of Settings.")
        case .notice: String(localized: "Drift notice", comment: "Name of a screen that has two designs, in the hidden design-variants section of Settings.")
        }
    }

    /// `defaults write com.zaitsew.vago.mac variant.<screen> b`, read at launch.
    var defaultsKey: String { "variant.\(rawValue)" }
}

/// Which variant each remaining screen shows. Stored in `state.json`; a `variant.<screen>` key in the
/// app's user defaults wins at launch, so a variant can change without a rebuild. Keys of screens
/// that were decided (pausePanel, blockPanel, modeIcon, toggle) are ignored when an old file has them.
struct DesignVariants: Codable, Sendable, Equatable {
    var setup = Variant.a
    var notice = Variant.a

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        setup = try c.decodeIfPresent(Variant.self, forKey: .setup) ?? .a
        notice = try c.decodeIfPresent(Variant.self, forKey: .notice) ?? .a
    }

    private enum Keys: String, CodingKey { case setup, notice }

    subscript(screen: DesignScreen) -> Variant {
        get {
            switch screen {
            case .setup: setup
            case .notice: notice
            }
        }
        set {
            switch screen {
            case .setup: setup = newValue
            case .notice: notice = newValue
            }
        }
    }

    /// Applies `variant.<screen>` keys from the app's defaults.
    mutating func applyDefaults(_ defaults: UserDefaults = .standard) {
        for screen in DesignScreen.allCases {
            if let raw = defaults.string(forKey: screen.defaultsKey)?.lowercased(), let variant = Variant(rawValue: raw) {
                self[screen] = variant
            }
        }
    }
}

/// What the owner's toggle is keyed by: the host for a web page, the bundle id for an app. Coarser
/// than `SiteKey`, so flipping Instagram covers every Instagram page.
enum PlaceKey {
    static func of(_ o: ActivitySample) -> String { o.host ?? o.bundleID }
}

extension Palette {
    /// The mode colours: work green, procrastination red, neutral grey.
    static func modeColor(_ mode: Mode) -> Color {
        switch mode {
        case .work: .green
        case .procrastination: .red
        case .neutral: .gray
        }
    }
}
