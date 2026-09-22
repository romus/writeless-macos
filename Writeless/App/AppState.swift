import Foundation
import Observation
import WritelessCore

/// Everything the menu, the pill and Settings render. Owned and mutated by
/// `AppCoordinator`; views only read it.
@Observable
final class AppState {
    var phase: Phase = .idle
    /// Set when audio actually starts flowing, so the timer doesn't count the
    /// engine's start-up (which can take a second or two on Bluetooth).
    var recordingStartedAt: Date?
    var elapsedSeconds: Double = 0
    var levels = LevelHistory(capacity: 13)

    var modelStatus: ModelStatus = .missing
    /// Bytes under the model download base. `nil` until Settings asks for it:
    /// nobody pays for the walk unless the Advanced section is open.
    var modelCacheBytes: Int64?
    var microphone: Permissions.MicrophoneAccess = .undetermined
    /// Every microphone the system is offering, refreshed as they come and go.
    var inputDevices: [InputDevice] = []
    /// 0...1, for the meter in the Settings microphone row.
    var inputLevel: Float = 0
    var hotkeyStatus: HotkeyStatus = .active
    var shortcut: Shortcut = .default

    /// Short message shown in the pill, cleared by the coordinator.
    var notice: Notice?

    var isRecording: Bool { phase == .starting || phase == .recording }
    var isAudioFlowing: Bool { phase == .recording }

    /// The coloured dot shared by the menu bar icon, the menu header and the pill.
    var indicator: StatusIndicator {
        .current(
            phase: phase,
            modelStatus: modelStatus,
            microphoneDenied: microphone == .denied,
            hotkeyStatus: hotkeyStatus
        )
    }

    /// Nothing stops recording: the pill only shows up when there is something
    /// to show.
    var isPillVisible: Bool { isRecording || phase == .transcribing || notice != nil }
}
