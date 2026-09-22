import Foundation

/// Where WhisperKit's Hub client puts files under our download base, and how to
/// tell — offline — whether a model is usable.
///
/// Layout: `<base>/models/argmaxinc/whisperkit-coreml/<folder>/` for the model,
/// `<base>/models/<tokenizerRepo>/` for the tokenizer, and
/// `<base>/models/argmaxinc/whisperkit-coreml/.cache/huggingface/download/<folder>/`
/// for download metadata and `.incomplete` parts.
public enum ModelFolderLayout {
    public static let modelRepo = "argmaxinc/whisperkit-coreml"
    /// Written after a model has loaded successfully once, so the app can tell a
    /// first, slow Neural Engine specialization from a fast load out of the cache.
    public static let readyMarkerName = ".writeless-ready"

    private static let requiredModels = ["MelSpectrogram", "AudioEncoder", "TextDecoder"]
    private static let requiredFiles = ["coremldata.bin", "model.mil"]

    public static func repoFolder(base: URL) -> URL {
        base.appending(path: "models").appending(path: modelRepo)
    }

    public static func modelFolder(base: URL, folder: String) -> URL {
        repoFolder(base: base).appending(path: folder)
    }

    public static func downloadCacheFolder(base: URL, folder: String) -> URL {
        repoFolder(base: base)
            .appending(path: ".cache/huggingface/download")
            .appending(path: folder)
    }

    public static func tokenizerFile(base: URL, repo: String) -> URL {
        base.appending(path: "models").appending(path: repo).appending(path: "tokenizer.json")
    }

    public static func readyMarker(base: URL, folder: String) -> URL {
        modelFolder(base: base, folder: folder).appending(path: readyMarkerName)
    }

    /// True when all three Core ML models are present with non-empty weights.
    public static func hasRequiredFiles(
        base: URL,
        folder: String,
        fileManager: FileManager = .default
    ) -> Bool {
        let root = modelFolder(base: base, folder: folder)
        for name in requiredModels {
            let compiled = root.appending(path: "\(name).mlmodelc")
            for file in requiredFiles where !fileManager.fileExists(atPath: compiled.appending(path: file).path) {
                return false
            }
            let weights = compiled.appending(path: "weights/weight.bin")
            let size = (try? fileManager.attributesOfItem(atPath: weights.path)[.size] as? Int64) ?? nil
            guard let size, size > 0 else { return false }
        }
        return true
    }

    public static func hasTokenizer(
        base: URL,
        model: WhisperModel,
        fileManager: FileManager = .default
    ) -> Bool {
        fileManager.fileExists(atPath: tokenizerFile(base: base, repo: model.tokenizerRepo).path)
    }

    public static func hasLoadedBefore(
        base: URL,
        folder: String,
        fileManager: FileManager = .default
    ) -> Bool {
        fileManager.fileExists(atPath: readyMarker(base: base, folder: folder).path)
    }

    /// Everything downloaded for a model so far, including partial files, which
    /// makes a smoother progress readout than the SDK's per-file weighting.
    public static func bytesOnDisk(
        base: URL,
        folder: String,
        fileManager: FileManager = .default
    ) -> Int64 {
        directorySize(modelFolder(base: base, folder: folder), fileManager: fileManager)
            + directorySize(downloadCacheFolder(base: base, folder: folder), fileManager: fileManager)
    }

    /// Everything under the download base: every model, the Hub's partial
    /// downloads and the tokenizers. This is what Settings calls the model cache.
    ///
    /// Logical size, not blocks allocated, so "627 MB on disk" matches the
    /// catalog's `downloadBytes` and the "312 of 627 MB" progress readout.
    public static func totalBytesOnDisk(base: URL, fileManager: FileManager = .default) -> Int64 {
        directorySize(base, fileManager: fileManager)
    }

    private static func directorySize(_ url: URL, fileManager: FileManager) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: []
        ) else { return 0 }

        var total: Int64 = 0
        for case let item as URL in enumerator {
            let values = try? item.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true, let size = values?.fileSize else { continue }
            total += Int64(size)
        }
        return total
    }
}
