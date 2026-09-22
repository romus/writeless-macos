import Foundation

/// The coloured dot the menu header and the pill share.
///
/// Green, red and orange are `NSColor.systemGreen/systemRed/systemOrange`,
/// which are exactly the design's `#30D158`, `#FF453A` and `#FF9F0A` in dark
/// mode — and give the right light-mode variants for free.
public enum StatusIndicator: Sendable, Equatable {
    /// Nothing to add: the menu bar glyph and the header text already say it
    /// (microphone denied, model downloading, shortcut taken).
    case none
    case ready
    case recording
    case transcribing

    public var pulses: Bool { self == .recording }

    public static func current(
        phase: Phase,
        modelStatus: ModelStatus,
        microphoneDenied: Bool,
        hotkeyStatus: HotkeyStatus
    ) -> StatusIndicator {
        switch phase {
        case .recording:
            return .recording
        case .transcribing:
            return .transcribing
        case .starting:
            // Grey until audio actually arrives: starting the engine can take a
            // moment, especially on Bluetooth.
            return .none
        case .idle:
            // Green promises "press the shortcut and it records". With a taken
            // shortcut or a model still downloading that is not true, and the
            // glyph and the menu header already explain what is wrong.
            guard !microphoneDenied, modelStatus.isReady, hotkeyStatus.isWorking else { return .none }
            return .ready
        }
    }

    /// Opacity of a pulsing dot: 1.0 → 0.3 → 1.0 over `cycle` seconds.
    ///
    /// A raised cosine is ease-in-out at both ends, so this needs no animation
    /// state — the pill and the menu header read the same elapsed time and stay
    /// in step. Both are already repainted at 20 Hz while recording.
    public static func pulseOpacity(at seconds: Double, cycle: Double = 1.4) -> Double {
        guard cycle > 0, seconds.isFinite else { return 1 }
        let t = seconds.truncatingRemainder(dividingBy: cycle) / cycle
        let wave = (cos(2 * .pi * t) + 1) / 2
        return 0.3 + 0.7 * wave
    }
}
