import Foundation

/// A stretch of use the nightly review may ask about. The Mac appends; both apps show the top three.
public struct Session: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var start: Date
    public var seconds: Int
    public var observation: ObservationRecord   // Codable twin of Observation
    public var guess: Bucket
    public var reason: String

    public init(id: UUID = UUID(), start: Date, seconds: Int, observation: ObservationRecord, guess: Bucket, reason: String) {
        self.id = id
        self.start = start
        self.seconds = seconds
        self.observation = observation
        self.guess = guess
        self.reason = reason
    }
}
