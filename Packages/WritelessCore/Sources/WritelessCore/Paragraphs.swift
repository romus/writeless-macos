import Foundation
import NaturalLanguage

/// Cuts a cleaned transcript into sentences for the paragraph step. Whisper
/// punctuates, so the tokenizer has something to work with; a piece it cuts
/// off after an abbreviation ("e.g.", "etc.") is glued back onto the sentence
/// before it, because a real sentence starts with a capital or a digit.
public enum SentenceSplitter {
    public static func split(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var pieces: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let piece = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { pieces.append(piece) }
            return true
        }

        var sentences: [String] = []
        for piece in pieces {
            if let last = sentences.last, !startsSentence(piece) {
                sentences[sentences.count - 1] = last + " " + piece
            } else {
                sentences.append(piece)
            }
        }
        return sentences
    }

    /// True unless the first letter is lowercase. Quotes and dashes before it
    /// are skipped; scripts without case count as a start.
    private static func startsSentence(_ piece: String) -> Bool {
        for scalar in piece.unicodeScalars {
            if CharacterSet.lowercaseLetters.contains(scalar) { return false }
            if CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) { return true }
        }
        return true
    }
}

/// How many sentences go to the model at once. Its judgement collapses on a
/// long list (48 sentences came back as 31 paragraphs), so the transcript is
/// cut into windows of roughly equal size, none longer than `maxSentences`.
public enum ParagraphWindows {
    public static let maxSentences = 14

    public static func make(count: Int, maxSentences: Int = maxSentences) -> [Range<Int>] {
        guard count > 0, maxSentences > 0 else { return [] }
        let windows = (count + maxSentences - 1) / maxSentences
        let base = count / windows
        let extra = count % windows
        var ranges: [Range<Int>] = []
        var start = 0
        for index in 0..<windows {
            let length = base + (index < extra ? 1 : 0)
            ranges.append(start..<(start + length))
            start += length
        }
        return ranges
    }
}

/// Rebuilds the transcript from its sentences and the model's answer. The
/// model only ever names sentence numbers, so the words on the clipboard are
/// exactly the words Whisper produced; this is where that guarantee lives.
public enum ParagraphLayout {
    /// Below either of these there is nothing to split, and the model is not asked.
    public static let minimumSentences = 3
    public static let minimumWords = 40
    /// A paragraph shorter than this is glued to its neighbour: the model
    /// likes to give a short closing remark a paragraph of its own.
    public static let minimumParagraphWords = 12

    public static func isWorthSplitting(_ sentences: [String]) -> Bool {
        sentences.count >= minimumSentences && wordCount(sentences) >= minimumWords
    }

    public static func wordCount(_ sentences: [String]) -> Int {
        sentences.reduce(0) { $0 + $1.split(whereSeparator: \.isWhitespace).count }
    }

    /// `starts` are 1-based sentence numbers that begin a paragraph, as the
    /// model returns them. Repeats and numbers out of range are ignored, and
    /// the first sentence always begins a paragraph.
    public static func apply(
        starts: [Int],
        to sentences: [String],
        minimumParagraphWords: Int = minimumParagraphWords
    ) -> String {
        guard !sentences.isEmpty else { return "" }
        let valid = Set(starts.filter { (1...sentences.count).contains($0) }).union([1])

        var paragraphs: [[String]] = []
        for (index, sentence) in sentences.enumerated() {
            if valid.contains(index + 1) {
                paragraphs.append([sentence])
            } else {
                paragraphs[paragraphs.count - 1].append(sentence)
            }
        }

        var merged: [[String]] = []
        for paragraph in paragraphs {
            if !merged.isEmpty, wordCount(paragraph) < minimumParagraphWords {
                merged[merged.count - 1] += paragraph
            } else {
                merged.append(paragraph)
            }
        }
        if merged.count > 1, wordCount(merged[0]) < minimumParagraphWords {
            merged[1] = merged[0] + merged[1]
            merged.removeFirst()
        }

        return merged
            .map { $0.joined(separator: " ") }
            .joined(separator: "\n\n")
    }
}

/// Whether the Paragraphs row can be used, and what it says when it cannot.
/// The row is hidden on a Mac that can never run Apple Intelligence; for the
/// other two reasons it names the one thing that fixes it.
public enum ParagraphsAvailability: Equatable, Sendable {
    case available
    /// Eligible Mac, Apple Intelligence switched off in System Settings.
    case turnedOff
    /// Switched on, model still arriving.
    case downloading
    /// Intel, macOS older than 26, or any reason the framework may add.
    case unsupported

    public var showsRow: Bool { self != .unsupported }
    public var canToggle: Bool { self == .available }

    public func subtitle(isOn: Bool) -> String {
        switch self {
        case .available: isOn ? "New paragraph when the topic changes" : "One continuous block"
        case .turnedOff: "Turn on Apple Intelligence in System Settings"
        case .downloading: "Apple Intelligence is still downloading"
        case .unsupported: "Requires a Mac with Apple silicon and macOS 26"
        }
    }

    /// Link under the subtitle; only when the user can act.
    public var actionTitle: String? {
        self == .turnedOff ? "Open System Settings…" : nil
    }
}
