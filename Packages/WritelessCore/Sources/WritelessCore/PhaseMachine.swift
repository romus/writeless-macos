import Foundation

/// What the app is doing right now.
public enum Phase: Sendable, Equatable {
    case idle
    /// The audio engine is starting; no buffer has arrived yet.
    case starting
    case recording
    case transcribing
}

/// Why a recording can't start.
public enum RecordingBlocker: Sendable, Equatable {
    case microphoneDenied
    case modelDownloading(percent: Int)
    case modelPreparing
    case modelUnavailable

    /// Blocking while a model downloads or first specializes avoids a transcript
    /// that lands minutes later, on top of whatever the user has copied by then.
    public var notice: Notice {
        switch self {
        case .microphoneDenied: .microphoneUnavailable
        case .modelDownloading(let percent): .modelDownloading(percent: percent)
        case .modelPreparing: .modelPreparing
        case .modelUnavailable: .modelUnavailable
        }
    }
}

public enum PhaseEvent: Sendable, Equatable {
    /// The hotkey, or the first item in the menu.
    case toggleRequested
    case cancelRequested
    /// The first audio buffer arrived.
    case audioStarted
    /// No audio arrived in time.
    case startTimedOut
    case startFailed
    /// Buffers stopped arriving mid-recording.
    case audioStalled
    /// Device change or system sleep.
    case audioInterrupted
    case maxDurationReached
    case transcriptionFinished
}

public enum PhaseAction: Sendable, Equatable {
    case none
    case startRecording
    /// Audio is flowing: the pill's dot turns red and the timer starts.
    case markRecording
    case stopAndTranscribe
    /// Stop and throw the audio away; shows `notice` when there is one.
    case abortRecording(Notice?)
    case rejectRecording(RecordingBlocker)
    case cancelTranscription
    case finish
    /// The hotkey was pressed while transcribing.
    case beep
}

/// The whole record → transcribe lifecycle as a pure function, so every
/// transition is testable without audio hardware or a model.
public enum PhaseMachine {
    public struct Decision: Sendable, Equatable {
        public let phase: Phase
        public let action: PhaseAction

        public init(phase: Phase, action: PhaseAction) {
            self.phase = phase
            self.action = action
        }
    }

    public static func decide(
        phase: Phase,
        event: PhaseEvent,
        blocker: RecordingBlocker? = nil
    ) -> Decision {
        switch (phase, event) {
        case (.idle, .toggleRequested):
            if let blocker {
                return Decision(phase: .idle, action: .rejectRecording(blocker))
            }
            return Decision(phase: .starting, action: .startRecording)

        case (.starting, .audioStarted):
            return Decision(phase: .recording, action: .markRecording)

        case (.starting, .startTimedOut), (.starting, .startFailed):
            return Decision(phase: .idle, action: .abortRecording(.microphoneUnavailable))

        case (.starting, .toggleRequested), (.recording, .toggleRequested),
             (.recording, .audioStalled), (.recording, .audioInterrupted),
             (.recording, .maxDurationReached), (.starting, .audioInterrupted):
            return Decision(phase: .transcribing, action: .stopAndTranscribe)

        case (.starting, .cancelRequested), (.recording, .cancelRequested):
            return Decision(phase: .idle, action: .abortRecording(nil))

        case (.transcribing, .toggleRequested):
            return Decision(phase: .transcribing, action: .beep)

        case (.transcribing, .cancelRequested):
            return Decision(phase: .idle, action: .cancelTranscription)

        case (.transcribing, .transcriptionFinished):
            return Decision(phase: .idle, action: .finish)

        default:
            return Decision(phase: phase, action: .none)
        }
    }
}
