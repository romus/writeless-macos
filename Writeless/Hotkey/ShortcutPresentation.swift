import AppKit
import WritelessCore

extension Shortcut {
    /// "⌥⌘Space", with printable keys resolved through the current layout.
    var displayString: String {
        display(keyName: { KeyboardLayout.character(forKeyCode: $0) })
    }

    /// The same shortcut in the form `NSMenuItem` draws itself.
    var menuKeyEquivalent: (key: String, modifiers: NSEvent.ModifierFlags) {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.control) { flags.insert(.control) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        return (menuKeyCharacter, flags)
    }

    private var menuKeyCharacter: String {
        if let number = KeyCodes.functionKeyNumber(keyCode) {
            return String(UnicodeScalar(0xF704 + number - 1) ?? " ")
        }
        switch keyCode {
        case KeyCodes.space: return " "
        case KeyCodes.return: return "\r"
        case KeyCodes.tab: return "\t"
        case KeyCodes.delete: return "\u{8}"
        case KeyCodes.forwardDelete: return "\u{7F}"
        case KeyCodes.escape: return "\u{1B}"
        case 126: return String(UnicodeScalar(NSUpArrowFunctionKey)!)
        case 125: return String(UnicodeScalar(NSDownArrowFunctionKey)!)
        case 123: return String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        case 124: return String(UnicodeScalar(NSRightArrowFunctionKey)!)
        default: return KeyboardLayout.character(forKeyCode: keyCode)?.lowercased() ?? ""
        }
    }

    /// Builds a shortcut from a captured key event.
    init(event: NSEvent) {
        var modifiers: KeyModifiers = []
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }
}

extension NSEvent.ModifierFlags {
    /// Live "⌥⌘…" preview while the user holds modifiers down.
    var shortcutSymbols: String {
        var symbols = ""
        if contains(.control) { symbols += "⌃" }
        if contains(.option) { symbols += "⌥" }
        if contains(.shift) { symbols += "⇧" }
        if contains(.command) { symbols += "⌘" }
        return symbols
    }
}
