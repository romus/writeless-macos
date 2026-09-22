import Foundation
import Testing

@testable import WritelessCore

private let sampleRate = 16_000

private func silence(seconds: Double) -> [Float] {
    Array(repeating: 0, count: Int(Double(sampleRate) * seconds))
}

private func noise(seconds: Double, amplitude: Float) -> [Float] {
    var generator = SystemRandomNumberGenerator()
    return (0..<Int(Double(sampleRate) * seconds)).map { _ in
        Float.random(in: -amplitude...amplitude, using: &generator)
    }
}

private func tone(seconds: Double, amplitude: Float, frequency: Double = 220) -> [Float] {
    (0..<Int(Double(sampleRate) * seconds)).map { index in
        amplitude * Float(sin(2 * Double.pi * frequency * Double(index) / Double(sampleRate)))
    }
}

@Suite("Speech gate")
struct SpeechGateTests {
    @Test("Silence has no speech")
    func silenceIsRejected() {
        let result = SpeechGate.analyze(samples: silence(seconds: 5))
        #expect(!result.hasSpeech)
        #expect(result.speechSeconds == 0)
    }

    @Test("Quiet room noise has no speech")
    func quietNoiseIsRejected() {
        // Roughly -66 dBFS RMS, well under the 0.01 threshold.
        let result = SpeechGate.analyze(samples: noise(seconds: 3, amplitude: 0.0008))
        #expect(!result.hasSpeech)
    }

    @Test("A single 100 ms blip is not speech")
    func blipIsRejected() {
        let samples = silence(seconds: 1) + tone(seconds: 0.1, amplitude: 0.3) + silence(seconds: 1)
        #expect(!SpeechGate.analyze(samples: samples).hasSpeech)
    }

    @Test("A 600 ms utterance is speech and gets trimmed with padding")
    func speechIsDetected() {
        let leadIn = 2.0
        let samples = silence(seconds: leadIn) + tone(seconds: 0.6, amplitude: 0.2) + silence(seconds: 2)
        let result = SpeechGate.analyze(samples: samples)

        #expect(result.hasSpeech)
        #expect(result.speechSeconds >= 0.5)
        // Starts 0.3 s before the tone and ends 0.5 s after it.
        #expect(result.range.lowerBound == Int(Double(sampleRate) * (leadIn - 0.3)))
        #expect(result.range.upperBound == Int(Double(sampleRate) * (leadIn + 0.6 + 0.5)))
        #expect(result.range.upperBound <= samples.count)
    }

    @Test("Padding is clamped to the recording")
    func paddingIsClamped() {
        let samples = tone(seconds: 0.6, amplitude: 0.2)
        let result = SpeechGate.analyze(samples: samples)
        #expect(result.hasSpeech)
        #expect(result.range.lowerBound == 0)
        #expect(result.range.upperBound == samples.count)
    }

    @Test("A recording shorter than one frame is not speech")
    func tinyRecording() {
        let result = SpeechGate.analyze(samples: tone(seconds: 0.05, amplitude: 0.5))
        #expect(!result.hasSpeech)
    }
}

@Suite("Level meter")
struct LevelMeterTests {
    @Test("Silence is 0, loud audio is 1, and the scale rises in between")
    func normalization() {
        #expect(LevelMeter.normalized(rms: 0) == 0)
        #expect(LevelMeter.normalized(rms: 1) == 1)
        let quiet = LevelMeter.normalized(rms: 0.01)
        let loud = LevelMeter.normalized(rms: 0.1)
        #expect(quiet > 0 && quiet < loud && loud < 1)
    }

    @Test("History keeps its length and drops the oldest value")
    func history() {
        var history = LevelHistory(capacity: 3)
        #expect(history.values == [0, 0, 0])

        history.push(0.5)
        history.push(2)   // clamped
        history.push(-1)  // clamped
        #expect(history.values == [0.5, 1, 0])

        history.push(0.25)
        #expect(history.values == [1, 0, 0.25])
        #expect(history.values.count == history.capacity)

        history.reset()
        #expect(history.values == [0, 0, 0])
    }
}

@Suite("Transcript cleaner")
struct TranscriptCleanerTests {
    @Test("Whitespace is collapsed and trimmed")
    func whitespace() {
        #expect(TranscriptCleaner.clean("  Hello   world.\n", speechSeconds: 5) == "Hello world.")
        #expect(TranscriptCleaner.clean("   ", speechSeconds: 5).isEmpty)
    }

    @Test("Pure annotations are dropped")
    func annotations() {
        #expect(TranscriptCleaner.clean("[BLANK_AUDIO]", speechSeconds: 5).isEmpty)
        #expect(TranscriptCleaner.clean("(soft music)", speechSeconds: 5).isEmpty)
        #expect(TranscriptCleaner.clean("[music] and then he spoke", speechSeconds: 5) == "[music] and then he spoke")
        // VAD chunks are joined with a space, so silence can come back as more
        // than one annotation.
        #expect(TranscriptCleaner.clean("[BLANK_AUDIO] [BLANK_AUDIO]", speechSeconds: 5).isEmpty)
        #expect(TranscriptCleaner.clean("(music) [BLANK_AUDIO]", speechSeconds: 5).isEmpty)
    }

    @Test("Known hallucinations are dropped only after very short speech")
    func hallucinations() {
        #expect(TranscriptCleaner.clean("Thank you.", speechSeconds: 0.7).isEmpty)
        #expect(TranscriptCleaner.clean("Субтитры сделал DimaTorzok", speechSeconds: 1.0).isEmpty)
        #expect(TranscriptCleaner.clean("Продолжение следует...", speechSeconds: 1.0).isEmpty)
        // The same words after real speech are kept: the user may have said them.
        #expect(TranscriptCleaner.clean("Thank you.", speechSeconds: 4) == "Thank you.")
        #expect(TranscriptCleaner.clean("Thank you for the coffee.", speechSeconds: 0.7) == "Thank you for the coffee.")
    }
}
