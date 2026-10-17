import AVFoundation
import Foundation

/// Reads any file AVAudioFile can open (m4a, mp3, wav, …) as 16 kHz mono
/// Float32, a stretch at a time, so an hour of audio never sits in memory at
/// once.
///
/// `nonisolated` because the target defaults to MainActor isolation and this
/// is blocking I/O. Not Sendable: it is created and used inside
/// `FileTranscriber` only.
nonisolated final class AudioFileReader {
    enum ReadError: LocalizedError {
        case cannotOpen(String)
        case cannotConvert
        case decodeFailed(String)

        var errorDescription: String? {
            switch self {
            case .cannotOpen(let reason): "The audio file could not be opened: \(reason)"
            case .cannotConvert: "The audio format is not supported."
            case .decodeFailed(let reason): "The audio file could not be decoded: \(reason)"
            }
        }
    }

    static let sampleRate: Double = 16_000

    let url: URL
    /// Seconds of audio in the file.
    let duration: Double
    /// "44100 Hz, 2 ch" — the decoded format, for the log.
    let sourceDescription: String
    /// True once the last sample has been handed out.
    private(set) var isAtEnd = false

    private let file: AVAudioFile
    private let target: AVAudioFormat
    /// `nil` when the file already is 16 kHz mono and can be read straight.
    private let converter: AVAudioConverter?
    private let input: AVAudioPCMBuffer
    /// A read that failed inside the converter's input block, which cannot throw.
    private var inputError: Error?

    init(url: URL) throws {
        self.url = url
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            throw ReadError.cannotOpen(error.localizedDescription)
        }

        // `processingFormat` is the decoded PCM; `fileFormat` is the codec on
        // disk and only good for describing the file.
        let source = file.processingFormat
        guard
            source.sampleRate > 0, source.channelCount > 0,
            let target = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate, channels: 1, interleaved: false
            ),
            let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 32_768)
        else { throw ReadError.cannotConvert }

        if source.sampleRate == target.sampleRate, source.channelCount == 1 {
            converter = nil
        } else {
            guard let converter = AVAudioConverter(from: source, to: target) else {
                throw ReadError.cannotConvert
            }
            converter.downmix = true
            self.converter = converter
        }

        self.file = file
        self.target = target
        self.input = input
        duration = Double(file.length) / source.sampleRate
        sourceDescription = "\(Int(source.sampleRate)) Hz, \(source.channelCount) ch"
    }

    /// Up to `seconds` of audio, fewer at the end of the file, `[]` once it is
    /// spent.
    func read(seconds: Double) throws -> [Float] {
        guard seconds > 0, !isAtEnd else { return [] }
        let frames = AVAudioFrameCount((seconds * Self.sampleRate).rounded(.up))
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: frames + 1024) else {
            throw ReadError.cannotConvert
        }

        if let converter {
            try convert(into: output, with: converter)
        } else {
            do {
                try file.read(into: output, frameCount: frames)
            } catch {
                throw ReadError.decodeFailed(error.localizedDescription)
            }
            if file.framePosition >= file.length { isAtEnd = true }
        }

        guard output.frameLength > 0, let channel = output.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }

    private func convert(into output: AVAudioPCMBuffer, with converter: AVAudioConverter) throws {
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { [self] count, inputStatus in
            // Unlike the microphone tap, a file does end, and `.endOfStream`
            // is what makes the converter flush the resampler's tail.
            guard file.framePosition < file.length else {
                inputStatus.pointee = .endOfStream
                return nil
            }
            do {
                try file.read(into: input, frameCount: min(count, input.frameCapacity))
            } catch {
                inputError = error
                inputStatus.pointee = .endOfStream
                return nil
            }
            guard input.frameLength > 0 else {
                inputStatus.pointee = .endOfStream
                return nil
            }
            inputStatus.pointee = .haveData
            return input
        }

        if let inputError {
            self.inputError = nil
            throw ReadError.decodeFailed(inputError.localizedDescription)
        }
        if status == .error {
            throw ReadError.decodeFailed(conversionError?.localizedDescription ?? "conversion failed")
        }
        if status == .endOfStream { isAtEnd = true }
    }
}
