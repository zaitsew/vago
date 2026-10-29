import Foundation
import FoundationModels
import VagoKit

/// The AI verdict for ambiguous use (docs/PRODUCT.md, signal 3).
///
/// POLICY section 1, model routing: this runs on-device on purpose. Window titles and URLs are
/// private, the call happens every few seconds (once per site and title per day, then cached by
/// `Classifier`), and Apple's on-device model is free. Nothing leaves the Mac.
struct FoundationModelsJudge: Judge {
    /// One structured answer from the model.
    @Generable
    struct Output {
        @Generable
        enum Answer: String {
            case productive
            case procrastination
            case neutral
        }

        @Guide(description: "productive if this use serves the owner's goals, procrastination if it is scrolling, video, news or games, neutral if it is a necessary chore")
        var bucket: Answer

        @Guide(description: "How sure you are, from 0 (guess) to 1 (certain)", .range(0.0...1.0))
        var confidence: Double

        @Guide(description: "One short sentence the owner can read, at most 12 words")
        var reason: String
    }

    /// True when the on-device model can answer right now (the download may still be running).
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// A judge when the model is available, otherwise `nil`: the classifier then runs without one.
    static func makeIfAvailable() -> FoundationModelsJudge? {
        isAvailable ? FoundationModelsJudge() : nil
    }

    func judge(_ o: ActivitySample, goals: String) async -> Verdict? {
        guard Self.isAvailable else { return nil }
        let instructions = """
        You decide whether one moment of computer use is work or procrastination for its owner.
        The owner's goals: \(goals)
        Social media, video and chat apps can be work (a client message, a talk about the owner's field) \
        or waste (a feed, reels, shorts, memes, news). Judge from the page title and address. \
        When the title and address do not say, give a low confidence instead of guessing.
        """
        let session = LanguageModelSession(instructions: instructions)
        let prompt = """
        App: \(o.appName)
        Site: \(o.host ?? "none")\(o.host == nil ? "" : o.path)
        Window title: \(Self.clip(o.windowTitle ?? "none", 200))
        """
        do {
            let response = try await session.respond(to: prompt, generating: Output.self)
            let out = response.content
            return Verdict(
                bucket: Bucket(rawValue: out.bucket.rawValue) ?? .procrastination,
                confidence: min(1, max(0, out.confidence)),
                reason: Self.clip(out.reason, 140)
            )
        } catch {
            // Guardrail refusal, context overflow, model busy: no verdict, so the session goes to review.
            return nil
        }
    }

    private static func clip(_ text: String, _ limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit)) + "…"
    }
}
