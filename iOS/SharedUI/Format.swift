import Foundation

/// Short spoken durations shared by the Today tab and the widgets.
enum Spoken {
    /// "3h 12m", "40m", "0m". Whole minutes, rounded down.
    static func duration(_ seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    /// Whole minutes, rounded to nearest and never 0 for a nonzero amount: "11m".
    static func minutes(_ seconds: Int) -> String {
        "\(max(1, (seconds + 30) / 60))m"
    }
}
