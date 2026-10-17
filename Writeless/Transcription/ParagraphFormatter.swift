import Foundation
import WritelessCore

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Asks the on-device Apple Intelligence model where the paragraphs of a
/// transcript begin. That is all it is allowed to do: the model sees a
/// numbered list of sentences and answers with numbers, and `ParagraphLayout`
/// rebuilds the text from the original sentences. Asked to return the text
/// itself it swapped synonyms in, so it never gets the chance.
///
/// `nonisolated`, like `Log`: this runs off the main actor, and the
/// `@Generable` macro's generated initialiser has to satisfy a nonisolated
/// protocol requirement, which it cannot do from a MainActor-isolated type.
nonisolated enum ParagraphFormatter {
    /// Per window: a dictation has one or two, an hour-long file dozens, and
    /// each gets its own budget. A window that overruns it sends the flat
    /// text out.
    static let timeout: Duration = .seconds(10)

    /// Read fresh every time: the user can flip Apple Intelligence in System
    /// Settings while we run, and the model takes a while to arrive after that.
    static var availability: ParagraphsAvailability {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .appleIntelligenceNotEnabled: return .turnedOff
                case .modelNotReady: return .downloading
                case .deviceNotEligible: return .unsupported
                @unknown default: return .unsupported
                }
            }
        }
        #endif
        return .unsupported
    }

    /// 1-based numbers of the sentences that begin a paragraph, or `nil` when
    /// the model could not be asked or did not answer in time. The caller then
    /// keeps the flat transcript, which is always the right fallback.
    static func paragraphStarts(for sentences: [String]) async -> [Int]? {
        #if canImport(FoundationModels)
        guard #available(macOS 26, *) else { return nil }
        let startedAt = Date()
        do {
            let starts = try await requestStarts(for: sentences)
            let elapsed = Int(Date().timeIntervalSince(startedAt) * 1000)
            Log.structure.info("Paragraphs: \(sentences.count, privacy: .public) sentences → starts \(String(describing: starts), privacy: .public) in \(elapsed, privacy: .public) ms")
            return starts
        } catch {
            let elapsed = Int(Date().timeIntervalSince(startedAt) * 1000)
            Log.structure.error("Paragraphs skipped after \(elapsed, privacy: .public) ms: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        #else
        return nil
        #endif
    }

    #if canImport(FoundationModels)
    private static let instructions = """
        You are given a numbered list of consecutive sentences from a dictated monologue. \
        Split it into paragraphs. Start a new paragraph whenever the speaker moves on to a new \
        topic or a new item, including the sentence that announces the transition (for example \
        "next", "one more thing", "finally", "now about ..."). Never split a single topic. \
        Return the numbers of the sentences that begin each paragraph. Sentence 1 always begins \
        a paragraph.
        """

    @available(macOS 26, *)
    @Generable
    nonisolated struct Paragraphing {
        @Guide(description: "1-based numbers of the sentences that begin a new paragraph, in ascending order. Always includes 1.")
        var paragraphStarts: [Int]
    }

    /// One request per window; the model's judgement collapses on long lists.
    /// Each window starts a paragraph of its own, which is why the windows are
    /// cut to even sizes rather than one long one and a stub.
    @available(macOS 26, *)
    private static func requestStarts(for sentences: [String]) async throws -> [Int] {
        var starts: [Int] = []
        for window in ParagraphWindows.make(count: sentences.count) {
            let numbered = sentences[window].enumerated()
                .map { "\($0.offset + 1). \($0.element)" }
                .joined(separator: "\n")
            let windowStarts: [Int] = try await withTimeout(timeout) {
                let session = LanguageModelSession(model: .default, instructions: instructions)
                let response = try await session.respond(
                    to: numbered,
                    generating: Paragraphing.self,
                    options: GenerationOptions(temperature: 0)
                )
                return response.content.paragraphStarts
            }
            starts += windowStarts.map { $0 + window.lowerBound }
            try Task.checkCancellation()
        }
        return starts
    }
    #endif

    private struct TimedOut: Error, LocalizedError {
        var errorDescription: String? { "the model did not answer in time" }
    }

    private static func withTimeout<T: Sendable>(
        _ limit: Duration,
        _ body: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await body() }
            group.addTask {
                try await Task.sleep(for: limit)
                throw TimedOut()
            }
            guard let first = try await group.next() else { throw TimedOut() }
            group.cancelAll()
            return first
        }
    }
}
