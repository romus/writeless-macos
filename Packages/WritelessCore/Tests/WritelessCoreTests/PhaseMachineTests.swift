import Foundation
import Testing

@testable import WritelessCore

@Suite("Phase machine")
struct PhaseMachineTests {
    @Test("Toggling from idle starts a recording")
    func startRecording() {
        let decision = PhaseMachine.decide(phase: .idle, event: .toggleRequested)
        #expect(decision == PhaseMachine.Decision(phase: .starting, action: .startRecording))
    }

    @Test(
        "Recording is refused while the model isn't usable",
        arguments: [
            RecordingBlocker.modelDownloading(percent: 42),
            .modelPreparing,
            .modelUnavailable,
            .microphoneDenied,
        ]
    )
    func blockedStart(blocker: RecordingBlocker) {
        let decision = PhaseMachine.decide(phase: .idle, event: .toggleRequested, blocker: blocker)
        #expect(decision.phase == .idle)
        #expect(decision.action == .rejectRecording(blocker))
        #expect(!blocker.notice.text.isEmpty)
    }

    @Test("The first audio buffer turns starting into recording")
    func firstBuffer() {
        #expect(
            PhaseMachine.decide(phase: .starting, event: .audioStarted)
                == PhaseMachine.Decision(phase: .recording, action: .markRecording)
        )
        // Later buffers change nothing.
        #expect(PhaseMachine.decide(phase: .recording, event: .audioStarted).action == .none)
    }

    @Test("A microphone that never delivers audio aborts with a notice")
    func startTimeout() {
        for event in [PhaseEvent.startTimedOut, .startFailed] {
            let decision = PhaseMachine.decide(phase: .starting, event: event)
            #expect(decision == PhaseMachine.Decision(phase: .idle, action: .abortRecording(.microphoneUnavailable)))
        }
    }

    @Test(
        "Everything that ends a recording keeps the audio and transcribes it",
        arguments: [PhaseEvent.toggleRequested, .audioStalled, .audioInterrupted, .maxDurationReached]
    )
    func stopAndTranscribe(event: PhaseEvent) {
        let decision = PhaseMachine.decide(phase: .recording, event: event)
        #expect(decision == PhaseMachine.Decision(phase: .transcribing, action: .stopAndTranscribe))
    }

    @Test("Stopping before the first buffer still goes through transcription")
    func stopWhileStarting() {
        #expect(PhaseMachine.decide(phase: .starting, event: .toggleRequested).phase == .transcribing)
    }

    @Test("Cancelling a recording throws the audio away")
    func cancelRecording() {
        #expect(
            PhaseMachine.decide(phase: .recording, event: .cancelRequested)
                == PhaseMachine.Decision(phase: .idle, action: .abortRecording(nil))
        )
    }

    @Test("While transcribing, the hotkey beeps and Cancel stops the work")
    func duringTranscription() {
        #expect(PhaseMachine.decide(phase: .transcribing, event: .toggleRequested).action == .beep)
        #expect(
            PhaseMachine.decide(phase: .transcribing, event: .cancelRequested)
                == PhaseMachine.Decision(phase: .idle, action: .cancelTranscription)
        )
        #expect(
            PhaseMachine.decide(phase: .transcribing, event: .transcriptionFinished)
                == PhaseMachine.Decision(phase: .idle, action: .finish)
        )
    }

    @Test("Audio events in idle are ignored")
    func irrelevantEvents() {
        for event in [PhaseEvent.audioStarted, .audioStalled, .startTimedOut, .transcriptionFinished, .cancelRequested] {
            let decision = PhaseMachine.decide(phase: .idle, event: event)
            #expect(decision == PhaseMachine.Decision(phase: .idle, action: .none))
        }
    }
}
