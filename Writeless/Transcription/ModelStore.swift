import Foundation
import WritelessCore

/// Model files on disk. Everything is derived from `ModelFolderLayout`, so the
/// rules for "is this model usable offline" are unit-tested in WritelessCore.
nonisolated struct ModelStore: Sendable {
    let base: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.init(base: support.appending(path: "Writeless/Models"))
    }

    init(base: URL) {
        self.base = base
    }

    func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var url = base
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    func folder(for model: WhisperModel) -> URL {
        ModelFolderLayout.modelFolder(base: base, folder: model.folder)
    }

    /// The Core ML models are all there. The tokenizer is fetched separately by
    /// WhisperKit on the first load, so it is not part of this check.
    func hasModelFiles(_ model: WhisperModel) -> Bool {
        ModelFolderLayout.hasRequiredFiles(base: base, folder: model.folder)
    }

    func hasTokenizer(_ model: WhisperModel) -> Bool {
        ModelFolderLayout.hasTokenizer(base: base, model: model)
    }

    /// Whether this model has been loaded successfully before, which tells a
    /// slow first Neural Engine specialization from a fast cached load.
    func hasLoadedBefore(_ model: WhisperModel) -> Bool {
        ModelFolderLayout.hasLoadedBefore(base: base, folder: model.folder)
    }

    func markLoaded(_ model: WhisperModel) {
        let marker = ModelFolderLayout.readyMarker(base: base, folder: model.folder)
        try? Data().write(to: marker)
    }

    func bytesOnDisk(_ model: WhisperModel) -> Int64 {
        ModelFolderLayout.bytesOnDisk(base: base, folder: model.folder)
    }

    /// Everything under the base: every model, the tokenizers and the Hub's
    /// partial downloads. This is what Settings calls the model cache.
    func totalBytesOnDisk() -> Int64 {
        ModelFolderLayout.totalBytesOnDisk(base: base)
    }

    /// Wipes every downloaded model, tokenizer and partial download, and puts
    /// the directory back so the next download starts into a clean tree.
    ///
    /// The caller must unload any live pipeline first: on APFS this unlinks
    /// files Core ML has mapped, which succeeds but leaves the pipeline reading
    /// an inode nothing can reach — and reclaims no space.
    func removeAllDownloads() throws {
        // Even a delete that fails halfway has to leave a usable directory
        // behind, or the next preparation fails before it starts. Recreating it
        // is also what re-applies the backup exclusion, which lives on the
        // folder itself.
        defer { try? prepareDirectory() }
        let manager = FileManager.default
        guard manager.fileExists(atPath: base.path) else { return }
        try manager.removeItem(at: base)
    }

    /// Wipes a broken download, including the Hub's metadata, so the next
    /// attempt starts clean instead of resuming onto damaged files.
    func removeDownload(_ model: WhisperModel) {
        let manager = FileManager.default
        try? manager.removeItem(at: ModelFolderLayout.modelFolder(base: base, folder: model.folder))
        try? manager.removeItem(at: ModelFolderLayout.downloadCacheFolder(base: base, folder: model.folder))
    }
}
