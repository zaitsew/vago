import Foundation

/// The colour behind the emoji.
public enum Tint: String, Sendable { case green, yellow, red }

/// How today's procrastination stands against the limit. Share = used / limit;
/// thresholds 25 / 50 / 75 / 100 / 150 %.
public enum Mood: Sendable, Equatable {
    case beaming, happy, neutral, worried, upset, wrecked

    public var emoji: String {
        switch self {
        case .beaming: "😄"
        case .happy: "🙂"
        case .neutral: "😐"
        case .worried: "😟"
        case .upset: "😣"
        case .wrecked: "😵"
        }
    }

    public var tint: Tint {
        switch self {
        case .beaming, .happy: .green
        case .neutral, .worried: .yellow
        case .upset, .wrecked: .red
        }
    }

    /// A limit of zero or less counts any use as wrecked and no use as beaming.
    public init(used seconds: Int, limitMinutes: Int) {
        let used = max(0, seconds) * 100          // percent-scaled, to compare in integers
        let limit = max(0, limitMinutes) * 60
        guard limit > 0 else {
            self = seconds <= 0 ? .beaming : .wrecked
            return
        }
        if used < limit * 25 { self = .beaming }
        else if used < limit * 50 { self = .happy }
        else if used < limit * 75 { self = .neutral }
        else if used < limit * 100 { self = .worried }
        else if used < limit * 150 { self = .upset }
        else { self = .wrecked }
    }
}
