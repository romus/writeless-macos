import CoreAudio
import Foundation
import WritelessCore

/// The CoreAudio half of choosing a microphone. Everything that talks to the
/// HAL lives here so `InputDeviceCatalog` can stay pure and unit-tested.
///
/// `nonisolated` for the same reason `AudioRecorder` is: the recorder resolves a
/// device on its own queue, and the property listeners fire on a HAL thread.
nonisolated enum AudioDevices {
    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    /// Every device that can record, in the order CoreAudio lists them.
    static func inputs() -> [InputDevice] {
        var seen = Set<String>()
        return deviceIDs().compactMap { id -> InputDevice? in
            guard hasInputChannels(id) else { return nil }
            guard
                let uid = string(id, kAudioDevicePropertyDeviceUID), !uid.isEmpty,
                let name = string(id, kAudioObjectPropertyName), !name.isEmpty
            else { return nil }
            // A Continuity Camera can show up on more than one HAL object.
            guard seen.insert(uid).inserted else { return nil }
            return InputDevice(uid: uid, name: name)
        }
    }

    static func defaultInputID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = globalAddress(kAudioHardwarePropertyDefaultInputDevice)
        let status = AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &deviceID)
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    /// A uid survives a reconnect; the numeric id does not, so it is always
    /// looked up again rather than remembered.
    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        var address = globalAddress(kAudioHardwarePropertyTranslateUIDToDevice)
        var cfUID = uid as CFString
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) { uidPointer in
            AudioObjectGetPropertyData(
                systemObject, &address,
                UInt32(MemoryLayout<CFString>.size), uidPointer,
                &size, &deviceID
            )
        }
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    // MARK: - Watching

    /// Holds the block CoreAudio was given, because removing a listener needs
    /// the very same block back.
    final class Listener: @unchecked Sendable {
        fileprivate let block: AudioObjectPropertyListenerBlock
        fileprivate let selectors: [AudioObjectPropertySelector]

        fileprivate init(block: @escaping AudioObjectPropertyListenerBlock, selectors: [AudioObjectPropertySelector]) {
            self.block = block
            self.selectors = selectors
        }
    }

    /// Fires when devices appear or disappear, and when the system input
    /// changes — both matter: one changes the list, the other changes what
    /// "System Default" means.
    static func addListener(queue: DispatchQueue, onChange: @escaping @Sendable () -> Void) -> Listener {
        let block: AudioObjectPropertyListenerBlock = { _, _ in onChange() }
        let selectors = [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice]
        for selector in selectors {
            var address = globalAddress(selector)
            let status = AudioObjectAddPropertyListenerBlock(systemObject, &address, queue, block)
            if status != noErr {
                Log.audio.error("Could not watch audio devices: \(status, privacy: .public)")
            }
        }
        return Listener(block: block, selectors: selectors)
    }

    static func removeListener(_ listener: Listener) {
        for selector in listener.selectors {
            var address = globalAddress(selector)
            AudioObjectRemovePropertyListenerBlock(systemObject, &address, nil, listener.block)
        }
    }

    // MARK: - HAL plumbing

    private static func globalAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func deviceIDs() -> [AudioDeviceID] {
        var address = globalAddress(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }

        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    /// The only honest test of "can this record": an output-only device answers
    /// the input scope with zero buffers.
    private static func hasInputChannels(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return false }

        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, buffer) == noErr else { return false }

        let list = UnsafeMutableAudioBufferListPointer(buffer.assumingMemoryBound(to: AudioBufferList.self))
        return list.contains { $0.mNumberChannels > 0 }
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = globalAddress(selector)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString?
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let value else { return nil }
        return value as String
    }
}
