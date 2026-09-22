import Foundation
import WritelessCore

// The only file that touches WhisperKit. Its types are not Sendable, so they
// never leave this actor.
@preconcurrency import WhisperKit

/// Downloads, loads and runs the Whisper model.
actor TranscriptionEngine {
    enum EngineError: LocalizedError {
        case incompleteDownload
        case notReady

        var errorDescription: String? {
            switch self {
            case .incompleteDownload: "The model download is incomplete."
            case .notReady: "The model is not ready."
            }
        }
    }

    /// Status updates for the menu, Settings and the pill.
    nonisolated let statuses: AsyncStream<ModelStatus>

    private let store: ModelStore
    private let statusContinuation: AsyncStream<ModelStatus>.Continuation
    private var kit: WhisperKit?
    private var loadedModel: WhisperModel?
    /// The preparation in flight, and what it is preparing. Cleared when it
    /// finishes, so a later `prepare` of the same model starts fresh.
    private var preparation: (model: WhisperModel, task: Task<Void, Never>)?
    /// Bumped whenever a preparation starts or is abandoned, so a load that
    /// finishes late can tell that it is stale.
    private var generation = 0

    init(store: ModelStore) {
        self.store = store
        (statuses, statusContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(4))
    }

    /// Starts (or restarts) downloading and loading a model in the background.
    func prepare(_ model: WhisperModel) {
        if loadedModel == model, kit != nil {
            // Already loaded — but a preparation for some other model may still
            // be running, and it would overwrite this one when it lands.
            abandonPreparation()
            emit(.ready)
            return
        }
        if preparation?.model == model { return }

        abandonPreparation()
        let generation = self.generation
        preparation = (model, Task { await self.runPreparation(model, generation: generation) })
    }

    func transcribe(samples: [Float], model: WhisperModel, language: String?) async throws -> String {
        let kit = try await readyKit(for: model)

        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: language,
            temperature: 0,
            temperatureFallbackCount: 3,
            usePrefillPrompt: true,
            // Without this, a nil language silently prefills <|en|> and
            // everything comes back translated-looking English.
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            // The 1 second default clips the tail of every window, which makes
            // sub-second recordings decode to nothing at all.
            windowClipTime: 0,
            suppressBlank: true,
            chunkingStrategy: .vad
        )

        let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
        // Chunked (VAD) transcription swallows per-chunk cancellation.
        try Task.checkCancellation()
        return results.map(\.text).joined(separator: " ")
    }

    func unload() async {
        abandonPreparation()
        await kit?.unloadModels()
        kit = nil
        loadedModel = nil
    }

    /// Throws the loaded pipeline away and deletes everything downloaded.
    /// Nothing is fetched again here: the next dictation — or the Download
    /// button in Settings — starts the download.
    ///
    /// The order matters three times over:
    ///  - a preparation in flight has to be cancelled *and awaited*, or a
    ///    download still writing into the tree recreates part of what we just
    ///    deleted (`WhisperKit.download` resolves successfully when cancelled);
    ///  - the Core ML models are memory-mapped, so unloading has to precede the
    ///    delete, or the pipeline reads unlinked inodes and no space comes back;
    ///  - `.missing` goes out before the delete, so recording is refused from
    ///    the moment the files stop being there.
    func clearCache() async {
        // A loop, not an `if`: every `await` here releases the actor, so a
        // `prepare` from the model picker can slip in while we wait.
        while let inFlight = preparation {
            abandonPreparation()
            await inFlight.task.value
        }
        abandonPreparation()

        await kit?.unloadModels()
        kit = nil
        loadedModel = nil
        emit(.missing)

        do {
            // Deliberately synchronous on the actor: that is what serialises the
            // delete against `prepare`, `transcribe` and `readyKit` without any
            // extra state. The actor's executor is not the main thread.
            try store.removeAllDownloads()
            Log.model.info("Model cache cleared")
        } catch {
            Log.model.error("Could not clear the model cache: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Cancels whatever is in flight and makes its late results stale.
    private func abandonPreparation() {
        generation += 1
        guard let preparation else { return }
        preparation.task.cancel()
        self.preparation = nil
    }

    // MARK: - Preparation

    private func runPreparation(_ model: WhisperModel, generation: Int, allowRepair: Bool = true) async {
        // Clearing this on the way out is what lets a retry (or a switch back
        // to this model) start a new preparation instead of awaiting a task
        // that has already finished.
        defer { if generation == self.generation { preparation = nil } }

        do {
            try store.prepareDirectory()

            if !store.hasModelFiles(model) {
                emit(.downloading(downloaded: store.bytesOnDisk(model), total: model.downloadBytes))
                let progress = pollDownloadProgress(model, generation: generation)
                defer { progress.cancel() }

                _ = try await WhisperKit.download(
                    variant: model.folder,
                    downloadBase: store.base,
                    from: ModelFolderLayout.modelRepo
                )
                // A cancelled download resolves successfully with a half-filled
                // folder, so check both cancellation and the files themselves.
                try Task.checkCancellation()
                guard store.hasModelFiles(model) else { throw EngineError.incompleteDownload }
            }

            guard generation == self.generation else { return }
            try Task.checkCancellation()

            emit(.preparing(firstRun: !store.hasLoadedBefore(model)))
            let loaded = try await loadKit(model)

            guard generation == self.generation else {
                await loaded.unloadModels()
                return
            }
            kit = loaded
            loadedModel = model
            store.markLoaded(model)
            emit(.ready)
            Log.model.info("Model \(model.id, privacy: .public) ready")
        } catch is CancellationError {
            Log.model.debug("Model preparation cancelled")
        } catch {
            guard generation == self.generation else { return }

            if allowRepair, store.hasModelFiles(model) {
                // Most load failures here mean damaged files: start over once.
                Log.model.error("Load failed, repairing \(model.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                store.removeDownload(model)
                await runPreparation(model, generation: generation, allowRepair: false)
                return
            }

            Log.model.error("Model preparation failed: \(error.localizedDescription, privacy: .public)")
            emit(.failed(error.localizedDescription))
        }
    }

    private func loadKit(_ model: WhisperModel) async throws -> WhisperKit {
        do {
            return try await makeKit(model, compute: nil)
        } catch {
            // Argmax doesn't list Medium as supported on any Mac; if the Neural
            // Engine refuses it, fall back to CPU and GPU before giving up.
            guard model.isUnsupportedByVendor else { throw error }
            Log.model.error("Neural Engine load failed for \(model.id, privacy: .public), retrying on GPU")
            return try await makeKit(
                model,
                compute: ModelComputeOptions(audioEncoderCompute: .cpuAndGPU, textDecoderCompute: .cpuAndGPU)
            )
        }
    }

    private func makeKit(_ model: WhisperModel, compute: ModelComputeOptions?) async throws -> WhisperKit {
        let config = WhisperKitConfig(
            model: model.folder,
            downloadBase: store.base,
            modelFolder: store.folder(for: model).path,
            // Without an explicit folder the tokenizer lands in ~/Documents and
            // macOS asks for Documents access.
            tokenizerFolder: store.base,
            computeOptions: compute,
            verbose: true,
            logLevel: .error,
            prewarm: false,
            load: true,
            download: false
        )
        return try await WhisperKit(config)
    }

    /// The SDK weights progress per file, which jumps around; bytes on disk
    /// move smoothly.
    private func pollDownloadProgress(_ model: WhisperModel, generation: Int) -> Task<Void, Never> {
        Task { [store] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, await generation == self.generation else { return }
                let downloaded = store.bytesOnDisk(model)
                await self.emit(.downloading(downloaded: downloaded, total: model.downloadBytes))
            }
        }
    }

    private func readyKit(for model: WhisperModel) async throws -> WhisperKit {
        if kit == nil || loadedModel != model {
            // Waiting on a preparation for a *different* model would return a
            // pipeline we can't use, so start the right one first.
            if preparation?.model != model { prepare(model) }
            await preparation?.task.value
        }
        guard let kit, loadedModel == model else { throw EngineError.notReady }
        return kit
    }

    private func emit(_ status: ModelStatus) {
        statusContinuation.yield(status)
    }
}
