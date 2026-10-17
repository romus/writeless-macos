import Foundation

/// Where to cut a long recording so that no word is split between two pieces.
///
/// The file transcriber reads a couple of minutes at a time and hands each
/// stretch to Whisper on its own. A cut at a fixed length would land in the
/// middle of a word; this one lands in the middle of the longest pause near
/// the end of the stretch instead, and whatever follows carries over.
public enum PauseFinder {
    /// The sample index to cut at: the middle of the longest run of quiet
    /// frames (RMS under `threshold`, as `SpeechGate` measures it) within the
    /// trailing `searchSeconds`. `samples.count` when the buffer is no longer
    /// than the window or nothing in it is quiet, so a short final stretch is
    /// never cut.
    public static func cutIndex(
        samples: [Float],
        sampleRate: Int = 16_000,
        searchSeconds: Double = 30,
        frameSeconds: Double = 0.1,
        threshold: Float = 0.01
    ) -> Int {
        let frameLength = max(1, Int(Double(sampleRate) * frameSeconds))
        let searchFrames = max(1, Int(searchSeconds / frameSeconds))
        let totalFrames = samples.count / frameLength
        guard totalFrames > searchFrames else { return samples.count }

        var bestStart = 0
        var bestLength = 0
        var runStart = 0
        var runLength = 0
        for frame in (totalFrames - searchFrames)..<totalFrames {
            let start = frame * frameLength
            let isQuiet = SpeechGate.rootMeanSquare(samples[start..<(start + frameLength)]) < threshold
            guard isQuiet else {
                runLength = 0
                continue
            }
            if runLength == 0 { runStart = frame }
            runLength += 1
            // A tie goes to the later pause: bigger pieces, fewer seams.
            if runLength >= bestLength {
                bestStart = runStart
                bestLength = runLength
            }
        }
        guard bestLength > 0 else { return samples.count }

        let cut = (bestStart + bestLength / 2) * frameLength
        return max(1, min(cut, samples.count))
    }
}
