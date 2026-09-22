import AppKit
import WritelessCore

/// Wires the pieces together and owns the record → transcribe → copy
/// lifecycle. The transitions themselves live in `PhaseMachine`, which is
/// pure and unit-tested; this class performs their side effects.
final class AppCoordinator {
    private let state = AppState()
    private let preferences = Preferences()
    private let store = ModelStore()
    private let engine: TranscriptionEngine
    private let recorder = AudioRecorder()
    /// A second capture, kept alive only while Settings is open, so the
    /// microphone row can show whether the chosen input is hearing anything.
    private let monitor = AudioRecorder(mode: .monitor)
    private let hotkey = GlobalHotkey()
    private let statusItem: StatusItemController
    private let pill: PillController
    private var settings: SettingsWindowController?

    private var tickTimer: Timer?
    private var engineTask: Task<Void, Never>?
    private var cacheSizeTask: Task<Void, Never>?
    private var transcriptionTask: Task<Void, Never>?
    private var startTask: Task<Void, Never>?
    private var transcriptionStartedAt: Date?
    private var noticeTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var activity: NSObjectProtocol?
    private var startRequestedAt: Date?
    private var lastToggleAt: Date?
    private var modelChangePending = false
    private var monitorTask: Task<Void, Never>?
    private var deviceListener: AudioDevices.Listener?
    private var isSettingsOpen = false
    private var isMonitoring = false

    init() {
        engine = TranscriptionEngine(store: store)
        statusItem = StatusItemController(state: state)
        pill = PillController(state: state)
    }

    // MARK: - Lifecycle

    func start() {
        preferences.appearance.apply()
        state.shortcut = preferences.shortcut
        state.microphone = Permissions.microphone

        settings = SettingsWindowController(
            preferences: preferences,
            state: state,
            actions: SettingsActions(
                windowOpened: { [weak self] in self?.settingsWindowChanged(isOpen: true) },
                windowClosed: { [weak self] in
                    self?.setHotkeySuspended(false)
                    self?.settingsWindowChanged(isOpen: false)
                },
                shortcutChanged: { [weak self] in self?.registerHotkey() },
                inputDeviceChanged: { [weak self] in self?.inputDeviceChanged() },
                modelChanged: { [weak self] in self?.prepareModel() },
                retryModelDownload: { [weak self] in self?.prepareModel() },
                refreshModelCacheSize: { [weak self] in self?.refreshModelCacheSize() },
                clearModelCache: { [weak self] in self?.clearModelCache() },
                hotkeyRecordingChanged: { [weak self] isRecording in self?.setHotkeySuspended(isRecording) }
            )
        )

        wireStatusItem()
        wireRecorder()
        observeModelStatus()
        observeSystemEvents()
        observeInputDevices()

        statusItem.install()
        registerHotkey(isInitial: true)
        prepareModel()
        requestPermissionsIfNeeded()
        startTicking()
        refreshUI()
        Log.app.info("Write Less started")
    }

    func showSettings() {
        settings?.show()
    }

    func shutDown() {
        tickTimer?.invalidate()
        engineTask?.cancel()
        cacheSizeTask?.cancel()
        transcriptionTask?.cancel()
        startTask?.cancel()
        noticeTask?.cancel()
        monitorTask?.cancel()
        if let deviceListener {
            AudioDevices.removeListener(deviceListener)
            self.deviceListener = nil
        }
        hotkey.unregister()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceObservers.removeAll()
        endActivity()
        pill.close()
        statusItem.remove()
        // Quitting never waits on audio teardown; the process going away
        // releases the device anyway.
        Task { await recorder.cancel() }
        Task { await monitor.cancel() }
    }

    // MARK: - Wiring

    private func wireStatusItem() {
        statusItem.onToggle = { [weak self] in self?.handle(.toggleRequested) }
        statusItem.onCancel = { [weak self] in self?.handle(.cancelRequested) }
        statusItem.onRetryDownload = { [weak self] in self?.prepareModel() }
        statusItem.onOpenSettings = { [weak self] in self?.settings?.show() }
        statusItem.onOpenMicrophoneSettings = { Permissions.openMicrophoneSettings() }
    }

