import AppKit

/// The floating capsule at the bottom of the screen.
///
/// It must never take focus: the whole point is that the user keeps typing (and
/// keeps their insertion point) in another app while dictating.
final class PillPanel: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 90),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        isFloatingPanel = true
        level = .statusBar
        hidesOnDeactivate = false // NSPanel defaults to true
        canHide = false // stays put when the app hides itself after Settings closes
        ignoresMouseEvents = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false // SwiftUI draws the capsule's shadow
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        self.contentView = contentView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
