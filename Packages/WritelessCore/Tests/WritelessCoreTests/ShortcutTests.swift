import Foundation
import Testing

@testable import WritelessCore

@Suite("Shortcut")
struct ShortcutTests {
    @Test("Default shortcut is ⌥⌘Space, as in the design")
    func defaultShortcut() {
        let shortcut = Shortcut.default
        #expect(shortcut.keyCode == KeyCodes.space)
        #expect(shortcut.modifiers == [.option, .command])
        #expect(shortcut.display(keyName: { _ in nil }) == "⌥⌘Space")
        #expect(shortcut.isValid)
    }

    @Test("Modifier symbols follow the macOS order ⌃⌥⇧⌘")
    func modifierOrder() {
        let all: KeyModifiers = [.command, .shift, .option, .control]
        #expect(all.symbols == "⌃⌥⇧⌘")
    }

    @Test("Printable keys are labelled by the keyboard layout, special keys are not")
    func display() {
        let optionCommandV = Shortcut(keyCode: KeyCodes.v, modifiers: [.option, .command])
        #expect(optionCommandV.display(keyName: { _ in "v" }) == "⌥⌘V")
        #expect(optionCommandV.display(keyName: { _ in nil }) == "⌥⌘Key 9")

        let f8 = Shortcut(keyCode: 100, modifiers: [])
        #expect(f8.display(keyName: { _ in "unused" }) == "F8")

        let escape = Shortcut(keyCode: KeyCodes.escape, modifiers: [.control])
        #expect(escape.display(keyName: { _ in nil }) == "⌃⎋")
    }

    @Test("Bare function keys need no modifier")
    func functionKeys() {
        #expect(Shortcut(keyCode: 100, modifiers: []).isValid)
        #expect(Shortcut(keyCode: 90, modifiers: [.shift]).isValid) // F20
        #expect(Shortcut(keyCode: 122, modifiers: [.option]).isValid) // F1
    }

    @Test(
        "Rejected combinations",
        arguments: [
            // A printable key with no modifier would fire while typing.
            (Shortcut(keyCode: KeyCodes.v, modifiers: []), ShortcutRejection.needsModifier),
            (Shortcut(keyCode: KeyCodes.v, modifiers: [.shift]), .needsModifier),
            // macOS 15 stopped delivering ⌥-only and ⌥⇧-only hotkeys.
            (Shortcut(keyCode: KeyCodes.space, modifiers: [.option]), .optionOnlyIsIgnoredByMacOS),
            (Shortcut(keyCode: KeyCodes.space, modifiers: [.option, .shift]), .optionOnlyIsIgnoredByMacOS),
            // ⌘V everywhere would be a disaster.
            (Shortcut(keyCode: KeyCodes.v, modifiers: [.command]), .commandWithPrintableKey),
            (Shortcut(keyCode: KeyCodes.v, modifiers: [.command, .shift]), .commandWithPrintableKey),
        ]
    )
    func rejections(shortcut: Shortcut, expected: ShortcutRejection) {
        #expect(shortcut.rejection == expected)
        #expect(!shortcut.isValid)
        #expect(!expected.message.isEmpty)
    }

    @Test(
        "Accepted combinations",
        arguments: [
            Shortcut.default,
            Shortcut(keyCode: KeyCodes.space, modifiers: [.control]),
            Shortcut(keyCode: KeyCodes.v, modifiers: [.control, .option]),
            Shortcut(keyCode: KeyCodes.space, modifiers: [.command]), // ⌘Space: taken by Spotlight, but valid
        ]
    )
    func accepted(shortcut: Shortcut) {
        #expect(shortcut.rejection == nil)
    }

    @Test("Modifier bits outside the four are dropped")
    func masking() {
        let noisy = Shortcut(keyCode: KeyCodes.space, modifiers: KeyModifiers(rawValue: 0x0100 | 0x0800 | 0x2000))
        #expect(noisy.modifiers == [.option, .command])
    }

    @Test("Round-trips through JSON for UserDefaults")
    func codable() throws {
        let data = try JSONEncoder().encode(Shortcut.default)
        #expect(try JSONDecoder().decode(Shortcut.self, from: data) == Shortcut.default)
    }
}

@Suite("Shortcut conflicts")
struct ShortcutConflictTests {
    @Test("A shortcut macOS already owns is detected, extra modifier bits and all")
    func systemConflict() {
        // 49 = Space, 0x0100 | 0x0800 = ⌘⌥ — "Show Finder search window" on a stock Mac.
        let finderSearch = SystemHotKey(keyCode: 49, rawModifiers: 0x0100 | 0x0800 | 0x2000)
        #expect(Shortcut.default.isTaken(bySystem: [finderSearch]))
    }

    @Test("Different key or modifiers is not a conflict")
    func noConflict() {
        let spotlight = SystemHotKey(keyCode: 49, rawModifiers: 0x0100)
        #expect(!Shortcut.default.isTaken(bySystem: [spotlight]))
        #expect(!Shortcut.default.isTaken(bySystem: []))
    }

    @Test("Status messages appear only for problems")
    func statusMessages() {
        #expect(HotkeyStatus.active.message == nil)
        #expect(HotkeyStatus.active.isWorking)
        #expect(HotkeyStatus.takenBySystem.message == "Used by a macOS shortcut")
        #expect(HotkeyStatus.takenByAnotherApp.message == "Used by another app")
        #expect(HotkeyStatus.rejected(.needsModifier).message == ShortcutRejection.needsModifier.message)
    }
}
