import AppKit
import WritelessCore

/// The menu bar item and its menu. Items are created once and shown or hidden
/// per state, because replacing `menu.items` while the menu is open is a good
/// way to make it flicker.
final class StatusItemController: NSObject, NSMenuDelegate {
    var onToggle: (() -> Void)?
    var onCancel: (() -> Void)?
    var onRetryDownload: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenMicrophoneSettings: (() -> Void)?

    private(set) var isMenuOpen = false

    private let state: AppState
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()

    private let headerItem = NSMenuItem()
    private let toggleItem = NSMenuItem()
    private let cancelItem = NSMenuItem()
    private let retryItem = NSMenuItem()
    private let microphoneItem = NSMenuItem()

    /// Reassigning the label on every tick would restate it to VoiceOver.
    private var lastAccessibilityLabel: String?

    init(state: AppState) {
        self.state = state
        super.init()
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.toolTip = "Write Less"
        buildMenu()
        item.menu = menu
        statusItem = item
        refresh()
    }

    func remove() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    // MARK: - Menu

    private func buildMenu() {
        menu.delegate = self
        menu.autoenablesItems = false

        headerItem.isEnabled = false

        configure(toggleItem, action: #selector(toggleTapped))
        configure(cancelItem, title: "Cancel", action: #selector(cancelTapped))
        configure(retryItem, title: "Retry Download", action: #selector(retryTapped))
        configure(microphoneItem, title: "Open Microphone Settings…", action: #selector(microphoneTapped))

        let settingsItem = NSMenuItem()
        configure(settingsItem, title: "Settings…", action: #selector(settingsTapped))

        let quitItem = NSMenuItem()
        configure(quitItem, title: "Quit", action: #selector(quitTapped))
        quitItem.keyEquivalent = "q"
        quitItem.keyEquivalentModifierMask = [.command]

        menu.addItem(headerItem)
        menu.addItem(toggleItem)
        menu.addItem(cancelItem)
        menu.addItem(retryItem)
        menu.addItem(microphoneItem)
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
    }

    private func configure(_ item: NSMenuItem, title: String = "", action: Selector) {
        item.title = title
        item.action = action
        item.target = self
        item.isEnabled = true
    }

    /// Repaints the icon and every item from the current state. Cheap enough to
    /// call from the 20 Hz tick while recording.
    func refresh() {
        let indicator = state.indicator
        let dotColor = dotColor(for: indicator)

        statusItem?.button?.image = icon
        applyAccessibilityLabel(for: indicator)

        if let header {
            headerItem.attributedTitle = attributedHeader(header, dotColor: dotColor)
            headerItem.isHidden = false
        } else {
            headerItem.isHidden = true
        }

        toggleItem.isHidden = state.phase == .transcribing
        toggleItem.title = state.isRecording ? "Stop & Copy" : "Start Recording"
        let equivalent = state.shortcut.menuKeyEquivalent
        toggleItem.keyEquivalent = equivalent.key
        toggleItem.keyEquivalentModifierMask = equivalent.modifiers

        cancelItem.isHidden = state.phase != .transcribing
        // Both names sit on the same action: a cleared cache offers "Download",
        // a failed one "Retry Download".
        let prompt = state.modelStatus.downloadPrompt
        if let prompt { retryItem.title = prompt.menuTitle }
        retryItem.isHidden = prompt == nil
        microphoneItem.isHidden = state.microphone != .denied
    }

    private var icon: NSImage? {
        let symbol: String
        switch state.phase {
        case .starting, .recording:
            symbol = "mic.fill"
        case .transcribing:
            symbol = "waveform"
        case .idle:
            if state.microphone == .denied {
                symbol = "mic.slash"
            } else {
                symbol = state.modelStatus.idleSymbolName ?? "mic"
            }
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Write Less")
        image?.isTemplate = true
        return image
    }

    private var header: String? {
        if state.isRecording {
            return "Recording \(ClockFormat.elapsed(state.elapsedSeconds))"
        }
        if state.phase == .transcribing {
            return "Transcribing…"
        }
        if state.microphone == .denied {
            return "Microphone access needed"
        }
        if let modelHeader = state.modelStatus.menuHeader {
            return modelHeader
        }
        switch state.hotkeyStatus {
        case .active:
            // The design's status row. Only while everything is actually ready:
            // a missing model leaves the header out, as it always has.
            return state.indicator == .ready ? "Ready" : nil
        case .takenBySystem:
            return "\(state.shortcut.displayString) is used by macOS"
        case .takenByAnotherApp:
            return "\(state.shortcut.displayString) is used by another app"
        case .rejected(let rejection):
            return rejection.message
        }
    }

    /// The dot's colour, already dimmed to the current point of the pulse.
    /// `nil` when there is no dot to draw.
    private func dotColor(for indicator: StatusIndicator) -> NSColor? {
        guard let color = indicator.dotColor else { return nil }
        guard indicator.pulses else { return color }
        return color.withAlphaComponent(StatusIndicator.pulseOpacity(at: state.elapsedSeconds))
    }

    private func applyAccessibilityLabel(for indicator: StatusIndicator) {
        let label = indicator.accessibilityDescription.map { "Write Less — \($0)" } ?? "Write Less"
        guard label != lastAccessibilityLabel else { return }
        lastAccessibilityLabel = label
        statusItem?.button?.setAccessibilityLabel(label)
    }

    private func attributedHeader(_ text: String, dotColor: NSColor?) -> NSAttributedString {
        let size = NSFont.menuFont(ofSize: 0).pointSize
        let title = NSMutableAttributedString()
        if let dotColor {
            title.append(NSAttributedString(
                string: "● ",
                attributes: [.foregroundColor: dotColor, .font: NSFont.systemFont(ofSize: size * 0.8)]
            ))
        }
        title.append(NSAttributedString(
            string: text,
            attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
                // Monospaced digits keep the timer from jittering as it ticks.
                .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular),
            ]
        ))
        return title
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        refresh()
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
    }

    // MARK: - Actions

    @objc private func toggleTapped() { onToggle?() }
    @objc private func cancelTapped() { onCancel?() }
    @objc private func retryTapped() { onRetryDownload?() }
    @objc private func settingsTapped() { onOpenSettings?() }
    @objc private func microphoneTapped() { onOpenMicrophoneSettings?() }
    @objc private func quitTapped() { NSApp.terminate(nil) }
}
