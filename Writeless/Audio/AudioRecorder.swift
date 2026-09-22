import AVFoundation
import CoreAudio
import Foundation
import WritelessCore
import os

/// Captures a microphone as 16 kHz mono Float32, which is what Whisper wants.
///
/// Deliberately not MainActor-isolated: the tap block runs on a real-time audio
/// thread, and a closure formed in a MainActor context would trip Swift 6's
/// runtime isolation check there. Engine calls run on a private serial queue
/// because `AVAudioEngine.start()` can block for seconds on Bluetooth.
nonisolated final class AudioRecorder: @unchecked Sendable {
    enum Mode {
        /// Keeps every sample, for a dictation.
        case record
        /// Keeps none: only the level, for the meter in Settings.
        case monitor
    }

    enum RecorderError: LocalizedError {
        case noInputDevice
        case cannotConvertAudio
        /// AVFAudio raised rather than returned. `ObjCException` caught it.
        case engineRefused(String)

        var errorDescription: String? {
            switch self {
            case .noInputDevice: "No microphone is available."
            case .cannotConvertAudio: "The microphone format is not supported."
            case .engineRefused(let reason): "The audio engine refused to start: \(reason)"
            }
        }
    }

    /// Called once per recording, when the first buffer lands.
    var onFirstBuffer: (@Sendable () -> Void)?
    /// The input is gone and could not be replaced.
    var onInterrupted: (@Sendable () -> Void)?

    private struct Capture {
        var samples: [Float] = []
        var peakLevel: Float = 0
        var lastBufferAt: Date?
        var receivedAudio = false
    }

    /// Source format, target format and the converter between them, kept
    /// together because all three have to change at once.
    private struct Conversion {
        let source: AVAudioFormat
        let target: AVAudioFormat
        let converter: AVAudioConverter

        static func make(source: AVAudioFormat) -> Conversion? {
            guard
                source.sampleRate > 0, source.channelCount > 0,
                let target = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false
                ),
                let converter = AVAudioConverter(from: source, to: target)
            else { return nil }
            converter.downmix = true
            return Conversion(source: source, target: target, converter: converter)
        }
    }

    private let mode: Mode
    private let queue = DispatchQueue(label: "dev.romus.writeless.audio")
    private let capture = OSAllocatedUnfairLock(initialState: Capture())
    private var engine: AVAudioEngine?
    /// The format the tap was installed against, so a configuration change that
    /// leaves the tap usable can be told from one that doesn't.
    private var tapFormat: AVAudioFormat?
    /// Written on `queue` before the tap exists, and afterwards only from the
    /// tap thread — `removeTap` drains that thread before the queue writes again.
    private var conversion: Conversion?
    private var configurationObserver: NSObjectProtocol?
    /// What the user picked. `nil` follows the system input.
    private var requestedDevice: InputDevice?
    /// A device that reconfigures itself over and over must not be chased
    /// forever; after this many tries the recording is handed back instead.
    private var rebindsLeft = 0

    init(mode: Mode = .record) {
        self.mode = mode
    }

    // MARK: - Lifecycle

    func start(device: InputDevice?) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try self.startOnQueue(device: device)
                    continuation.resume()
                } catch {
                    self.teardownEngineOnQueue()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Moves an in-flight capture to another microphone without losing a
    /// syllable: everything is resampled to 16 kHz mono before it is kept, so a
    /// 24 kHz half and a 48 kHz half simply abut. Remembers the choice for the
    /// next recording when nothing is running.
    func switchInput(to device: InputDevice?) async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.requestedDevice = device
                guard self.engine != nil else {
                    continuation.resume()
                    return
                }
                do {
                    try self.rebindOnQueue()
                } catch {
                    Log.audio.error("Could not switch the input: \(error.localizedDescription, privacy: .public)")
                    self.teardownEngineOnQueue()
                    self.onInterrupted?()
                }
                continuation.resume()
            }
        }
    }

    /// Stops and returns everything captured so far.
    func stop() async -> [Float] {
        await withCheckedContinuation { continuation in
            queue.async {
                self.teardownEngineOnQueue()
                let samples = self.capture.withLock { state -> [Float] in
                    let samples = state.samples
                    state = Capture()
                    return samples
                }
                continuation.resume(returning: samples)
            }
        }
    }

    /// Stops and throws the audio away.
    func cancel() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.teardownEngineOnQueue()
                self.capture.withLock { $0 = Capture() }
                continuation.resume()
            }
        }
    }

    // MARK: - State the UI polls

    /// Loudest RMS since the previous call, for the waveform and the meter.
    func takeLevel() -> Float {
        capture.withLock { state in
            defer { state.peakLevel = 0 }
            return state.peakLevel
        }
    }

    var lastBufferAt: Date? { capture.withLock { $0.lastBufferAt } }

    // MARK: - Engine

    private func startOnQueue(device: InputDevice?) throws {
        teardownEngineOnQueue()
        requestedDevice = device
        rebindsLeft = 3
        capture.withLock { state in
            state = Capture()
            if mode == .record {
                // Roughly a minute of 16 kHz mono, so the tap thread isn't
                // reallocating while it holds the lock.
                state.samples.reserveCapacity(16_000 * 60)
            }
        }
        try startEngineOnQueue()
    }

    private func startEngineOnQueue() throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode

        // Only an explicit choice is pinned. Following the system input needs no
        // pin at all, and skipping it is what keeps the engine's graph and the
        // hardware in agreement — see the comment on `installTap` below.
        if let device = requestedDevice {
            pin(device, on: input)
        }

        // Re-reads the hardware, so the graph agrees with the device that was
        // just swapped underneath it.
        engine.prepare()

        guard let format = settledInputFormat(input) else { throw RecorderError.noInputDevice }
        guard let conversion = Conversion.make(source: format) else { throw RecorderError.cannotConvertAudio }
        self.conversion = conversion

        // `format: nil` on purpose. Handing AVFAudio a format we read ourselves
        // makes it compare that against what its graph believes the hardware is
        // doing, and a mismatch is an `NSException` — which is an `abort()`,
        // because Swift cannot catch one. Any input that does not run at the
        // rate the graph was built with used to crash here: AirPods at 24 kHz,
        // every single time. With `nil` AVFAudio reads the bus itself and has
        // nothing to disagree with.
        try ObjCException.guarding {
            input.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
                self?.append(buffer)
            }
        }
        tapFormat = format

        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            // Posted from the render thread; the engine is only ever touched on
            // our own queue, which also orders this after `startEngineOnQueue`.
            guard let self else { return }
            queue.async { self.handleConfigurationChangeOnQueue() }
        }

        // Before `start()`, so a throw from it still finds an engine to tear down.
        self.engine = engine
        try ObjCException.guarding { try engine.start() }
        let what = mode == .record ? "Recording" : "Monitoring"
        Log.audio.info("\(what, privacy: .public) from \(self.describe(format), privacy: .public)")
    }

    /// Swaps the IO unit's device. Reports failure rather than swallowing it:
    /// a pin that silently does nothing leaves the recording on a microphone
    /// the user did not choose.
    private func pin(_ device: InputDevice, on input: AVAudioInputNode) {
        guard let audioUnit = input.audioUnit else {
            Log.audio.error("The input node has no audio unit; using the system input")
            return
        }
        guard var deviceID = AudioDevices.deviceID(forUID: device.uid) else {
            Log.audio.info("\(device.name, privacy: .public) is not connected; using the system input")
            return
        }
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            Log.audio.error("Could not select \(device.name, privacy: .public): \(status, privacy: .public)")
        }
    }

    /// A Bluetooth input can report nothing at all for a few tens of
    /// milliseconds while its link comes up. Returns as soon as there is a real
    /// format, so a device that is already awake costs nothing.
    private func settledInputFormat(_ input: AVAudioInputNode) -> AVAudioFormat? {
        for attempt in 0..<25 {
            let format = input.outputFormat(forBus: 0)
            if format.sampleRate > 0, format.channelCount > 0 { return format }
            if attempt == 0 { Log.audio.info("Waiting for the input to report a format") }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return nil
    }

    private func teardownEngineOnQueue() {
        if let observer = configurationObserver {
            NotificationCenter.default.removeObserver(observer)
            configurationObserver = nil
        }
        tapFormat = nil
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        // The tap thread is drained by `removeTap`, so the converter is ours again.
        conversion = nil
        // Dropping the engine releases the device, so the orange microphone
        // indicator goes away right after a recording.
        self.engine = nil
    }

    /// Rebuilds the capture on the currently wanted device, keeping everything
    /// already recorded.
    private func rebindOnQueue() throws {
        teardownEngineOnQueue()
        try startEngineOnQueue()
        // The new device may take a moment to speak; the caller's stall
        // watchdog must not count the silence before the swap.
        capture.withLock { $0.lastBufferAt = Date() }
    }

    /// AVAudioEngine posts a configuration change whenever the hardware moves
    /// under it — the user picking another microphone in Settings, AirPods
    /// going back in their case, a display being unplugged. A change is only
    /// worth acting on when the tap can no longer be trusted: the engine
    /// stopped, or the format moved. A device that goes quiet without saying so
    /// is caught by the caller's stall watchdog instead.
    private func handleConfigurationChangeOnQueue() {
        guard let engine, let tapFormat else { return }

        let current = engine.inputNode.outputFormat(forBus: 0)
        if engine.isRunning,
           current.sampleRate == tapFormat.sampleRate,
           current.channelCount == tapFormat.channelCount {
            Log.audio.debug("Audio engine settled; the tap still fits")
            return
        }

        Log.audio.info("Audio configuration changed under the tap: \(self.describe(current), privacy: .public), running \(engine.isRunning, privacy: .public)")

        guard rebindsLeft > 0 else {
            Log.audio.error("The input keeps reconfiguring itself; giving the recording back")
            onInterrupted?()
            return
        }
        rebindsLeft -= 1

        do {
            try rebindOnQueue()
        } catch {
            Log.audio.error("Could not follow the input: \(error.localizedDescription, privacy: .public)")
            teardownEngineOnQueue()
            onInterrupted?()
        }
    }

    private func describe(_ format: AVAudioFormat) -> String {
        "\(format.sampleRate) Hz, \(format.channelCount) ch"
    }

    // MARK: - The tap

    private func append(_ buffer: AVAudioPCMBuffer) {
        let format = buffer.format
        // A zero sample rate would make the frame count below infinite, and
        // `AVAudioFrameCount(infinity)` is an unconditional trap — on the
        // real-time thread, where a trap is the whole app.
        guard buffer.frameLength > 0, format.sampleRate > 0, format.channelCount > 0 else { return }

        // The buffers can arrive in a format the engine never announced, which
        // the old converter would refuse by raising. Rebuilding is cheap and
        // happens once per change, not once per buffer.
        if conversion?.source.isEqual(format) != true {
            guard let rebuilt = Conversion.make(source: format) else { return }
            Log.audio.info("Converting from \(self.describe(format), privacy: .public)")
            conversion = rebuilt
        }
        guard let conversion else { return }

        let ratio = conversion.target.sampleRate / format.sampleRate
        let frames = (Double(buffer.frameLength) * ratio).rounded(.up)
        let capacity = AVAudioFrameCount(min(max(frames, 0), 1_048_576)) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: conversion.target, frameCapacity: capacity) else { return }

        var handedOver = false
        var conversionError: NSError?
        let status = conversion.converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if handedOver {
                // Never .endOfStream: that would retire the converter for good.
                inputStatus.pointee = .noDataNow
                return nil
            }
            handedOver = true
            inputStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, output.frameLength > 0, let channel = output.floatChannelData?[0] else {
            if let conversionError {
                Log.audio.error("Audio conversion failed: \(conversionError.localizedDescription, privacy: .public)")
            }
            return
        }

        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
        let level = SpeechGate.rootMeanSquare(samples)

        let isFirstBuffer = capture.withLock { state in
            // The monitor only ever reports a level; nothing it hears is kept.
            if mode == .record { state.samples.append(contentsOf: samples) }
            state.peakLevel = max(state.peakLevel, level)
            state.lastBufferAt = Date()
            defer { state.receivedAudio = true }
            return !state.receivedAudio
        }
        if isFirstBuffer { onFirstBuffer?() }
    }
}
