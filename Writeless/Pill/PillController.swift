import AppKit
import SwiftUI

/// Shows and places the recording pill. The panel holds a transparent canvas
/// wider than the capsule, so SwiftUI can resize the capsule (a notice is
/// wider than a timer) without the window ever being resized or repositioned.
final class PillController {
    private let state: AppState
    private var panel: PillPanel?
    private var occlusionObserver: NSObjectProtocol?

    init(state: AppState) {
        self.state = state
    }

    /// Runs on every tick while recording, so it acts only when the pill has
    /// to appear or go: a pill that is already up stays where it was placed
    /// instead of chasing the pointer from display to display.
    func refresh() {
        guard state.isPillVisible else { return hide() }
        let panel = panel ?? makePanel()
        self.panel = panel
        if !panel.isVisible { present(panel) }
    }

    /// The displays or the active Space changed under a visible pill, so it is
    /// placed and ordered in again, on whatever the user is looking at now.
    func reattach() {
        guard state.isPillVisible, let panel else { return }
        present(panel)
    }

    func close() {
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
            self.occlusionObserver = nil
        }
        panel?.orderOut(nil)
        panel = nil
    }

    private func present(_ panel: PillPanel) {
        let screen = position(panel)
        // Never makeKey: that would steal focus from the app being dictated into.
        panel.orderFrontRegardless()

        let screenName = screen?.localizedName ?? "no screen"
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nothing"
        let isAppHidden = NSApp.isHidden
        Log.pill.info("Shown on \(screenName, privacy: .public) over \(frontmost, privacy: .public), app hidden: \(isAppHidden, privacy: .public)")
    }

    private func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> PillPanel {
        let hosting = NSHostingView(rootView: PillCanvas(state: state))
        hosting.frame = NSRect(x: 0, y: 0, width: 460, height: 90)
        hosting.autoresizingMask = [.width, .height]
        let panel = PillPanel(contentView: hosting)

        // Ordered in is not the same as on screen: a full-screen Space can
        // refuse the panel, and only the window server knows it did.
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: panel, queue: .main
        ) { [weak panel] _ in
            MainActor.assumeIsolated {
                guard let panel, panel.isVisible else { return }
                let isOnScreen = panel.occlusionState.contains(.visible)
                let isOnActiveSpace = panel.isOnActiveSpace
                Log.pill.info("On screen: \(isOnScreen, privacy: .public), on the active Space: \(isOnActiveSpace, privacy: .public)")
            }
        }
        return panel
    }

    @discardableResult
    private func position(_ panel: PillPanel) -> NSScreen? {
        // NSMouseInRect, not NSRect.contains: the pointer's top row lies on the
        // screen's maxY, which contains() leaves out, and the top edge is where
        // the pointer sits to reveal the menu bar over a full-screen app.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        guard let screen else { return nil }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(
            NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.minY + 24
            )
        )
        return screen
    }
}

/// Centres the capsule in the panel's transparent canvas.
private struct PillCanvas: View {
    let state: AppState

    var body: some View {
        PillView(state: state)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}
