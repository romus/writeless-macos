import Foundation

/// Carbon modifier flags, redeclared so this package stays free of system
/// framework imports. Values match `cmdKey`, `shiftKey`, `optionKey`, `controlKey`.
public struct KeyModifiers: OptionSet, Sendable, Hashable, Codable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let command = KeyModifiers(rawValue: 0x0100)
    public static let shift = KeyModifiers(rawValue: 0x0200)
    public static let option = KeyModifiers(rawValue: 0x0800)
    public static let control = KeyModifiers(rawValue: 0x1000)

    /// The four modifiers a global hotkey may use; other bits are ignored.
    public static let all: KeyModifiers = [.control, .option, .shift, .command]

    /// Symbols in the order macOS draws them.
    public var symbols: String {
        var result = ""
        if contains(.control) { result += "⌃" }
        if contains(.option) { result += "⌥" }
        if contains(.shift) { result += "⇧" }
        if contains(.command) { result += "⌘" }
        return result
    }
}

/// A global keyboard shortcut: a virtual key code plus Carbon modifier flags.
public struct Shortcut: Sendable, Hashable, Codable {
    public var keyCode: UInt32
    public var modifiers: KeyModifiers

    public init(keyCode: UInt32, modifiers: KeyModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(.all)
    }

    /// ⌥⌘Space, as in the design.
    public static let `default` = Shortcut(keyCode: KeyCodes.space, modifiers: [.option, .command])

    public var isFunctionKey: Bool { KeyCodes.functionKeyNumber(keyCode) != nil }

    /// Keys whose label depends on the keyboard layout (letters, digits, punctuation).
    public var isPrintableKey: Bool { KeyCodes.specialKeyName(keyCode) == nil && !isFunctionKey }

    /// "⌥⌘Space". Printable keys are resolved through `keyName`, which the app
    /// backs with the current ASCII-capable keyboard layout.
    public func display(keyName: (UInt32) -> String?) -> String {
        let key = KeyCodes.specialKeyName(keyCode)
            ?? keyName(keyCode)?.uppercased()
            ?? "Key \(keyCode)"
        return modifiers.symbols + key
    }
}

/// Why a shortcut cannot be used as a global hotkey.
public enum ShortcutRejection: Sendable, Hashable {
    /// No modifier at all (allowed only for F1–F20).
    case needsModifier
    /// Since macOS 15, `RegisterEventHotKey` never fires for ⌥-only and ⌥⇧-only chords.
    case optionOnlyIsIgnoredByMacOS
    /// ⌘ with a printable key would shadow ⌘C, ⌘V and friends everywhere.
    case commandWithPrintableKey

    public var message: String {
        switch self {
        case .needsModifier, .commandWithPrintableKey:
            "Add ⌥ or ⌃ to the shortcut"
        case .optionOnlyIsIgnoredByMacOS:
            "macOS ignores ⌥-only shortcuts — add ⌘ or ⌃"
        }
    }
}

public extension Shortcut {
    /// `nil` when the shortcut can be registered.
    var rejection: ShortcutRejection? {
        if isFunctionKey { return nil }

        let mods = modifiers.intersection(.all)
        if mods.isEmpty || mods == .shift { return .needsModifier }

        let withoutShift = mods.subtracting(.shift)
        if withoutShift == .option { return .optionOnlyIsIgnoredByMacOS }
        if withoutShift == .command, isPrintableKey { return .commandWithPrintableKey }
        return nil
    }

    var isValid: Bool { rejection == nil }
}
