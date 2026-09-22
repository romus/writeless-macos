import AppKit
import SwiftUI

/// Hosts `SettingsView` in a plain window: an accessory app has no Settings
/// scene worth fighting with.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let preferences: Preferences
    private let state: AppState
    private let actions: SettingsActions
    private var window: NSWindow?

    init(preferences: Preferences, state: AppState, actions: SettingsActions) {
        self.preferences = preferences
        self.state = state
        self.actions = actions
        super.init()
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // The microphone meter only runs while the window is up.
        actions.windowOpened()
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(
            rootView: SettingsView(preferences: preferences, state: state, actions: actions)
        )
        hosting.sizingOptions = [.preferredContentSize]

        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.title = "Write Less"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    func windowWillClose(_ notification: Notification) {
        actions.windowClosed()
        // Give focus back to whatever the user was working in. Without this the
        // app stays active with no windows, and the user's own ⌘V lands nowhere.
        NSApp.hide(nil)
    }
}
