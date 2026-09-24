# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this repository.

## Commands

```bash
make run             # build Debug and launch
make test            # WritelessCore tests (swift test, no app host)
make build           # build Debug
make project         # regenerate Writeless.xcodeproj after editing project.yml
make release         # Release build, signed with SIGN_IDENTITY (default: ad-hoc)
make zip             # release + Writeless-<version>.zip + SHA256
make cask            # render the Homebrew cask for the built archive
make install         # copy the release build into /Applications
make uninstall       # remove it from /Applications (settings and models kept)
make setup-signing   # write Config/Local.xcconfig from your Apple Development cert
make version         # print MARKETING_VERSION
```

Logs: `log show --predicate 'subsystem BEGINSWITH "dev.romus.writeless"' --last 10m --info`

## Architecture

Menu-bar-only app (`LSUIElement`). AppKit owns the lifecycle and the windows; SwiftUI
draws the settings rows and the pill.

- **`Writeless/App`** — `Main` (explicit `static main()`, strong app delegate),
  `AppState` (`@Observable`, everything the UI reads), `AppCoordinator` (wires
  everything, performs the side effects of the state machine).
- **`Writeless/MenuBar`** — status item and its menu; items are created once and
  shown or hidden per state.
- **`Writeless/Settings`** — window controller plus the SwiftUI rows and the
  shortcut recorder.
- **`Writeless/Pill`** — non-activating `NSPanel` with the recording capsule.
- **`Writeless/Hotkey`** — Carbon hot key, keyboard-layout key names, system
  shortcut conflicts.
- **`Writeless/Audio`** — `AVAudioEngine` capture, resampled to 16 kHz mono, plus
  `AudioDevices`, the CoreAudio device list and its change notifications. There are
  two `AudioRecorder`s: the dictation, and a `.monitor` one that runs only while
  Settings is open and keeps nothing but the level.
- **`Writeless/Transcription`** — `ModelStore` (files on disk) and
  `TranscriptionEngine` (actor around WhisperKit).
- **`Writeless/System`** — permissions, preferences, login item, sounds, logging,
  and the clipboard a transcript ends up on.
- **`Writeless/Support`** — the Obj-C exception guard, because AVFAudio raises
  where it ought to throw.
- **`Packages/WritelessCore`** — pure logic, no AppKit and no WhisperKit: shortcut
  model and validation, model, language and input-device catalogs, model folder
  layout, speech gate, transcript cleaner, level meter, `PhaseMachine`. This is
  where tests live.

Flow: hotkey → `PhaseMachine.decide` → `AppCoordinator` starts `AudioRecorder` →
stop → `SpeechGate` → `TranscriptionEngine.transcribe` → `TranscriptCleaner` →
`Clipboard`. The ⌘V is the user's.

## Things that will bite you

**Swift 6, default MainActor isolation.** The app target sets
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so anything touched off the main thread
must opt out explicitly — `AudioRecorder`, `ModelStore` and `Log` are all
`nonisolated`. A tap block formed in a MainActor context crashes at runtime on the
audio thread. Callbacks from timers, notifications and Carbon hop back with
`MainActor.assumeIsolated`. A `nonisolated deinit` cannot touch Carbon pointers, so
cleanup is explicit (`GlobalHotkey.unregister()`).

**WhisperKit 1.1.0** (`argmaxinc/argmax-oss-swift`, pinned exactly). Verified
behaviours the code depends on:

- `detectLanguage: true` is required for automatic language detection. A nil
  language alone prefills `<|en|>` and everything comes out English.
- `windowClipTime: 0` is required, or clips shorter than one second decode to
  nothing (the default clips one second off the end of every window).
- `noSpeechThreshold` does nothing: `noSpeechProb` is hardcoded to 0 upstream. Our
  own `SpeechGate` is the silence filter.
- `tokenizerFolder` must be set, or the tokenizer lands in `~/Documents/huggingface`
  and macOS asks for Documents access.
- `WhisperKit.download` resolves successfully when cancelled, returning a partial
  folder, and the VAD path drops per-chunk errors — so check `Task.checkCancellation()`
  and the files on disk afterwards.
- `WhisperKit` is not Sendable. It is imported in `TranscriptionEngine.swift` only,
  with `@preconcurrency`, and never leaves that actor.
- Models: `<base>/models/argmaxinc/whisperkit-coreml/<folder>`, tokenizer at
  `<base>/models/openai/whisper-*`. A `.writeless-ready` marker records the first
  successful load, which is how a slow first Neural Engine specialization is told
  apart from a fast cached load.
- The Core ML models are memory-mapped once loaded. Deleting them out from under a
  live pipeline succeeds on APFS and reclaims nothing: `kit` is left reading unlinked
  inodes. Clearing the cache therefore goes through the actor — drain the in-flight
  preparation, `unloadModels()`, delete — and only while `phase == .idle`. Nothing is
  re-downloaded afterwards, so `ModelStatus.missing` has to stay escapable: the first
  dictation starts the download, and `downloadPrompt` puts the same action in Settings
  and in the menu.

