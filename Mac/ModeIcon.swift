import AppKit
import SwiftUI
import VagoKit

/// The mode pill in the menu bar, by word and colour: WORK green, WASTE red, a moon in grey when
/// nothing is counted. A tinted capsule (18% of the mode colour, the label in the full colour)
/// reads as state and leaves the share beside it its own tint.
struct ModeBadge: View {
    var mode: Mode

    static func word(_ mode: Mode) -> String? {
        switch mode {
        case .work: String(localized: "WORK", comment: "Menu-bar pill while the place in front counts as work. Keep it short and upper case.")
        case .procrastination: String(localized: "WASTE", comment: "Menu-bar pill while the place in front counts as procrastination. Keep it short and upper case.")
        case .neutral: nil
        }
    }

    static func name(_ mode: Mode) -> String {
        switch mode {
        case .work: String(localized: "Work", comment: "Name of the work mode, for the tooltip and accessibility.")
        case .procrastination: String(localized: "Procrastination", comment: "Name of the procrastination mode, for the tooltip and accessibility.")
        case .neutral: String(localized: "Neutral", comment: "Name of the neutral mode, for the tooltip and accessibility.")
        }
    }

    var body: some View {
        let color = Palette.modeColor(mode)
        Group {
            if let word = Self.word(mode) {
                Text(verbatim: word)
                    .font(.system(size: 9.5, weight: .heavy, design: .rounded))
            } else {
                Image(systemName: "moon.fill")
                    .font(.system(size: 9, weight: .bold))
            }
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .frame(minWidth: 26, minHeight: 16)
        .background(Capsule().fill(color.opacity(0.18)))
        .accessibilityLabel(Self.name(mode))
    }
}

/// The pill as a bitmap for the status item. A coloured, non-template image keeps its colours.
@MainActor
enum ModeBadgeImage {
    static func make(mode: Mode, scale: CGFloat) -> NSImage? {
        let renderer = ImageRenderer(content: ModeBadge(mode: mode).padding(.trailing, 5))
        renderer.scale = scale
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = false
        return image
    }
}

/// The popover's first row: the mode pill, the place in front, and one switch. Plain data in and a
/// closure out, so a screenshot renders it with sample data.
struct ModeRowContent: View {
    var label: String?
    var mode: Mode
    var isWork: Bool
    var onToggle: @MainActor () -> Void

    private var caption: String {
        guard label != nil else { return String(localized: "Nothing in front yet", comment: "Mode row caption before any place was seen.") }
        let counts = isWork
            ? String(localized: "Counts as work.", comment: "Mode row caption: the place in front counts as work.")
            : (mode == .neutral
                ? String(localized: "Counts as neutral.", comment: "Mode row caption: the place in front counts as neutral.")
                : String(localized: "Counts as waste.", comment: "Mode row caption: the place in front counts as waste."))
        let rest = String(localized: "Resets when you leave it or the day ends.", comment: "Mode row caption: how long a flip of the switch lasts.")
        return "\(counts) \(rest)"
    }

    var body: some View {
        HStack(spacing: 10) {
            ModeBadge(mode: mode)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: label ?? "—").font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                Text(verbatim: caption).font(.caption).foregroundStyle(.secondary).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            WorkSwitch(isOn: isWork, enabled: label != nil, action: onToggle)
        }
        .accessibilityElement(children: .contain)
    }
}

/// An explicit capsule switch: green when the place counts as work, grey when it does not. A native
/// `Toggle` switch renders grey in a window that is not key, so on and off looked alike.
struct WorkSwitch: View {
    var isOn: Bool
    var enabled = true
    var action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            Capsule()
                .fill(isOn ? Palette.work : Color.gray.opacity(0.35))
                .frame(width: 36, height: 21)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle().fill(.white).shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                        .frame(width: 17, height: 17).padding(2)
                }
                .animation(.easeOut(duration: 0.12), value: isOn)
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.4)
        .disabled(!enabled)
        .accessibilityLabel(Text("Work", comment: "Accessibility label of the work switch."))
        .accessibilityValue(isOn ? Text("On", comment: "Switch state.") : Text("Off", comment: "Switch state."))
        .accessibilityAddTraits(.isToggle)
    }
}

struct ModeRow: View {
    let model: AppModel

    var body: some View {
        let target = model.toggleTarget
        ModeRowContent(
            label: target.map { model.displayName($0) }, mode: model.currentMode, isWork: model.toggleIsWork
        ) { model.toggleCurrent() }
    }
}
