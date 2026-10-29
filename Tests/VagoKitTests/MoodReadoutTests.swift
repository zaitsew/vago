import Foundation
import Testing
@testable import VagoKit

@Suite("Mood")
struct MoodTests {
    // Limit 40 minutes = 2400 s, so 25% = 600 s, 50% = 1200 s, 75% = 1800 s, 100% = 2400 s, 150% = 3600 s.
    @Test(arguments: [
        (0, Mood.beaming), (599, .beaming), (600, .happy), (1199, .happy), (1200, .neutral),
        (1799, .neutral), (1800, .worried), (2399, .worried), (2400, .upset), (3599, .upset),
        (3600, .wrecked), (99_999, .wrecked),
    ])
    func boundaries(seconds: Int, expected: Mood) {
        #expect(Mood(used: seconds, limitMinutes: 40) == expected)
    }

    @Test func emojiTable() {
        #expect([Mood.beaming, .happy, .neutral, .worried, .upset, .wrecked].map(\.emoji) == ["😄", "🙂", "😐", "😟", "😣", "😵"])
    }

    @Test func tintTable() {
        #expect([Mood.beaming, .happy, .neutral, .worried, .upset, .wrecked].map(\.tint) == [.green, .green, .yellow, .yellow, .red, .red])
    }

    @Test func limitOfZeroDoesNotCrash() {
        #expect(Mood(used: 0, limitMinutes: 0) == .beaming)
        #expect(Mood(used: 1, limitMinutes: 0) == .wrecked)
    }

    @Test func negativeUseCountsAsNone() {
        #expect(Mood(used: -50, limitMinutes: 30) == .beaming)
    }
}

@Suite("Readout")
struct ReadoutTests {
    @Test func belowThreeQuartersShowsMinutesOnly() {
        #expect(Readout.short(seconds: 12 * 60, limitMinutes: 60) == "😄 12m")
        #expect(Readout.short(seconds: 12 * 60, limitMinutes: 30) == "🙂 12m")
        #expect(Readout.short(seconds: 22 * 60, limitMinutes: 30) == "😐 22m")
    }

    @Test func fromThreeQuartersShowsTheLimit() {
        #expect(Readout.short(seconds: 22 * 60 + 30, limitMinutes: 30) == "😟 22/30m")
        #expect(Readout.short(seconds: 28 * 60, limitMinutes: 30) == "😟 28/30m")
    }

    @Test func overTheLimit() {
        #expect(Readout.short(seconds: 41 * 60, limitMinutes: 30) == "😣 41/30m")
        #expect(Readout.short(seconds: 45 * 60, limitMinutes: 30) == "😵 45/30m")
    }

    @Test func minutesRoundDown() {
        #expect(Readout.short(seconds: 119, limitMinutes: 60) == "😄 1m")
        #expect(Readout.short(seconds: 29 * 60 + 59, limitMinutes: 30) == "😟 29/30m")
        #expect(Readout.short(seconds: 0, limitMinutes: 30) == "😄 0m")
    }
}
