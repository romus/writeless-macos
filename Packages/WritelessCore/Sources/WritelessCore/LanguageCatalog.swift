import Foundation

/// A language Whisper can be pinned to. Names are English, matching the rest of
/// the UI; the codes are the ones WhisperKit accepts in `DecodingOptions.language`.
public struct WhisperLanguage: Sendable, Hashable, Identifiable, Codable {
    public let code: String
    public let name: String

    public var id: String { code }

    public init(code: String, name: String) {
        self.code = code
        self.name = name
    }
}

public enum LanguageCatalog {
    /// Stored preference value for automatic detection.
    public static let automaticCode = "auto"

    /// Every language Whisper supports, sorted by name. Aliases (mandarin,
    /// castilian, flemish, …) collapse into their primary name.
    public static let all: [WhisperLanguage] = [
        WhisperLanguage(code: "af", name: "Afrikaans"),
        WhisperLanguage(code: "sq", name: "Albanian"),
        WhisperLanguage(code: "am", name: "Amharic"),
        WhisperLanguage(code: "ar", name: "Arabic"),
        WhisperLanguage(code: "hy", name: "Armenian"),
        WhisperLanguage(code: "as", name: "Assamese"),
        WhisperLanguage(code: "az", name: "Azerbaijani"),
        WhisperLanguage(code: "ba", name: "Bashkir"),
        WhisperLanguage(code: "eu", name: "Basque"),
        WhisperLanguage(code: "be", name: "Belarusian"),
        WhisperLanguage(code: "bn", name: "Bengali"),
        WhisperLanguage(code: "bs", name: "Bosnian"),
        WhisperLanguage(code: "br", name: "Breton"),
        WhisperLanguage(code: "bg", name: "Bulgarian"),
        WhisperLanguage(code: "yue", name: "Cantonese"),
        WhisperLanguage(code: "ca", name: "Catalan"),
        WhisperLanguage(code: "zh", name: "Chinese"),
        WhisperLanguage(code: "hr", name: "Croatian"),
        WhisperLanguage(code: "cs", name: "Czech"),
        WhisperLanguage(code: "da", name: "Danish"),
        WhisperLanguage(code: "nl", name: "Dutch"),
        WhisperLanguage(code: "en", name: "English"),
        WhisperLanguage(code: "et", name: "Estonian"),
        WhisperLanguage(code: "fo", name: "Faroese"),
        WhisperLanguage(code: "fi", name: "Finnish"),
        WhisperLanguage(code: "fr", name: "French"),
        WhisperLanguage(code: "gl", name: "Galician"),
        WhisperLanguage(code: "ka", name: "Georgian"),
        WhisperLanguage(code: "de", name: "German"),
        WhisperLanguage(code: "el", name: "Greek"),
        WhisperLanguage(code: "gu", name: "Gujarati"),
        WhisperLanguage(code: "ht", name: "Haitian Creole"),
        WhisperLanguage(code: "ha", name: "Hausa"),
        WhisperLanguage(code: "haw", name: "Hawaiian"),
        WhisperLanguage(code: "he", name: "Hebrew"),
        WhisperLanguage(code: "hi", name: "Hindi"),
        WhisperLanguage(code: "hu", name: "Hungarian"),
        WhisperLanguage(code: "is", name: "Icelandic"),
        WhisperLanguage(code: "id", name: "Indonesian"),
        WhisperLanguage(code: "it", name: "Italian"),
        WhisperLanguage(code: "ja", name: "Japanese"),
        WhisperLanguage(code: "jw", name: "Javanese"),
        WhisperLanguage(code: "kn", name: "Kannada"),
        WhisperLanguage(code: "kk", name: "Kazakh"),
        WhisperLanguage(code: "km", name: "Khmer"),
        WhisperLanguage(code: "ko", name: "Korean"),
        WhisperLanguage(code: "lo", name: "Lao"),
        WhisperLanguage(code: "la", name: "Latin"),
        WhisperLanguage(code: "lv", name: "Latvian"),
        WhisperLanguage(code: "ln", name: "Lingala"),
        WhisperLanguage(code: "lt", name: "Lithuanian"),
        WhisperLanguage(code: "lb", name: "Luxembourgish"),
        WhisperLanguage(code: "mk", name: "Macedonian"),
        WhisperLanguage(code: "mg", name: "Malagasy"),
        WhisperLanguage(code: "ms", name: "Malay"),
        WhisperLanguage(code: "ml", name: "Malayalam"),
        WhisperLanguage(code: "mt", name: "Maltese"),
        WhisperLanguage(code: "mi", name: "Maori"),
        WhisperLanguage(code: "mr", name: "Marathi"),
        WhisperLanguage(code: "mn", name: "Mongolian"),
        WhisperLanguage(code: "my", name: "Myanmar"),
        WhisperLanguage(code: "ne", name: "Nepali"),
        WhisperLanguage(code: "no", name: "Norwegian"),
        WhisperLanguage(code: "nn", name: "Nynorsk"),
        WhisperLanguage(code: "oc", name: "Occitan"),
        WhisperLanguage(code: "ps", name: "Pashto"),
        WhisperLanguage(code: "fa", name: "Persian"),
        WhisperLanguage(code: "pl", name: "Polish"),
        WhisperLanguage(code: "pt", name: "Portuguese"),
        WhisperLanguage(code: "pa", name: "Punjabi"),
        WhisperLanguage(code: "ro", name: "Romanian"),
        WhisperLanguage(code: "ru", name: "Russian"),
        WhisperLanguage(code: "sa", name: "Sanskrit"),
        WhisperLanguage(code: "sr", name: "Serbian"),
        WhisperLanguage(code: "sn", name: "Shona"),
        WhisperLanguage(code: "sd", name: "Sindhi"),
        WhisperLanguage(code: "si", name: "Sinhala"),
        WhisperLanguage(code: "sk", name: "Slovak"),
        WhisperLanguage(code: "sl", name: "Slovenian"),
        WhisperLanguage(code: "so", name: "Somali"),
        WhisperLanguage(code: "es", name: "Spanish"),
        WhisperLanguage(code: "su", name: "Sundanese"),
        WhisperLanguage(code: "sw", name: "Swahili"),
        WhisperLanguage(code: "sv", name: "Swedish"),
        WhisperLanguage(code: "tl", name: "Tagalog"),
        WhisperLanguage(code: "tg", name: "Tajik"),
        WhisperLanguage(code: "ta", name: "Tamil"),
        WhisperLanguage(code: "tt", name: "Tatar"),
        WhisperLanguage(code: "te", name: "Telugu"),
        WhisperLanguage(code: "th", name: "Thai"),
        WhisperLanguage(code: "bo", name: "Tibetan"),
        WhisperLanguage(code: "tr", name: "Turkish"),
        WhisperLanguage(code: "tk", name: "Turkmen"),
        WhisperLanguage(code: "uk", name: "Ukrainian"),
        WhisperLanguage(code: "ur", name: "Urdu"),
        WhisperLanguage(code: "uz", name: "Uzbek"),
        WhisperLanguage(code: "vi", name: "Vietnamese"),
        WhisperLanguage(code: "cy", name: "Welsh"),
        WhisperLanguage(code: "yi", name: "Yiddish"),
        WhisperLanguage(code: "yo", name: "Yoruba"),
    ]

    public static func language(code: String) -> WhisperLanguage? {
        all.first { $0.code == code }
    }

    /// The value handed to WhisperKit: `nil` means "detect the language".
    public static func decodingLanguage(forPreference preference: String?) -> String? {
        guard let preference, preference != automaticCode, language(code: preference) != nil else {
            return nil
        }
        return preference
    }

    /// Label for the Language popup.
    public static func displayName(forPreference preference: String?) -> String {
        guard let code = decodingLanguage(forPreference: preference) else { return "Automatic" }
        return language(code: code)?.name ?? "Automatic"
    }
}
