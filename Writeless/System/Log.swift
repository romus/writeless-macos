import OSLog

/// Unified-logging channels. `nonisolated` because the audio thread and the
/// transcription actor log too, and this target defaults to MainActor isolation.
nonisolated enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "dev.romus.writeless"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let model = Logger(subsystem: subsystem, category: "model")
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
}
