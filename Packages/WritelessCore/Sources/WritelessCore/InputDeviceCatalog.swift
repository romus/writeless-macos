import Foundation

/// A microphone the system is offering, as Settings and the recorder see it.
///
/// Identified by its CoreAudio UID rather than its `AudioDeviceID`: the numeric
/// id is handed out afresh every time a device reconnects, so a remembered pair
/// of AirPods would come back as somebody else's microphone. The name travels
/// with the uid so a device that is currently away can still be named in the
/// picker instead of rendering as a blank row.
public struct InputDevice: Sendable, Hashable, Identifiable, Codable {
    public let uid: String
    public let name: String

    public var id: String { uid }

    public init(uid: String, name: String) {
        self.uid = uid
        self.name = name
    }
}

/// One row of the microphone picker.
public struct InputDeviceEntry: Sendable, Hashable, Identifiable {
    public let uid: String
    public let title: String
    /// False for the remembered choice while it is unplugged. Still selectable:
    /// picking it means "use this one once it is back".
    public let isAvailable: Bool

    public var id: String { uid }

    public init(uid: String, title: String, isAvailable: Bool) {
        self.uid = uid
        self.title = title
        self.isAvailable = isAvailable
    }
}

/// Resolves the stored microphone preference against whatever is plugged in
/// right now. Nothing here talks to CoreAudio — `AudioDevices` does that, and
/// hands the result in.
public enum InputDeviceCatalog {
    /// "Follow the system input", the same sentinel idea as
    /// `LanguageCatalog.automaticCode`.
    public static let systemDefaultUID = ""
    public static let systemDefaultName = "System Default"

    /// CoreAudio happily lists the same microphone twice: a Continuity Camera
    /// that reconnected leaves its previous registration behind, alive and
    /// identical but for its uid. Two rows the user cannot tell apart are not
    /// two choices, so the first of each name wins.
    public static func deduplicated(_ devices: [InputDevice]) -> [InputDevice] {
        var seen = Set<String>()
        return devices.filter { seen.insert($0.name).inserted }
    }

    /// Turns a uid the picker just produced back into a device to store.
    public static func device(
        forUID uid: String,
        available: [InputDevice],
        remembered: InputDevice?
    ) -> InputDevice? {
        guard uid != systemDefaultUID else { return nil }
        if let live = available.first(where: { $0.uid == uid }) { return live }
        // Re-picking the row for a device that is away keeps its name.
        if let remembered, remembered.uid == uid { return remembered }
        return nil
    }

    /// Everything connected, plus the remembered choice when it is currently
    /// away, so the selection never renders blank. The "System Default" row is
    /// the view's, exactly as "Automatic" is in the language picker.
    public static func deviceEntries(selected: InputDevice?, available: [InputDevice]) -> [InputDeviceEntry] {
        var entries = available.map {
            InputDeviceEntry(uid: $0.uid, title: $0.name, isAvailable: true)
        }
        if let selected,
           selected.uid != systemDefaultUID,
           !available.contains(where: { $0.uid == selected.uid }) {
            entries.append(
                InputDeviceEntry(
                    uid: selected.uid,
                    title: "\(selected.name) (not connected)",
                    isAvailable: false
                )
            )
        }
        return entries
    }
}
