import Foundation

/// Where the selected model is in its download → load → ready lifecycle.
public enum ModelStatus: Sendable, Equatable {
    /// Nothing on disk: the first launch, or straight after the cache was cleared.
    case missing
    case downloading(downloaded: Int64, total: Int64)
    /// `firstRun` is true while Core ML specializes the model for the Neural
    /// Engine, which takes minutes once per model; later loads take seconds.
    case preparing(firstRun: Bool)
    case ready
    case failed(String)

    public var isReady: Bool { self == .ready }

    public var percent: Int? {
        guard case .downloading(let downloaded, let total) = self, total > 0 else { return nil }
        return min(100, max(0, Int(Double(downloaded) / Double(total) * 100)))
    }

    /// Subtitle under "Model" in Settings.
    public var settingsSubtitle: String {
        switch self {
        case .missing: "Not downloaded"
        case .downloading(let downloaded, let total): "Downloading… \(ByteFormat.progress(downloaded: downloaded, total: total))"
        case .preparing(let firstRun): firstRun ? "Preparing… (first run can take a few minutes)" : "Preparing…"
        case .ready: "On-device"
        case .failed: "Download failed"
        }
    }

    /// Disabled header line in the menu; `nil` when there is nothing to say.
    public var menuHeader: String? {
        switch self {
        case .missing: "Model not downloaded"
        case .downloading: "Downloading model… \(percent ?? 0)%"
        case .preparing(let firstRun): firstRun ? "Preparing model… (first run only)" : "Loading model…"
        case .ready: nil
        case .failed: "Model download failed"
        }
    }

    /// Menu bar icon while idle.
    public var idleSymbolName: String? {
        switch self {
        case .missing, .downloading: "arrow.down.circle"
        case .preparing: "hourglass"
        case .failed: "exclamationmark.triangle"
        case .ready: nil
        }
    }

    /// The one button that starts a download, when there is one to start.
    /// Nothing else in the app leaves `.missing`, so without it a cleared cache
    /// would be a dead end.
    public var downloadPrompt: DownloadPrompt? {
        switch self {
        case .missing: .download
        case .failed: .retry
        case .downloading, .preparing, .ready: nil
        }
    }

    /// Recording is refused while the model can't be used soon.
    ///
    /// A model that is merely loading from cache is fine: transcription waits a
    /// few seconds. A download or a first specialization is not, because the
    /// transcript would reach the clipboard minutes later, overwriting whatever
    /// the user has copied in the meantime.
    public var recordingBlocker: RecordingBlocker? {
        switch self {
        case .missing: .modelUnavailable
        case .downloading: .modelDownloading(percent: percent ?? 0)
        case .preparing(let firstRun): firstRun ? .modelPreparing : nil
        case .ready: nil
        case .failed: .modelUnavailable
        }
    }
}

/// Settings and the menu offer the same action under different names.
public enum DownloadPrompt: Sendable, Equatable {
    case download
    case retry

    public var settingsTitle: String {
        switch self {
        case .download: "Download"
        case .retry: "Retry"
        }
    }

    public var menuTitle: String {
        switch self {
        case .download: "Download Model"
        case .retry: "Retry Download"
        }
    }
}
