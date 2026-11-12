import Foundation
import SwiftUI
import VagoKit

/// One of the two designs of a new screen. The owner reviews both; nothing is decided in code.
enum Variant: String, Codable, Sendable, CaseIterable {
    case a, b
    var label: String { rawValue.uppercased() }
}

/// The new screens that have two designs.
enum DesignScreen: String, Codable, Sendable, CaseIterable {
    case setup, pausePanel, blockPanel, modeIcon, toggle, notice

    var title: String {
        switch self {
        case .setup: "Setup (A one page, B three steps)"
        case .pausePanel: "Pause panel (A card, B shade)"
        case .blockPanel: "Block panel (A hold, B type)"
        case .modeIcon: "Mode icon (A dot, B word)"
        case .toggle: "Toggle (A sticks, B resets)"
        case .notice: "Drift notice (A text, B with action)"
        }
    }

    /// `defaults write com.zaitsew.vago.mac variant.<screen> b`, read at launch.
    var defaultsKey: String { "variant.\(rawValue)" }
}

/// Which variant each new screen shows. Stored in `state.json`; a `variant.<screen>` key in the
/// app's user defaults wins at launch, so a variant can change without a rebuild.
struct DesignVariants: Codable, Sendable, Equatable {
    var setup = Variant.a
    var pausePanel = Variant.a
    var blockPanel = Variant.a
    var modeIcon = Variant.a
    var toggle = Variant.a
    var notice = Variant.a

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        setup = try c.decodeIfPresent(Variant.self, forKey: .setup) ?? .a
        pausePanel = try c.decodeIfPresent(Variant.self, forKey: .pausePanel) ?? .a
        blockPanel = try c.decodeIfPresent(Variant.self, forKey: .blockPanel) ?? .a
        modeIcon = try c.decodeIfPresent(Variant.self, forKey: .modeIcon) ?? .a
        toggle = try c.decodeIfPresent(Variant.self, forKey: .toggle) ?? .a
        notice = try c.decodeIfPresent(Variant.self, forKey: .notice) ?? .a
    }

    private enum Keys: String, CodingKey { case setup, pausePanel, blockPanel, modeIcon, toggle, notice }

    subscript(screen: DesignScreen) -> Variant {
        get {
            switch screen {
            case .setup: setup
            case .pausePanel: pausePanel
            case .blockPanel: blockPanel
            case .modeIcon: modeIcon
            case .toggle: toggle
            case .notice: notice
            }
        }
        set {
            switch screen {
            case .setup: setup = newValue
            case .pausePanel: pausePanel = newValue
            case .blockPanel: blockPanel = newValue
            case .modeIcon: modeIcon = newValue
            case .toggle: toggle = newValue
            case .notice: notice = newValue
            }
        }
    }

    /// Variant B of the toggle: it clears when the owner leaves the place and at the day change.
    var toggleResets: Bool { toggle == .b }

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
