import AppKit
import Observation
import WritelessCore

enum AppearancePreference: String, CaseIterable, Identifiable, Sendable {
    case light, dark, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .system: "System"
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        case .system: nil
        }
    }

    func apply() {
        NSApp.appearance = appearance
    }
}

/// User settings, stored in UserDefaults. "Launch at login" is deliberately not
/// here: `SMAppService` is the source of truth for it.
@Observable
final class Preferences {
    private enum Key {
        static let shortcut = "shortcut"
        static let model = "model"
        static let language = "language"
        static let inputDevice = "inputDevice"
        static let soundOnFinish = "soundOnFinish"
        static let appearance = "appearance"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var shortcut: Shortcut {
        didSet { defaults.set(try? JSONEncoder().encode(shortcut), forKey: Key.shortcut) }
    }

    var modelID: String {
        didSet { defaults.set(modelID, forKey: Key.model) }
    }

    var languageCode: String {
        didSet { defaults.set(languageCode, forKey: Key.language) }
    }

    /// The chosen microphone, or `nil` to follow the system input. Stored whole
    /// rather than by uid alone, so a device that is currently away can still
    /// be named in the picker instead of showing as a blank row.
    var inputDevice: InputDevice? {
        didSet {
            defaults.set(inputDevice.flatMap { try? JSONEncoder().encode($0) }, forKey: Key.inputDevice)
        }
    }

    var soundOnFinish: Bool {
        didSet { defaults.set(soundOnFinish, forKey: Key.soundOnFinish) }
    }

    var appearance: AppearancePreference {
        didSet {
            defaults.set(appearance.rawValue, forKey: Key.appearance)
            appearance.apply()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedShortcut = (defaults.data(forKey: Key.shortcut))
            .flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) }
        shortcut = storedShortcut ?? .default
        modelID = WhisperModelCatalog.model(forPreference: defaults.string(forKey: Key.model)).id
        languageCode = defaults.string(forKey: Key.language) ?? LanguageCatalog.automaticCode
        inputDevice = (defaults.data(forKey: Key.inputDevice))
            .flatMap { try? JSONDecoder().decode(InputDevice.self, from: $0) }
        soundOnFinish = defaults.object(forKey: Key.soundOnFinish) as? Bool ?? true
        appearance = defaults.string(forKey: Key.appearance)
            .flatMap(AppearancePreference.init(rawValue:)) ?? .system
    }

    var model: WhisperModel { WhisperModelCatalog.model(forPreference: modelID) }

    /// The value handed to WhisperKit: `nil` asks it to detect the language.
    var decodingLanguage: String? { LanguageCatalog.decodingLanguage(forPreference: languageCode) }
}
