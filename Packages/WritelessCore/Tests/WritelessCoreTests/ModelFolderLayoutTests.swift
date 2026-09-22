import Foundation
import Testing

@testable import WritelessCore

@Suite("Model folder layout")
struct ModelFolderLayoutTests {
    private let model = WhisperModelCatalog.default

    private func makeBase() throws -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "writeless-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Writes the three compiled models the way the Hub lays them out.
    private func populate(
        base: URL,
        folder: String,
        weightBytes: Int = 1024,
        skipping omitted: (model: String, file: String)? = nil
    ) throws {
        let root = ModelFolderLayout.modelFolder(base: base, folder: folder)
        for name in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            let compiled = root.appending(path: "\(name).mlmodelc")
            try FileManager.default.createDirectory(
                at: compiled.appending(path: "weights"), withIntermediateDirectories: true
            )
            for file in ["coremldata.bin", "model.mil"] {
                if let omitted, omitted.model == name, omitted.file == file { continue }
                try Data("x".utf8).write(to: compiled.appending(path: file))
            }
            if let omitted, omitted.model == name, omitted.file == "weight.bin" { continue }
            try Data(repeating: 0, count: weightBytes)
                .write(to: compiled.appending(path: "weights/weight.bin"))
        }
    }

    @Test("Paths match what WhisperKit's Hub client writes")
    func paths() {
        let base = URL(fileURLWithPath: "/tmp/base")
        #expect(
            ModelFolderLayout.modelFolder(base: base, folder: model.folder).path
                == "/tmp/base/models/argmaxinc/whisperkit-coreml/\(model.folder)"
        )
        #expect(
            ModelFolderLayout.downloadCacheFolder(base: base, folder: model.folder).path
                == "/tmp/base/models/argmaxinc/whisperkit-coreml/.cache/huggingface/download/\(model.folder)"
        )
        #expect(
            ModelFolderLayout.tokenizerFile(base: base, repo: model.tokenizerRepo).path
                == "/tmp/base/models/openai/whisper-large-v3/tokenizer.json"
        )
    }

    @Test("A complete download is recognised")
    func complete() throws {
        let base = try makeBase()
        defer { try? FileManager.default.removeItem(at: base) }

        #expect(!ModelFolderLayout.hasRequiredFiles(base: base, folder: model.folder))
        try populate(base: base, folder: model.folder)
        #expect(ModelFolderLayout.hasRequiredFiles(base: base, folder: model.folder))
    }

    @Test(
        "Missing or empty files mean the model is not usable",
        arguments: [("TextDecoder", "weight.bin"), ("AudioEncoder", "model.mil"), ("MelSpectrogram", "coremldata.bin")]
    )
    func incomplete(omitted: (model: String, file: String)) throws {
        let base = try makeBase()
        defer { try? FileManager.default.removeItem(at: base) }

        try populate(base: base, folder: model.folder, skipping: omitted)
        #expect(!ModelFolderLayout.hasRequiredFiles(base: base, folder: model.folder))
    }

    @Test("A zero-byte weights file counts as incomplete")
    func emptyWeights() throws {
        let base = try makeBase()
        defer { try? FileManager.default.removeItem(at: base) }

        try populate(base: base, folder: model.folder, weightBytes: 0)
        #expect(!ModelFolderLayout.hasRequiredFiles(base: base, folder: model.folder))
    }

    @Test("The ready marker records that a model has loaded once")
    func readyMarker() throws {
        let base = try makeBase()
        defer { try? FileManager.default.removeItem(at: base) }

        try populate(base: base, folder: model.folder)
        #expect(!ModelFolderLayout.hasLoadedBefore(base: base, folder: model.folder))

        try Data().write(to: ModelFolderLayout.readyMarker(base: base, folder: model.folder))
        #expect(ModelFolderLayout.hasLoadedBefore(base: base, folder: model.folder))
    }

    @Test("The tokenizer is checked separately from the model")
    func tokenizer() throws {
        let base = try makeBase()
        defer { try? FileManager.default.removeItem(at: base) }

        try populate(base: base, folder: model.folder)
        #expect(!ModelFolderLayout.hasTokenizer(base: base, model: model))

        let tokenizer = ModelFolderLayout.tokenizerFile(base: base, repo: model.tokenizerRepo)
        try FileManager.default.createDirectory(
            at: tokenizer.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(to: tokenizer)
        #expect(ModelFolderLayout.hasTokenizer(base: base, model: model))
    }

    @Test("Progress counts partially downloaded files too")
    func bytesOnDisk() throws {
        let base = try makeBase()
        defer { try? FileManager.default.removeItem(at: base) }

        #expect(ModelFolderLayout.bytesOnDisk(base: base, folder: model.folder) == 0)
        try populate(base: base, folder: model.folder, weightBytes: 1000)

        let cache = ModelFolderLayout.downloadCacheFolder(base: base, folder: model.folder)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 500).write(to: cache.appending(path: "AudioEncoder.abc123.incomplete"))

        // 3 × (1000 bytes of weights + two 1-byte files) + 500 bytes in flight.
        #expect(ModelFolderLayout.bytesOnDisk(base: base, folder: model.folder) == 3 * 1002 + 500)
    }

    @Test("The cache total spans every model, the tokenizer and partial downloads")
    func totalBytesOnDisk() throws {
        let base = try makeBase()
        defer { try? FileManager.default.removeItem(at: base) }

        #expect(ModelFolderLayout.totalBytesOnDisk(base: base) == 0)

        try populate(base: base, folder: model.folder, weightBytes: 1000)
        try populate(base: base, folder: "openai_whisper-tiny", weightBytes: 500)

        let cache = ModelFolderLayout.downloadCacheFolder(base: base, folder: model.folder)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 500).write(to: cache.appending(path: "AudioEncoder.abc123.incomplete"))

        let tokenizer = ModelFolderLayout.tokenizerFile(base: base, repo: model.tokenizerRepo)
        try FileManager.default.createDirectory(
            at: tokenizer.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(repeating: 0, count: 200).write(to: tokenizer)

        #expect(ModelFolderLayout.totalBytesOnDisk(base: base) == 3 * 1002 + 3 * 502 + 500 + 200)

        // The guard that matters: summing the catalog instead would miss the
        // tokenizer and any folder left behind by a model we no longer list.
        #expect(
            ModelFolderLayout.totalBytesOnDisk(base: base)
                > ModelFolderLayout.bytesOnDisk(base: base, folder: model.folder)
        )
    }
}
