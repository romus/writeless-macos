# Write Less

Speech to text in the macOS menu bar. Press a shortcut, talk, press it again — the
transcript lands on your clipboard, ready to paste. Everything runs on your Mac:
no account, no network after the model is downloaded.

Version 2 is a native Swift rewrite. [Version 1](https://github.com/romus/writeless) was Python.

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon

## Install

```bash
brew tap romus/writeless
brew install --cask writeless
```

Write Less asks for one permission on first launch:

- **Microphone** — to record.

The speech model (about 630 MB) downloads on first launch. Loading it the first time
also compiles it for the Neural Engine, which can take a few minutes; later launches
take seconds. The menu shows the progress.

## Use

- **⌥⌘Space** (default) starts and stops dictation. The menu's "Stop & Copy" does
  the same.
- A capsule at the bottom of the screen shows the level and the elapsed time while
  recording, and it never takes focus, so you can keep typing.
- The transcript goes to the clipboard; press ⌘V to paste it. Write Less never types
  for you, so a transcript can't land somewhere you didn't expect.

If ⌥⌘Space does nothing, macOS is probably still using it for "Show Finder search
window": Settings shows "Used by a macOS shortcut" — pick another shortcut, or turn
the system one off in System Settings → Keyboard → Keyboard Shortcuts.

## Settings

Open them from the menu.

| Setting | Notes |
|---|---|
| Shortcut | Click, then press a combination. Esc cancels. ⌥-only combinations are refused: macOS never delivers them. |
| Model | Tiny (77 MB), Base (147 MB), Small (486 MB), Medium (1.5 GB), Large (627 MB, large-v3-turbo — the default, and the best quality for its size). |
| Language | Automatic detection, or a fixed language when detection keeps guessing wrong on short phrases. |
| Sound on finish | Plays the system "Glass" sound when a transcript is ready. |
| Launch at login | Managed through macOS login items. |
| Appearance | Light, Dark or System. |
| Advanced → Model cache | How much `~/Library/Application Support/Writeless/Models` holds. "Clear" deletes every downloaded model, the tokenizer and any half-finished download; the selected model downloads again the next time you dictate. |

Files:

- Models: `~/Library/Application Support/Writeless/Models`
- Preferences: `defaults read dev.romus.writeless`
- Logs: `log show --predicate 'subsystem BEGINSWITH "dev.romus.writeless"' --last 10m --info`

## Build from source

```bash
brew install xcodegen
make setup-signing   # sign Debug builds with your Apple Development certificate
make run             # build and launch
make test            # WritelessCore tests
make release         # signed release build in build/dist
make zip             # release build + archive for Homebrew
make install         # copy the release build into /Applications
make uninstall       # remove it from /Applications
```

`make install` replaces `/Applications/Write Less.app`, and warns first when Homebrew's
`writeless` cask manages that same path — a later `brew upgrade` would overwrite the local
build. `make uninstall` removes the app again; it refuses if something else occupies that
path, keeps the models and preferences, and leaves the login item alone — turn "Launch at
login" off before uninstalling, or clear the leftover entry in System Settings → General →
Login Items.

`project.yml` is the source of truth for the Xcode project; run `make project` after
changing it. `make setup-signing` is worth doing once: ad-hoc signatures change on
every build, and macOS ties the Microphone permission to the signature, so without
it you re-grant it constantly.

Releases are ad-hoc signed by default. To use a real identity:

```bash
make zip SIGN_IDENTITY="Developer ID Application: …"
```

## Layout

```
Writeless/            the app: menu bar, settings, pill, audio, transcription
Packages/WritelessCore/  pure logic (shortcuts, catalogs, speech gate, phase machine) + tests
Config/               xcconfigs: version, bundle ids, signing
scripts/              app icon (make icon), Homebrew cask, local signing
```
