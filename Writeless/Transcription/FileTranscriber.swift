import Foundation
import WritelessCore

/// Reads an audio file piecewise, cuts it at pauses and runs each piece
/// through the shared engine, so an hour-long recording costs a couple of
/// minutes of memory at a time and reports progress as it goes.
///
/// An actor rather than a nonisolated helper: with approachable concurrency a
/// nonisolated async function runs on its caller's actor, and the caller is
/// the main one.
actor FileTranscriber {
    enum Event: Sendable {
        /// The file opened and its length is known.
        case opened(totalSeconds: Double)
        /// The model is loaded and the first piece is going in.
        case started
        case advanced(doneSeconds: Double)
    }

    struct Output: Sendable {
        /// Whisper's text, pieces joined by a space, not yet cleaned.
        let text: String
        let speechSeconds: Double
    }

    /// Read this much at a time. Each stretch goes to WhisperKit on its own,
    /// which cuts it further at pauses and decodes the chunks concurrently.
    static let pieceSeconds: Double = 150
    /// WhisperKit's VAD chunker drops whatever follows its last cut when that
    /// is a second or less. Two seconds of silence at the end of every piece
    /// make any real remainder longer than that, so nothing audible is lost.
    static let tailPaddingSeconds: Double = 2

    private let engine: TranscriptionEngine

    init(engine: TranscriptionEngine) {
        self.engine = engine
    }

    func transcribe(
        file url: URL,
        model: WhisperModel,
        language: String?,
        onEvent: @escaping @Sendable (Event) -> Void
    ) async throws -> Output {
        let reader = try AudioFileReader(url: url)
        let name = url.lastPathComponent
        Log.files.info("Opened \(name, privacy: .public): \(Self.seconds(reader.duration), privacy: .public) s, \(reader.sourceDescription, privacy: .public)")
        onEvent(.opened(totalSeconds: reader.duration))

        try await engine.ensureReady(model)
        try Task.checkCancellation()
        onEvent(.started)

        let sampleRate = AudioFileReader.sampleRate
        let padding = [Float](repeating: 0, count: Int(Self.tailPaddingSeconds * sampleRate))
        var carry: [Float] = []
        var consumed = 0
        var parts: [String] = []
        var speechSeconds = 0.0
        var pieceNumber = 0
        var finished = false

        while !finished {
            try Task.checkCancellation()
            let fresh = try reader.read(seconds: Self.pieceSeconds - Double(carry.count) / sampleRate)
            finished = reader.isAtEnd || fresh.isEmpty

            var piece = carry + fresh
            carry = []
            if !finished {
                let cut = PauseFinder.cutIndex(samples: piece)
                carry = Array(piece[cut...])
                piece.removeSubrange(cut...)
            }
            guard !piece.isEmpty else { continue }

            pieceNumber += 1
            let startedAt = Date()
            let gate = SpeechGate.analyze(samples: piece)
            if gate.hasSpeech {
                let samples = Array(piece[gate.range]) + padding
                let text = try await engine.transcribe(samples: samples, model: model, language: language)
                try Task.checkCancellation()
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { parts.append(trimmed) }
                speechSeconds += gate.speechSeconds
            }
            consumed += piece.count

            let elapsed = Int(Date().timeIntervalSince(startedAt) * 1000)
            Log.files.info("Piece \(pieceNumber, privacy: .public): \(Self.seconds(Double(piece.count) / sampleRate), privacy: .public) s, \(Self.seconds(gate.speechSeconds), privacy: .public) s of speech, \(elapsed, privacy: .public) ms")
            onEvent(.advanced(doneSeconds: Double(consumed) / sampleRate))
        }

        return Output(text: parts.joined(separator: " "), speechSeconds: speechSeconds)
    }

    private static func seconds(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
