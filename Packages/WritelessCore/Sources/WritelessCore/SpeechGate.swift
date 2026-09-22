import Foundation

/// Whether a recording contains speech at all, and where it starts and ends.
///
/// WhisperKit 1.1.0 never fills in `noSpeechProb` (it is hardcoded to 0), so
/// `noSpeechThreshold` can't protect us from hallucinated text on silence.
public struct SpeechGateResult: Sendable, Equatable {
    public let hasSpeech: Bool
    /// Sample range to transcribe, padded a little around the speech.
    public let range: Range<Int>
    public let speechSeconds: Double

    public init(hasSpeech: Bool, range: Range<Int>, speechSeconds: Double) {
        self.hasSpeech = hasSpeech
        self.range = range
        self.speechSeconds = speechSeconds
    }
}

public enum SpeechGate {
    public static func analyze(
        samples: [Float],
        sampleRate: Int = 16_000,
        frameSeconds: Double = 0.1,
        threshold: Float = 0.01,
        minimumActiveFrames: Int = 2,
        leadingPadSeconds: Double = 0.3,
        trailingPadSeconds: Double = 0.5
    ) -> SpeechGateResult {
        let frameLength = max(1, Int(Double(sampleRate) * frameSeconds))
        guard samples.count >= frameLength else {
            return SpeechGateResult(hasSpeech: false, range: 0..<samples.count, speechSeconds: 0)
        }

        var firstActive: Int?
        var lastActive: Int?
        var activeFrames = 0
        var longestRun = 0
        var currentRun = 0

        var frameIndex = 0
        while (frameIndex + 1) * frameLength <= samples.count {
            let start = frameIndex * frameLength
            let frame = samples[start..<(start + frameLength)]
            if rootMeanSquare(frame) > threshold {
                activeFrames += 1
                currentRun += 1
                longestRun = max(longestRun, currentRun)
                if firstActive == nil { firstActive = frameIndex }
                lastActive = frameIndex
            } else {
                currentRun = 0
            }
            frameIndex += 1
        }

        guard longestRun >= minimumActiveFrames, let firstActive, let lastActive else {
            return SpeechGateResult(hasSpeech: false, range: 0..<samples.count, speechSeconds: 0)
        }

        let leadingPad = Int(Double(sampleRate) * leadingPadSeconds)
        let trailingPad = Int(Double(sampleRate) * trailingPadSeconds)
        let lower = max(0, firstActive * frameLength - leadingPad)
        let upper = min(samples.count, (lastActive + 1) * frameLength + trailingPad)

        return SpeechGateResult(
            hasSpeech: true,
            range: lower..<max(lower, upper),
            speechSeconds: Double(activeFrames) * frameSeconds
        )
    }

    public static func rootMeanSquare(_ samples: some Collection<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return (sum / Float(samples.count)).squareRoot()
    }
}
