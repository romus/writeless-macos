import AppKit
import WritelessCore

extension StatusIndicator {
    /// The one place the dot's colour is decided. `nil` means no dot.
    ///
    /// The system colours are the design's `#30D158`, `#FF453A` and `#FF9F0A`
    /// in dark mode, and adapt on their own to a light menu bar.
    var dotColor: NSColor? {
        switch self {
        case .none: nil
        case .ready: .systemGreen
        case .recording: .systemRed
        case .transcribing: .systemOrange
        }
    }

    /// What VoiceOver reads after the app's name.
    var accessibilityDescription: String? {
        switch self {
        case .none: nil
        case .ready: "Ready"
        case .recording: "Recording"
        case .transcribing: "Transcribing"
        }
    }
}
