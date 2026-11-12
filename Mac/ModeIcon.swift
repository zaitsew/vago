import AppKit
import SwiftUI
import VagoKit

/// The mode badge in the menu bar, by image and colour: work green, procrastination red, neutral
/// grey. Variant A is a symbol in a coloured circle, variant B a coloured capsule with a word.
struct ModeBadge: View {
    var mode: Mode
    var variant: Variant

    static func symbol(_ mode: Mode) -> String {
        switch mode {
        case .work: "briefcase.fill"
        case .procrastination: "flame.fill"
        case .neutral: "moon.fill"
        }
    }

    static func word(_ mode: Mode) -> String {
        switch mode {
        case .work: "WORK"
        case .procrastination: "WASTE"
        case .neutral: "—"
        }
    }

    static func name(_ mode: Mode) -> String {
        switch mode {
        case .work: "Work"
        case .procrastination: "Procrastination"
        case .neutral: "Neutral"
        }
    }

    var body: some View {
        let color = Palette.modeColor(mode)
        Group {
            if variant == .a {
                ZStack {
                    Circle().fill(color)
                    Image(systemName: Self.symbol(mode))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 18, height: 18)
            } else {
                Text(Self.word(mode))
                    .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .frame(minWidth: 26, minHeight: 16)
                    .background(Capsule().fill(color))
            }
        }
        .accessibilityLabel(Self.name(mode))
    }
}

/// The badge as a bitmap for the status item. A coloured, non-template image keeps its colours.
@MainActor
enum ModeBadgeImage {
    static func make(mode: Mode, variant: Variant, scale: CGFloat) -> NSImage? {
        let renderer = ImageRenderer(content: ModeBadge(mode: mode, variant: variant).padding(.trailing, 5))
        renderer.scale = scale
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = false
        return image
    }
}

/// The popover's first row: the mode badge, the place in front, and one switch. Plain data in and a
/// closure out, so a screenshot renders it with sample data.
struct ModeRowContent: View {
    var label: String?
    var mode: Mode
    var isWork: Bool
    var iconVariant: Variant
    var toggleVariant: Variant
    var onToggle: @MainActor () -> Void

    private var caption: String {
        guard label != nil else { return "Nothing in front yet" }
        let counts = isWork ? "Counts as work." : (mode == .neutral ? "Counts as neutral." : "Counts as waste.")
        let rest = toggleVariant == .a
            ? "Stays until you flip it back."
            : "Resets when you leave it or the day ends."
        return "\(counts) \(rest)"
    }

    var body: some View {
        HStack(spacing: 10) {
            ModeBadge(mode: mode, variant: iconVariant)
            VStack(alignment: .leading, spacing: 1) {
                Text(label ?? "—").font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Toggle("Work", isOn: Binding(get: { isWork }, set: { _ in onToggle() }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .fixedSize()
                .disabled(label == nil)
        }
        .accessibilityElement(children: .contain)
    }
}

struct ModeRow: View {
    let model: AppModel

    var body: some View {
        let target = model.toggleTarget
        ModeRowContent(
            label: target.map { model.displayName($0) }, mode: model.currentMode, isWork: model.toggleIsWork,
            iconVariant: model.variants.modeIcon, toggleVariant: model.variants.toggle
        ) { model.toggleCurrent() }
    }
}
