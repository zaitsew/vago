import Foundation

/// Formatting shared by the menu bar, widget and Live Activity.
public enum Readout {
    /// "😄 12m" below 75% of the limit; "😟 28/30m" from 75% on, also past the limit ("😣 41/30m").
    /// Minutes are rounded down.
    public static func short(seconds: Int, limitMinutes: Int) -> String {
        let mood = Mood(used: seconds, limitMinutes: limitMinutes)
        let minutes = max(0, seconds) / 60
        switch mood {
        case .beaming, .happy, .neutral:
            return "\(mood.emoji) \(minutes)m"
        case .worried, .upset, .wrecked:
            return "\(mood.emoji) \(minutes)/\(limitMinutes)m"
        }
    }
}
