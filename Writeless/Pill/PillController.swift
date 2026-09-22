import AppKit
import SwiftUI

/// Shows and places the recording pill. The panel holds a transparent canvas
/// wider than the capsule, so SwiftUI can resize the capsule (a notice is
/// wider than a timer) without the window ever being resized or repositioned.
final class PillController {
    private let state: AppState
    private var panel: PillPanel?

    init(state: AppState) {
        self.state = state
    }

    func refresh() {
        state.isPillVisible ? show() : hide()
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel)
        if !panel.isVisible {
            // Never makeKey: that would steal focus from the app being dictated into.
            panel.orderFrontRegardless()
        }
    }

    private func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> PillPanel {
        let hosting = NSHostingView(rootView: PillCanvas(state: state))
        hosting.frame = NSRect(x: 0, y: 0, width: 460, height: 90)
        hosting.autoresizingMask = [.width, .height]
        return PillPanel(contentView: hosting)
    }

    private func position(_ panel: PillPanel) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(
            NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.minY + 24
            )
        )
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
