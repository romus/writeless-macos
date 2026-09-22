import Foundation

/// A short message the pill shows for about two seconds.
public enum Notice: Sendable, Equatable {
    case noSpeechDetected
    case microphoneUnavailable
    /// The good outcome: the clipboard is where every transcript ends up.
    case copiedToClipboard
    case modelDownloading(percent: Int)
    case modelPreparing
    case modelUnavailable
    case transcriptionFailed

    public var text: String {
        switch self {
        case .noSpeechDetected: "No speech detected"
        case .microphoneUnavailable: "Microphone unavailable"
        case .copiedToClipboard: "Copied — press ⌘V"
        case .modelDownloading(let percent): "Downloading model… \(percent)%"
        case .modelPreparing: "Preparing model…"
        case .modelUnavailable: "Model unavailable"
        case .transcriptionFailed: "Transcription failed"
        }
    }

    public var symbolName: String {
        switch self {
        case .noSpeechDetected: "waveform.slash"
        case .microphoneUnavailable: "mic.slash"
        case .copiedToClipboard: "doc.on.clipboard"
        case .modelDownloading: "arrow.down.circle"
        case .modelPreparing: "hourglass"
        case .modelUnavailable: "exclamationmark.triangle"
        case .transcriptionFailed: "exclamationmark.triangle"
        }
    }
}
