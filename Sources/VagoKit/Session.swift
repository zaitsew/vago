import Foundation

/// A stretch of use the nightly review may ask about. The Mac appends; both apps show the top three.
public struct Session: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var start: Date
    public var seconds: Int
    public var sample: ActivitySampleRecord   // Codable twin of ActivitySample
    public var guess: Bucket
    public var reason: String

    public init(id: UUID = UUID(), start: Date, seconds: Int, sample: ActivitySampleRecord, guess: Bucket, reason: String) {
        self.id = id
        self.start = start
        self.seconds = seconds
        self.sample = sample
        self.guess = guess
        self.reason = reason
    }
}
