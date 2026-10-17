import Foundation

/// What the menu shows while a file is being transcribed: which file, how far
/// along it is, and a rough guess at how long is left.
public struct FileTranscriptionProgress: Sendable, Equatable {
    public var fileName: String
    /// Length of the recording; 0 until the file has been opened.
    public var totalSeconds: Double = 0
    public var doneSeconds: Double = 0
    /// When the first piece went to the model. Set only once the model is
    /// loaded, so a download is not counted against the estimate.
    public var startedAt: Date?
    /// The audio is all consumed and Apple Intelligence is placing paragraphs.
    public var isFormatting = false

    public init(fileName: String) {
        self.fileName = fileName
    }

    /// 0...1; 0 while the length is still unknown.
    public var fraction: Double {
        guard totalSeconds > 0 else { return 0 }
        return min(1, max(0, doneSeconds / totalSeconds))
    }

    public var title: String { "Transcribing \(fileName)" }

    /// "30:32 of 1:12:40"; nil until the length is known.
    public var positionLabel: String? {
        guard totalSeconds > 0 else { return nil }
        let done = ClockFormat.duration(min(doneSeconds, totalSeconds))
        return "\(done) of \(ClockFormat.duration(totalSeconds))"
    }

    /// "about 5 min left", never under a minute; "Adding paragraphs…" once the
    /// audio is done; nil until there is a finished piece to extrapolate from.
    public func remainingLabel(now: Date) -> String? {
        if isFormatting { return "Adding paragraphs…" }
        guard let startedAt, doneSeconds > 0, totalSeconds > doneSeconds else { return nil }
        let elapsed = now.timeIntervalSince(startedAt)
        guard elapsed > 0 else { return nil }

        let remaining = elapsed * (totalSeconds - doneSeconds) / doneSeconds
        let minutes = max(1, Int((remaining / 60).rounded(.up)))
        guard minutes >= 60 else { return "about \(minutes) min left" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "about \(hours) h left" : "about \(hours) h \(rest) min left"
    }
}
