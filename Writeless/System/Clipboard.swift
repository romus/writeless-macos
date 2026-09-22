import AppKit

/// Where a transcript ends up, and where it stops.
///
/// Write Less used to synthesize ⌘V into the focused app. That needed the
/// Accessibility permission, was swallowed by password fields and Terminal's
/// Secure Keyboard Entry anyway, and — because nothing records which app the
/// recording started in — dropped the text into whatever had focus a moment
/// later, mid-sentence. Pressing ⌘V is the user's call.
enum Clipboard {
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