**Never hand `installTap` a format you read yourself.**
`installTap(onBus:bufferSize:format:)` compares the format it is given against what
the engine's graph believes the hardware is doing, and reports a mismatch by
*raising* an `NSException` — which Swift cannot catch, so it is an `abort()`.
Reading `outputFormat(forBus: 0)` and passing it straight back is exactly how the
two drift apart: touching `inputNode` realises the IO unit at one rate, and anything
that moves the device afterwards leaves the graph a step behind. AirPods run their
microphone at 24 kHz while every built-in input is 48 kHz, so this crashed every
recording on AirPods and none on the internal mic. The tap is installed with
`format: nil` — AVFAudio then reads the bus itself and has nothing to disagree with —
and the converter is rebuilt from `buffer.format` whenever that moves, instead of
being fixed at start. `WLExceptionGuard` wraps the call anyway, so a raise that does
get through becomes `RecorderError.engineRefused` and a "Microphone unavailable"
notice rather than a crash report.

Two smaller traps in the same tap: `AVAudioFrameCount(Double(frameLength) * ratio)`
is an unconditional Swift trap when the buffer reports a zero sample rate, which a
Bluetooth input does while its link comes up; and `self.engine` has to be assigned
*before* `engine.start()`, or a throw from `start()` leaves teardown with nothing to
find and the engine is released with a live tap.

**Pinning the input device.** `kAudioOutputUnitProperty_CurrentDevice` on the input
node's audio unit swaps the IO unit's device behind the engine's back, and the engine
notices roughly 100 ms after `start()` and posts `AVAudioEngineConfigurationChange`.
Taking that notification at face value stopped each recording after a tenth of a
second, which the speech gate then reported as "No speech detected". The pin now
happens only when the user picked a specific microphone; "System Default" needs no
pin, so the common case never provokes the notification at all. When a change does
arrive and the tap no longer fits, the recorder re-binds onto the wanted device — or
the system default, if that device has gone — and keeps what it has already captured:
everything is resampled to 16 kHz mono before it is kept, so a 24 kHz half and a
48 kHz half simply abut. Three failed re-binds in one recording and it gives up with
`onInterrupted`. A device that just goes quiet is caught by the stall watchdog, whose
five-second window restarts on every re-bind. The per-recording facts (`Recording
from … Hz`, `Captured … samples`) and every phase transition are logged at `info`,
because `debug` is not persisted and the alternative is reading CoreAudio's own log.

**Global shortcut.** `RegisterEventHotKey` reports success even for chords macOS
owns, and the system wins — `CopySymbolicHotKeys` is the only way to notice, and the
default ⌥⌘Space is "Show Finder search window" on a stock system. Since macOS 15,
⌥-only and ⌥⇧-only chords never fire, so they are refused.

**Menus and timers.** Timers that update the menu header or the pill must be added to
`RunLoop.main` in `.common` mode, or they freeze while a menu is open.

**Focus.** The pill is a non-activating panel and must never become key. When the
settings window closes, the app hides itself (`NSApp.hide`) so focus returns to the
app the user was typing in; otherwise their own ⌘V lands nowhere.

**The pill over full-screen apps.** It needs all of: an `NSPanel` with `.nonactivatingPanel`
from `init`, an accessory app, a level of at least `.statusBar`, and `.canJoinAllSpaces` +
`.fullScreenAuxiliary` — and *not* `.stationary`, which keeps the window with the desktop and
left the pill on the ordinary Spaces while the user dictated into a full-screen Ghostty. It is
ordered in again whenever the active Space or the displays change, and placed only when it
appears, not on every tick, so it does not chase the pointer to another display. The `pill`
log category records where it was shown and whether the window server actually put it on screen.

**Two names.** The product is "Write Less": `PRODUCT_NAME` and the display names, so the
bundle is `Write Less.app` and the process is `Write Less` — quote it in `pkill -x`, or it
silently matches nothing. Everything an identifier hangs off keeps the old spelling on purpose:
the bundle ids, the Xcode project, target and scheme, the `Writeless/` source folder,
`WritelessCore`, the cask token, the release archive `Writeless-<version>.zip`,
`~/Library/Application Support/Writeless/Models` and `.writeless-ready`. Renaming any of those
orphans a permission, a preference or a 630 MB model download. The Makefile keeps the three
roles in separate variables (`APP_NAME`, `PROJECT_NAME`, `ARCHIVE_NAME`).

**No auto-paste.** The transcript stops at the clipboard on purpose. Synthesizing ⌘V
needed the Accessibility permission, was swallowed by password fields and Secure
Keyboard Entry anyway, and — because nothing records which app the recording started
in — dropped the text into whatever had focus a moment later, in the middle of
whatever the user was typing. Bringing it back brings all three problems with it.

## Versioning and release

- The version lives in `Config/Version.xcconfig` (`MARKETING_VERSION`), read by
  Xcode, the Makefile and CI.
- Bundle ids: `dev.romus.writeless` (Release), `dev.romus.writeless.dev` (Debug), so
  a development build never shares permissions or preferences with an installed one.
- Tagging `v*` runs `.github/workflows/release.yml`: build, archive, GitHub release,
  install smoke test through a temporary tap, then a pull request against the
  Homebrew tap.
- Releases are ad-hoc signed. Their signature changes every build, so Homebrew cannot
  carry the Gatekeeper approval forward and the cask drops the quarantine flag in
  `postflight`. Switching to a stable identity (`SIGN_IDENTITY=…`) makes the
  Gatekeeper approval and the Microphone grant survive upgrades; remove the
  `postflight` block then.
