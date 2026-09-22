import Carbon
import Foundation

/// Key labels from the current ASCII-capable keyboard layout, so a Russian or
/// Dvorak layout still shows the right key.
///
/// Main thread only: Text Input Services crashes when called from elsewhere,
/// which is exactly how the Python version used to die on macOS 26.
enum KeyboardLayout {
    /// The character a key produces with no modifiers, e.g. 9 → "v".
    static func character(forKeyCode keyCode: UInt32) -> String? {
        guard let layout = currentLayoutData() else { return nil }
        return character(forKeyCode: keyCode, layout: layout)
    }

    private static func character(forKeyCode keyCode: UInt32, layout: Data) -> String? {
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 8)
        var length = 0

        let status = layout.withUnsafeBytes { raw -> OSStatus in
            guard let pointer = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(
                pointer,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
        }

        guard status == noErr, length > 0 else { return nil }
        let text = String(utf16CodeUnits: characters, count: length)
        return text.isEmpty ? nil : text
    }

    private static func currentLayoutData() -> Data? {
        guard
            let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
            let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else {
            return nil
        }
        return Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
    }
}
