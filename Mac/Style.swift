import AppKit
import SwiftUI
import VagoKit

/// Colours shared by the popover, the Day window and the day strip. Light and dark mode both.
enum Palette {
    static let work = Color.green
    static let waste = Color.orange
    static let neutral = AnyShapeStyle(HierarchicalShapeStyle.secondary.opacity(0.35))
    /// An empty hour cell.
    static let empty = AnyShapeStyle(HierarchicalShapeStyle.quaternary.opacity(0.6))

    static func style(for bucket: Bucket) -> AnyShapeStyle {
        switch bucket {
        case .productive: AnyShapeStyle(work)
        case .procrastination, .ambiguous: AnyShapeStyle(waste)
        case .neutral: neutral
        }
    }

    /// A mood or share tint. Yellow is darkened in light mode, so a large number stays legible.
    static func color(_ tint: Tint?) -> Color {
        switch tint {
        case .green: .green
        case .yellow: yellow
        case .red: .red
        case nil: .secondary
        }
    }

    private static let yellow = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .systemYellow
            : NSColor(srgbRed: 0.78, green: 0.56, blue: 0.0, alpha: 1)
    })
}

/// A thin rounded progress bar that keeps its colour in every window state.
struct ThinBar: View {
    var fraction: Double
    var color: Color
    var height: CGFloat = 5

    var body: some View {
        Capsule()
            .fill(.quaternary)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(color)
                        .frame(width: max(fraction > 0 ? height : 0, geo.size.width * min(1, max(0, fraction))))
                }
            }
            .frame(height: height)
            .accessibilityValue("\(Int((min(1, max(0, fraction)) * 100).rounded())) percent")
    }
}

/// Number formatting for every screen.
enum Format {
    /// "45s" under a minute, then "12m", "1h 05m".
    static func duration(_ seconds: Int) -> String {
        let s = max(0, seconds)
        if s < 60 { return "\(s)s" }
        return minutes(s)
    }

    /// "0m", "12m", "3h 12m": whole minutes, rounded down.
    static func minutes(_ seconds: Int) -> String {
        let m = max(0, seconds) / 60
        return m < 60 ? "\(m)m" : String(format: "%dh %02dm", m / 60, m % 60)
    }

    /// "3h 12m work · 40m neutral · 41m waste".
    static func split(_ share: ProductiveShare) -> String {
        "\(minutes(share.productive)) work · \(minutes(share.neutral)) neutral · \(minutes(share.procrastination)) waste"
    }

    /// The hero caption: the split, or "12 min so far" while the share is hidden.
    static func caption(_ share: ProductiveShare) -> String {
        share.percent == nil ? "\(share.active / 60) min so far" : split(share)
    }

    /// The classifier prefixes guesses with "unsure: " or "held: "; the screen marks those itself.
    static func reason(_ text: String) -> String {
        for prefix in ["unsure: ", "held: "] where text.hasPrefix(prefix) {
            return String(text.dropFirst(prefix.count))
        }
        return text
    }

    /// "Sunday, 8 November" for a day id.
    static func dayTitle(_ day: DayKey) -> String {
        let parse = DateFormatter()
        parse.locale = Locale(identifier: "en_US_POSIX")
        parse.dateFormat = "yyyy-MM-dd"
        guard let date = parse.date(from: day.id) else { return day.id }
        let show = DateFormatter()
        show.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return show.string(from: date)
    }
}
