import Foundation
import Testing

@testable import WritelessCore

@Suite("Model status")
struct ModelStatusTests {
    @Test("Download percentage is clamped")
    func percent() {
        #expect(ModelStatus.downloading(downloaded: 0, total: 100).percent == 0)
        #expect(ModelStatus.downloading(downloaded: 42, total: 100).percent == 42)
        #expect(ModelStatus.downloading(downloaded: 200, total: 100).percent == 100)
        #expect(ModelStatus.downloading(downloaded: 1, total: 0).percent == nil)
        #expect(ModelStatus.ready.percent == nil)
    }

    @Test("Settings shows 'On-device' unless something is happening")
    func subtitles() {
        #expect(ModelStatus.ready.settingsSubtitle == "On-device")
        #expect(ModelStatus.missing.settingsSubtitle == "Not downloaded")
        #expect(
            ModelStatus.downloading(downloaded: 312_000_000, total: 626_718_238).settingsSubtitle
                == "Downloading… 312 of 627 MB"
        )
        #expect(ModelStatus.preparing(firstRun: true).settingsSubtitle.hasPrefix("Preparing…"))
        #expect(ModelStatus.failed("boom").settingsSubtitle == "Download failed")
    }

    @Test("The menu stays quiet while the model is ready, and says so when it is gone")
    func menuHeader() {
        #expect(ModelStatus.ready.menuHeader == nil)
        #expect(ModelStatus.missing.menuHeader == "Model not downloaded")
        #expect(ModelStatus.downloading(downloaded: 42, total: 100).menuHeader == "Downloading model… 42%")
        #expect(ModelStatus.preparing(firstRun: false).menuHeader == "Loading model…")
        #expect(ModelStatus.failed("boom").menuHeader == "Model download failed")
    }

    @Test("Recording waits for a download or a first specialization, but not for a cached load")
    func blockers() {
        #expect(ModelStatus.ready.recordingBlocker == nil)
        #expect(ModelStatus.preparing(firstRun: false).recordingBlocker == nil)
        #expect(ModelStatus.preparing(firstRun: true).recordingBlocker == .modelPreparing)
        #expect(ModelStatus.downloading(downloaded: 42, total: 100).recordingBlocker == .modelDownloading(percent: 42))
        #expect(ModelStatus.missing.recordingBlocker == .modelUnavailable)
        #expect(ModelStatus.failed("boom").recordingBlocker == .modelUnavailable)
    }

    @Test("A cleared cache is never a dead end: it always offers a way to download")
    func downloadPrompt() {
        #expect(ModelStatus.missing.downloadPrompt == .download)
        #expect(ModelStatus.failed("boom").downloadPrompt == .retry)
        #expect(ModelStatus.ready.downloadPrompt == nil)
        #expect(ModelStatus.downloading(downloaded: 42, total: 100).downloadPrompt == nil)
        #expect(ModelStatus.preparing(firstRun: true).downloadPrompt == nil)

        #expect(DownloadPrompt.download.settingsTitle == "Download")
        #expect(DownloadPrompt.download.menuTitle == "Download Model")
        #expect(DownloadPrompt.retry.settingsTitle == "Retry")
        #expect(DownloadPrompt.retry.menuTitle == "Retry Download")
    }

    @Test("A missing model shows the download glyph, not a ready menu bar")
    func idleSymbols() {
        #expect(ModelStatus.missing.idleSymbolName == "arrow.down.circle")
        #expect(ModelStatus.downloading(downloaded: 42, total: 100).idleSymbolName == "arrow.down.circle")
        #expect(ModelStatus.preparing(firstRun: false).idleSymbolName == "hourglass")
        #expect(ModelStatus.failed("boom").idleSymbolName == "exclamationmark.triangle")
        #expect(ModelStatus.ready.idleSymbolName == nil)
    }
}
