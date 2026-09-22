import Carbon
import WritelessCore

/// Carbon dispatches hot key events on the main thread, so it is safe to assume
/// main-actor isolation here. The handler has to be a C function pointer, which
/// cannot capture context — hence the `Unmanaged` round trip.
private nonisolated func hotKeyEventHandler(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated { hotkey.fire() }
    return noErr
}

/// The global shortcut. Carbon hot keys need no Accessibility or Input
/// Monitoring permission and swallow the key event, unlike an NSEvent monitor.
final class GlobalHotkey {
    var onFire: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var current: Shortcut?

    // No deinit: a nonisolated deinit cannot touch these Carbon pointers, and
    // cleanup is explicit anyway (`unregister()` from the coordinator).

    @discardableResult
    func register(_ shortcut: Shortcut) -> HotkeyStatus {
        unregisterHotKey()
        current = shortcut

        if let rejection = shortcut.rejection {
            return .rejected(rejection)
        }

        installHandlerIfNeeded()

        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: OSType(0x574C_5353), id: 1) // 'WLSS'
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers.rawValue,
            identifier,
            GetEventDispatcherTarget(),
            0,
            &reference
        )

        guard status == noErr, let reference else {
            Log.hotkey.error("RegisterEventHotKey failed with status \(status, privacy: .public)")
            return .takenByAnotherApp
        }
        hotKeyRef = reference

        // Registration succeeds even when macOS owns the chord, so ask.
        if shortcut.isTaken(bySystem: SystemShortcuts.current()) {
            return .takenBySystem
        }
        return .active
    }

    /// Releases the chord while the user records a new one, so pressing the
    /// current shortcut types it instead of starting a recording.
    func suspend() {
        unregisterHotKey()
    }

    @discardableResult
    func resume() -> HotkeyStatus {
        guard let current else { return .active }
        return register(current)
    }

    func unregister() {
        unregisterHotKey()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        current = nil
    }

    fileprivate func fire() {
        onFire?()
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetEventDispatcherTarget(),
            hotKeyEventHandler,
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
    }

    private func unregisterHotKey() {
        guard let hotKeyRef else { return }
        UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
    }
}
