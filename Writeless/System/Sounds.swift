import AppKit

enum Sounds {
    /// Reused so repeated dictations don't stack sounds; `NSSound.play()` is a
    /// no-op while the same instance is still playing, hence the `stop()`.
    private static let finished = NSSound(named: "Glass")

    static func playFinished() {
        guard let finished else { return }
        finished.stop()
        finished.play()
    }

    static func beep() {
        NSSound.beep()
    }
}
