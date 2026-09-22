import Foundation
import Testing

@testable import WritelessCore

@Suite("Status indicator")
struct StatusIndicatorTests {
    private func indicator(
        phase: Phase,
        model: ModelStatus = .ready,
        microphoneDenied: Bool = false,
        hotkey: HotkeyStatus = .active
    ) -> StatusIndicator {
        StatusIndicator.current(
            phase: phase,
            modelStatus: model,
            microphoneDenied: microphoneDenied,
            hotkeyStatus: hotkey
        )
    }

    @Test("A healthy idle app is green")
    func ready() {
        #expect(indicator(phase: .idle) == .ready)
    }

    @Test("Recording is red, transcribing is orange")
    func activePhases() {
        #expect(indicator(phase: .recording) == .recording)
        #expect(indicator(phase: .transcribing) == .transcribing)
    }

    @Test("Starting has no dot until audio arrives")
    func starting() {
        #expect(indicator(phase: .starting) == .none)
    }

    @Test(
        "Idle shows no dot while the model can't be used",
        arguments: [
            ModelStatus.missing,
            .downloading(downloaded: 10, total: 100),
            .preparing(firstRun: true),
            .preparing(firstRun: false),
            .failed("boom"),
        ]
    )
    func unusableModel(model: ModelStatus) {
        #expect(indicator(phase: .idle, model: model) == .none)
    }

    @Test("A denied microphone drops the green dot")
    func microphoneDenied() {
        #expect(indicator(phase: .idle, microphoneDenied: true) == .none)
    }

    @Test(
        "A shortcut the app doesn't own drops the green dot",
        arguments: [
            HotkeyStatus.takenBySystem,
            .takenByAnotherApp,
            .rejected(.optionOnlyIsIgnoredByMacOS),
        ]
    )
    func brokenHotkey(hotkey: HotkeyStatus) {
        #expect(indicator(phase: .idle, hotkey: hotkey) == .none)
    }

    @Test("An active phase keeps its dot even when something else is wrong")
    func activeBeatsBlockers() {
        #expect(indicator(phase: .recording, model: .missing, microphoneDenied: true) == .recording)
        #expect(indicator(phase: .transcribing, model: .failed("boom"), hotkey: .takenBySystem) == .transcribing)
    }

    @Test("Only recording pulses")
    func pulses() {
        #expect(StatusIndicator.recording.pulses)
        #expect(!StatusIndicator.ready.pulses)
        #expect(!StatusIndicator.transcribing.pulses)
        #expect(!StatusIndicator.none.pulses)
    }

    @Test("The pulse runs from full to a third and back")
    func pulseEnds() {
        #expect(StatusIndicator.pulseOpacity(at: 0).isApproximately(1))
        #expect(StatusIndicator.pulseOpacity(at: 0.7).isApproximately(0.3))
        #expect(StatusIndicator.pulseOpacity(at: 1.4).isApproximately(1))
    }

    @Test("The pulse stays inside its range and repeats every 1.4 s")
    func pulseCycle() {
        for step in 0...500 {
            let t = Double(step) / 100
            let value = StatusIndicator.pulseOpacity(at: t)
            #expect(value >= 0.3 && value <= 1.0)
            #expect(value.isApproximately(StatusIndicator.pulseOpacity(at: t + 1.4)))
        }
    }

    @Test("A nonsensical elapsed time doesn't dim the dot")
    func pulseGuards() {
        #expect(StatusIndicator.pulseOpacity(at: .nan) == 1)
        #expect(StatusIndicator.pulseOpacity(at: 1, cycle: 0) == 1)
    }
}

private extension Double {
    func isApproximately(_ other: Double, tolerance: Double = 1e-9) -> Bool {
        abs(self - other) < tolerance
    }
}
