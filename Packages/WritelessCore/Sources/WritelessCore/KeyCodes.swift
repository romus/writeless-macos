import Foundation

/// Virtual key codes and the labels macOS uses for keys that don't depend on
/// the keyboard layout.
public enum KeyCodes {
    public static let space: UInt32 = 49
    public static let escape: UInt32 = 53
    public static let `return`: UInt32 = 36
    public static let tab: UInt32 = 48
    public static let delete: UInt32 = 51
    public static let forwardDelete: UInt32 = 117
    public static let v: UInt32 = 9

    /// Key code → F-number, for F1 through F20.
    private static let functionKeys: [UInt32: Int] = [
        122: 1, 120: 2, 99: 3, 118: 4, 96: 5, 97: 6, 98: 7, 100: 8, 101: 9, 109: 10,
        103: 11, 111: 12, 105: 13, 107: 14, 113: 15, 106: 16, 64: 17, 79: 18, 80: 19, 90: 20,
    ]

    private static let specialKeyNames: [UInt32: String] = [
        49: "Space",
        36: "↩",
        76: "⌅", // keypad enter
        48: "⇥",
        51: "⌫",
        117: "⌦",
        53: "⎋",
        126: "↑",
        125: "↓",
        123: "←",
        124: "→",
        116: "⇞",
        121: "⇟",
        115: "↖",
        119: "↘",
        71: "⌧", // clear
    ]

    public static func functionKeyNumber(_ keyCode: UInt32) -> Int? { functionKeys[keyCode] }

    /// Layout-independent label, or `nil` for printable keys.
    public static func specialKeyName(_ keyCode: UInt32) -> String? {
        if let number = functionKeys[keyCode] { return "F\(number)" }
        return specialKeyNames[keyCode]
    }
}