    private func wireRecorder() {
        // Both callbacks arrive off the main thread.
        recorder.onFirstBuffer = { [weak self] in
            Task { @MainActor in self?.handle(.audioStarted) }
        }
        recorder.onInterrupted = { [weak self] in
            Task { @MainActor in self?.handle(.audioInterrupted) }
        }
    }

    private func observeModelStatus() {
        let statuses = engine.statuses
        engineTask = Task { [weak self] in
            for await status in statuses {
                guard let self else { return }
                state.modelStatus = status
                // The size on disk only moves when a download does, and only
                // matters once the Advanced section has asked for a value.
                if status == .ready, state.modelCacheBytes != nil { refreshModelCacheSize() }
                refreshUI()
            }
        }
    }

    private func observeSystemEvents() {
        workspaceObservers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.handle(.audioInterrupted) }
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.pill.refresh() }
            }
        )
    }

    /// Devices come and go — AirPods connect, a display is unplugged, the
    /// system input changes under us — and the picker has to keep up.
    private func observeInputDevices() {
        deviceListener = AudioDevices.addListener(queue: .main) { [weak self] in
            MainActor.assumeIsolated { self?.refreshInputDevices() }
        }
        refreshInputDevices()
    }

    private func refreshInputDevices() {
        // An input that vanishes mid-recording is not handled here: the
        // recorder hears about it from the engine first and re-binds itself.
        let devices = InputDeviceCatalog.deduplicated(AudioDevices.inputs())
        if devices.map(\.uid) != state.inputDevices.map(\.uid) {
            let names = devices.map(\.name).joined(separator: ", ")
            Log.audio.info("Inputs: \(names.isEmpty ? "none" : names, privacy: .public)")
        }
        state.inputDevices = devices
    }

    // MARK: - State machine

    private func handle(_ event: PhaseEvent) {
        let decision = PhaseMachine.decide(phase: state.phase, event: event, blocker: currentBlocker())
        if decision.action != .none {
            Log.app.info("\(String(describing: event), privacy: .public) in \(String(describing: self.state.phase), privacy: .public) → \(String(describing: decision.action), privacy: .public)")
        }
        state.phase = decision.phase
        perform(decision.action)
        refreshUI()
    }

    private func currentBlocker() -> RecordingBlocker? {
        if state.microphone == .denied { return .microphoneDenied }
        return state.modelStatus.recordingBlocker
    }

    private func perform(_ action: PhaseAction) {
        switch action {
        case .none:
            break

        case .startRecording:
            startRecording()

        case .markRecording:
            state.recordingStartedAt = Date()
            state.elapsedSeconds = 0

        case .stopAndTranscribe:
            startTask?.cancel()
            startTask = nil
            stopAndTranscribe()

        case .abortRecording(let notice):
            startTask?.cancel()
            startTask = nil
            Task { await recorder.cancel() }
            endRecordingSession()
            show(notice)

        case .rejectRecording(let blocker):
            switch blocker {
            case .microphoneDenied:
                showMicrophoneAlert()
            case .modelUnavailable:
                // Nothing downloads a model on its own any more, so the first
                // dictation after a cleared cache is what starts it.
                prepareModel()
                show(.modelDownloading(percent: 0))
            case .modelDownloading, .modelPreparing:
                show(blocker.notice)
            }

        case .cancelTranscription:
            transcriptionTask?.cancel()
            transcriptionTask = nil
            endRecordingSession()
            applyPendingModelChange()

        case .finish:
            endRecordingSession()
            applyPendingModelChange()

        case .beep:
            Sounds.beep()
        }
    }

    // MARK: - Recording

    private func startRecording() {
        state.levels.reset()
        state.recordingStartedAt = nil
        state.elapsedSeconds = 0
        setInputLevel(0)
        startRequestedAt = Date()

        // The dictation wants the device to itself: two clients of one
        // Bluetooth input is a good way to be handed a format nobody asked for.
        setMonitoring(false)
        let monitorStopped = monitorTask
        let device = preferences.inputDevice

        startTask = Task { [weak self] in
            guard let self else { return }
            if Permissions.microphone == .undetermined {
                // This can sit on the permission dialog for as long as the user
                // takes to read it, by which point the watchdog may have given up.
                _ = await Permissions.requestMicrophone()
                guard !Task.isCancelled, state.phase == .starting else { return }
                state.microphone = Permissions.microphone
            }
            guard Permissions.microphone == .granted else {
                handle(.startFailed)
                return
            }
            await monitorStopped?.value
            guard !Task.isCancelled else { return }
            do {
                try await recorder.start(device: device)
                // `.recording` counts as fine: the first buffer, and the phase
                // change with it, can land before `start()` gets back here.
                guard !Task.isCancelled, state.phase == .starting || state.phase == .recording else {
                    // The recording was abandoned while the engine was starting.
                    await recorder.cancel()
                    return
                }
            } catch {
                Log.audio.error("Could not start recording: \(error.localizedDescription, privacy: .public)")
                guard !Task.isCancelled else { return }
                handle(.startFailed)
            }
        }
    }

    private func stopAndTranscribe() {
        let model = preferences.model
        let language = preferences.decodingLanguage

        transcriptionStartedAt = Date()
        transcriptionTask = Task { [weak self] in
            guard let self else { return }
            let samples = await recorder.stop()

            do {
                try Task.checkCancellation()

                // WhisperKit's own no-speech check is a stub in 1.1.0, so
                // silence is filtered here instead of being turned into
                // invented text. A quarter of an hour of audio is a lot of
                // arithmetic and a big copy, so it happens off the main actor.
                let (gate, speech) = await Task.detached(priority: .userInitiated) {
                    let gate = SpeechGate.analyze(samples: samples)
                    return (gate, gate.hasSpeech ? Array(samples[gate.range]) : [])
                }.value
                try Task.checkCancellation()
                Log.audio.info("Captured \(samples.count, privacy: .public) samples, \(gate.speechSeconds, privacy: .public) s of speech")

                guard gate.hasSpeech else {
                    finishTranscription(notice: .noSpeechDetected)
                    return
                }

                let raw = try await engine.transcribe(
                    samples: speech,
                    model: model,
                    language: language
                )
                try Task.checkCancellation()

                let text = TranscriptCleaner.clean(raw, speechSeconds: gate.speechSeconds)
                guard !text.isEmpty else {
                    finishTranscription(notice: .noSpeechDetected)
                    return
                }

                Clipboard.copy(text)
                Log.app.info("Copied \(text.count, privacy: .public) characters to the clipboard")
                if preferences.soundOnFinish { Sounds.playFinished() }
                finishTranscription(notice: .copiedToClipboard)
            } catch is CancellationError {
                Log.app.debug("Transcription cancelled")
            } catch {
                Log.app.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
                finishTranscription(notice: .transcriptionFailed)
            }
        }
    }

    private func finishTranscription(notice: Notice) {
        // Every transcription ends here, so the notice doubles as the one-line
        // record of how it went.
        Log.app.info("Transcription finished: \(String(describing: notice), privacy: .public)")
        show(notice)
        handle(.transcriptionFinished)
    }

    private func endRecordingSession() {
        transcriptionStartedAt = nil
        state.recordingStartedAt = nil
        state.elapsedSeconds = 0
        state.levels.reset()
        state.inputLevel = 0
        startRequestedAt = nil
    }

    // MARK: - Microphone

    /// Applies to whatever is running: an in-flight dictation moves to the new
    /// microphone without losing what it has, and an idle recorder simply
    /// remembers the choice for next time.
    private func inputDeviceChanged() {
        let device = preferences.inputDevice
        Log.audio.info("Microphone set to \(device?.name ?? "the system input", privacy: .public)")
        Task { [weak self] in
            guard let self else { return }
            await recorder.switchInput(to: device)
            await monitor.switchInput(to: device)
        }
    }

    private func settingsWindowChanged(isOpen: Bool) {
        isSettingsOpen = isOpen
        updateMonitoring()
    }

    private func updateMonitoring() {
        setMonitoring(isSettingsOpen && state.phase == .idle && state.microphone == .granted)
    }

    /// Starts and stops are chained rather than fired in parallel: they share
    /// one engine, and a stop that overtakes its start leaves the device open.
    private func setMonitoring(_ enabled: Bool) {
        guard enabled != isMonitoring else { return }
        isMonitoring = enabled

        let device = preferences.inputDevice
        let previous = monitorTask
        monitorTask = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            if enabled {
                do {
                    try await monitor.start(device: device)
                } catch {
                    Log.audio.error("Could not watch the input level: \(error.localizedDescription, privacy: .public)")
                }
            } else {
                await monitor.cancel()
                setInputLevel(0)
            }
        }
    }

    // MARK: - Model

    private func prepareModel() {
        guard state.phase == .idle else {
            // Swapping the pipeline mid-transcription would kill it, and
            // swapping it mid-recording would make the stop wait for a fresh
            // download before it could transcribe anything.
            modelChangePending = true
            return
        }
        let model = preferences.model
        Task { await engine.prepare(model) }
    }

    /// The walk is metadata only, but it is still filesystem work, and
    /// `ModelStore` is nonisolated — from a plain `Task` it would run right
    /// here, on the main actor.
    private func refreshModelCacheSize() {
        cacheSizeTask?.cancel()
        let store = self.store
        cacheSizeTask = Task { [weak self] in
            let bytes = await Task.detached(priority: .utility) { store.totalBytesOnDisk() }.value
            guard !Task.isCancelled, let self else { return }
            state.modelCacheBytes = bytes
        }
    }

    /// Refused rather than deferred, unlike a model change: a wipe that fires
    /// minutes later, long after the user confirmed it, is a bug. Settings
    /// disables the button off-idle too.
    private func clearModelCache() {
        guard state.phase == .idle else { return }
        Task { [weak self] in
            await self?.engine.clearCache()
            self?.refreshModelCacheSize()
        }
    }

    private func applyPendingModelChange() {
        guard modelChangePending else { return }
        modelChangePending = false
        prepareModel()
    }

    // MARK: - Hotkey

    private func registerHotkey(isInitial: Bool = false) {
        hotkey.onFire = { [weak self] in self?.hotkeyFired() }
        let status = hotkey.register(preferences.shortcut)
        state.shortcut = preferences.shortcut
        state.hotkeyStatus = status
        Log.hotkey.info("Registered \(self.preferences.shortcut.displayString, privacy: .public): \(String(describing: status), privacy: .public)")
        if isInitial, status == .takenBySystem { showSystemConflictAlert() }
        refreshUI()
    }

    private func setHotkeySuspended(_ suspended: Bool) {
        if suspended {
            hotkey.suspend()
        } else {
            state.hotkeyStatus = hotkey.resume()
            refreshUI()
        }
    }

    private func hotkeyFired() {
        let now = Date()
        // Carbon can deliver a burst if the key repeats.
        if let lastToggleAt, now.timeIntervalSince(lastToggleAt) < 0.2 { return }
        lastToggleAt = now
        handle(.toggleRequested)
    }

    // MARK: - Permissions

    private func requestPermissionsIfNeeded() {
        Task { [weak self] in
            guard let self else { return }
            if Permissions.microphone == .undetermined {
                _ = await Permissions.requestMicrophone()
            }
            state.microphone = Permissions.microphone
            refreshUI()
        }
    }

    private func showMicrophoneAlert() {
        // Never run a modal inside the Carbon hot key callback.
        Task { @MainActor in self.runMicrophoneAlert() }
    }

    private func runMicrophoneAlert() {
        let alert = NSAlert()
        alert.messageText = "Write Less needs access to the microphone"
        alert.informativeText = "Turn on Microphone for Write Less in System Settings → Privacy & Security."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            Permissions.openMicrophoneSettings()
        }
    }

    private func showSystemConflictAlert() {
        Task { @MainActor in self.runSystemConflictAlert() }
    }

    private func runSystemConflictAlert() {
        let alert = NSAlert()
        alert.messageText = "\(preferences.shortcut.displayString) is already used by macOS"
        alert.informativeText = """
            macOS handles this shortcut first, so Write Less never sees it. \
            Choose another shortcut, or turn the system one off in Keyboard Settings.
            """
        alert.addButton(withTitle: "Choose Shortcut…")
        alert.addButton(withTitle: "Open Keyboard Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn: settings?.show()
        case .alertSecondButtonReturn: Permissions.openKeyboardShortcutSettings()
        default: break
        }
    }

    // MARK: - Ticking

    private func startTicking() {
        // .common mode, or the timer stops while the menu is open.
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func tick() {
        // `takeLevel` resets the peak, so it is read once per tick and shared:
        // a second reader would see the silence the first one left behind.
        if state.isRecording {
            let level = LevelMeter.normalized(rms: recorder.takeLevel())
            state.levels.push(level)
            setInputLevel(level)
            if let startedAt = state.recordingStartedAt {
                state.elapsedSeconds = Date().timeIntervalSince(startedAt)
            }
            refreshUI()
        } else {
            if isMonitoring {
                setInputLevel(LevelMeter.normalized(rms: monitor.takeLevel()))
            }
            if statusItem.isMenuOpen { statusItem.refresh() }
        }
        checkWatchdogs()
    }

    /// Observation counts an equal value as a change, and a silent room would
    /// otherwise redraw the meter twenty times a second for nothing.
    private func setInputLevel(_ level: Float) {
        if level != state.inputLevel { state.inputLevel = level }
    }

    private func checkWatchdogs() {
        let now = Date()
        switch state.phase {
        case .starting:
            if let startRequestedAt, now.timeIntervalSince(startRequestedAt) > 10 {
                handle(.startTimedOut)
            }
        case .recording:
            if let last = recorder.lastBufferAt, now.timeIntervalSince(last) > 5 {
                Log.audio.error("No audio for 5 seconds; stopping")
                handle(.audioStalled)
            } else if let startedAt = state.recordingStartedAt, now.timeIntervalSince(startedAt) > 15 * 60 {
                handle(.maxDurationReached)
            }
        case .transcribing:
            // Transcription waits on the model, which can be loading; a
            // ceiling keeps a wedged load from parking the app here forever.
            if let transcriptionStartedAt, now.timeIntervalSince(transcriptionStartedAt) > 300 {
                Log.app.error("Transcription exceeded five minutes; cancelling")
                show(.transcriptionFailed)
                handle(.cancelRequested)
            }

        case .idle:
            break
        }
    }

    // MARK: - UI

    private func refreshUI() {
        statusItem.refresh()
        pill.refresh()
        updateActivity()
        updateMonitoring()
    }

    private func show(_ notice: Notice?) {
        noticeTask?.cancel()
        state.notice = notice
        guard notice != nil else { return }

        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1800))
            guard !Task.isCancelled, let self else { return }
            state.notice = nil
            refreshUI()
        }
    }

    /// Keeps timers and downloads running at full speed while there is work.
    private func updateActivity() {
        let isModelBusy: Bool
        switch state.modelStatus {
        case .downloading, .preparing: isModelBusy = true
        default: isModelBusy = false
        }

        if state.phase != .idle || isModelBusy {
            guard activity == nil else { return }
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated], reason: "Recording and transcribing"
            )
        } else {
            endActivity()
        }
    }

    private func endActivity() {
        guard let activity else { return }
        ProcessInfo.processInfo.endActivity(activity)
        self.activity = nil
    }
}
