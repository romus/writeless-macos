import AppKit
import SwiftUI
import WritelessCore

/// Click, then press a combination. Esc cancels; combinations macOS won't
/// deliver are refused with a hint instead of being stored.
struct ShortcutRecorderButton: View {
    @Binding var shortcut: Shortcut
    @Binding var hint: String?
    /// The global hotkey is released while recording, so pressing the current
    /// shortcut records it instead of starting a recording.
    var onRecordingChanged: (Bool) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var modifierPreview = ""

    var body: some View {
        Button(action: toggle) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .frame(minWidth: 104, minHeight: 24)
        }
        .buttonStyle(ShortcutRecorderButtonStyle(isRecording: isRecording))
        .help(isRecording ? "Press a shortcut, or Esc to cancel" : "Click to change the shortcut")
        .onDisappear(perform: stop)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            stop()
        }
    }

    private var label: String {
        guard isRecording else { return shortcut.displayString }
        return modifierPreview.isEmpty ? "Type shortcut…" : modifierPreview + "…"
    }

    private func toggle() {
        isRecording ? stop() : start()
    }

    private func start() {
        isRecording = true
        modifierPreview = ""
        hint = nil
        onRecordingChanged(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handle(event)
            return nil // swallow the keys while recording
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard isRecording else { return }
        isRecording = false
        modifierPreview = ""
        onRecordingChanged(false)
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .flagsChanged:
            modifierPreview = event.modifierFlags.shortcutSymbols

        case .keyDown:
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isBareEscape = event.keyCode == UInt16(KeyCodes.escape)
                && modifiers.subtracting([.function, .numericPad]).isEmpty
            if isBareEscape {
                stop()
                return
            }

            let candidate = Shortcut(event: event)
            if let rejection = candidate.rejection {
                hint = rejection.message
                modifierPreview = ""
                return // keep listening
            }
            hint = nil
            shortcut = candidate
            stop()

        default:
            break
        }
    }
}

private struct ShortcutRecorderButtonStyle: ButtonStyle {
    let isRecording: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        configuration.label
            .padding(.horizontal, 12)
            .background(shape.fill(isRecording ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.07)))
            .overlay(
                shape.strokeBorder(
                    isRecording ? Color.accentColor : Color.primary.opacity(0.12),
                    lineWidth: isRecording ? 1.5 : 1
                )
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(shape)
    }
}
