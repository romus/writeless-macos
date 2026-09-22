import Foundation

/// Tidies Whisper output and drops the phrases it invents when it hears almost
/// nothing. The energy gate in `SpeechGate` catches silence; this catches the
/// leftovers, such as a cough turning into "Thank you." or a YouTube credit.
public enum TranscriptCleaner {
    /// Hallucinations are only dropped when they are the entire result and the
    /// recording held less speech than this.
    public static let shortSpeechSeconds: Double = 2.0

    private static let hallucinations: Set<String> = [
        "thank you",
        "thank you.",
        "thanks for watching",
        "thanks for watching!",
        "thank you for watching",
        "thank you for watching!",
        "you",
        "bye",
        "bye.",
        "продолжение следует",
        "продолжение следует...",
        "спасибо за просмотр",
        "спасибо за просмотр!",
        "субтитры сделал dimatorzok",
        "субтитры создавал dimatorzok",
        "редактор субтитров а.семкин корректор а.егорова",
    ]

    /// True when the text is nothing but bracketed annotations, such as
    /// `[BLANK_AUDIO]` or `(soft music)`, however many of them.
    private static func isOnlyAnnotations(_ text: String) -> Bool {
        var remainder = ""
        var depth = 0
        for character in text {
            switch character {
            case "[", "(": depth += 1
            case "]", ")": depth = max(0, depth - 1)
            default: if depth == 0 { remainder.append(character) }
            }
        }
        return remainder.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public static func clean(_ raw: String, speechSeconds: Double) -> String {
        let collapsed = raw
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !collapsed.isEmpty else { return "" }
        if isOnlyAnnotations(collapsed) { return "" }

        let normalized = collapsed
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: " \"'«»„“”"))
        if speechSeconds < shortSpeechSeconds, hallucinations.contains(normalized) { return "" }

        return collapsed
    }
}
