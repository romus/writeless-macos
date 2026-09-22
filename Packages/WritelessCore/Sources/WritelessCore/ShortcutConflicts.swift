import Foundation

/// A shortcut macOS itself has claimed, as reported by `CopySymbolicHotKeys`.
public struct SystemHotKey: Sendable, Hashable {
    public let keyCode: UInt32
    public let modifiers: KeyModifiers

    /// `rawModifiers` comes straight from HIToolbox and can carry bits we don't
    /// care about (device-side modifiers), so it is masked down to the four.
    public init(keyCode: UInt32, rawModifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = KeyModifiers(rawValue: rawModifiers).intersection(.all)
    }
}

/// What happened when the app tried to own its shortcut.
///
/// `RegisterEventHotKey` succeeds even for chords macOS has claimed (⌥⌘Space is
/// "Show Finder search window" on a stock system) and the system wins, so a
/// successful registration is not proof that the hotkey will ever fire.
public enum HotkeyStatus: Sendable, Hashable {
    case active
    case takenBySystem
    case takenByAnotherApp
    case rejected(ShortcutRejection)

    public var isWorking: Bool { self == .active }

    /// Subtitle for the Shortcut row in Settings; `nil` while everything works.
    public var message: String? {
        switch self {
        case .active: nil
        case .takenBySystem: "Used by a macOS shortcut"
        case .takenByAnotherApp: "Used by another app"
        case .rejected(let rejection): rejection.message
        }
    }
}

public extension Shortcut {
    func isTaken(bySystem hotKeys: [SystemHotKey]) -> Bool {
        hotKeys.contains { $0.keyCode == keyCode && $0.modifiers == modifiers.intersection(.all) }
    }
}
