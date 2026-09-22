import Carbon
import WritelessCore

/// The shortcuts macOS has claimed for itself.
///
/// `RegisterEventHotKey` happily reports success for these and then never
/// fires, because the system handles the chord first — so this list is the only
/// way to notice, and ⌥⌘Space is "Show Finder search window" out of the box.
enum SystemShortcuts {
    static func current() -> [SystemHotKey] {
        var out: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&out) == noErr,
              let entries = out?.takeRetainedValue() as? [[String: Any]]
        else {
            return []
        }

        // The kHISymbolicHotKey* constants are CFSTR macros that Swift doesn't
        // import, so the keys are spelled out.
        return entries.compactMap { entry in
            guard entry["kHISymbolicHotKeyEnabled"] as? Bool == true,
                  let keyCode = entry["kHISymbolicHotKeyCode"] as? Int,
                  let modifiers = entry["kHISymbolicHotKeyModifiers"] as? Int
            else {
                return nil
            }
            return SystemHotKey(keyCode: UInt32(keyCode), rawModifiers: UInt32(modifiers))
        }
    }
}
