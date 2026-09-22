import Foundation

/// A Whisper model as offered in Settings, mapped to its folder in the
/// `argmaxinc/whisperkit-coreml` repository.
public struct WhisperModel: Sendable, Hashable, Identifiable, Codable {
    public let id: String
    public let displayName: String
    /// Folder name in the model repo; also the variant passed to `WhisperKit.download`.
    public let folder: String
    /// Total download size, used for the progress readout.
    public let downloadBytes: Int64
    /// Hugging Face repo WhisperKit pulls the tokenizer from.
    public let tokenizerRepo: String
    /// Argmax doesn't list this model as supported on any Mac.
    public let isUnsupportedByVendor: Bool

    public init(
        id: String,
        displayName: String,
        folder: String,
        downloadBytes: Int64,
        tokenizerRepo: String,
        isUnsupportedByVendor: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.folder = folder
        self.downloadBytes = downloadBytes
        self.tokenizerRepo = tokenizerRepo
        self.isUnsupportedByVendor = isUnsupportedByVendor
    }
}

public enum WhisperModelCatalog {
    public static let all: [WhisperModel] = [
        WhisperModel(
            id: "tiny", displayName: "Tiny",
            folder: "openai_whisper-tiny", downloadBytes: 76_635_397,
            tokenizerRepo: "openai/whisper-tiny"
        ),
        WhisperModel(
            id: "base", displayName: "Base",
            folder: "openai_whisper-base", downloadBytes: 146_719_453,
            tokenizerRepo: "openai/whisper-base"
        ),
        WhisperModel(
            id: "small", displayName: "Small",
            folder: "openai_whisper-small", downloadBytes: 486_487_465,
            tokenizerRepo: "openai/whisper-small"
        ),
        WhisperModel(
            id: "medium", displayName: "Medium",
            folder: "openai_whisper-medium", downloadBytes: 1_529_654_233,
            tokenizerRepo: "openai/whisper-medium",
            isUnsupportedByVendor: true
        ),
        // OpenAI's large-v3-turbo, compressed by Argmax: better and faster than
        // Medium at less than half the download.
        WhisperModel(
            id: "large", displayName: "Large",
            folder: "openai_whisper-large-v3-v20240930_626MB", downloadBytes: 626_718_238,
            tokenizerRepo: "openai/whisper-large-v3"
        ),
    ]

    public static let `default`: WhisperModel = model(id: "large") ?? all[0]

    public static func model(id: String) -> WhisperModel? {
        all.first { $0.id == id }
    }

    /// The model for a stored preference, falling back to the default.
    public static func model(forPreference id: String?) -> WhisperModel {
        id.flatMap(model(id:)) ?? `default`
    }
}
