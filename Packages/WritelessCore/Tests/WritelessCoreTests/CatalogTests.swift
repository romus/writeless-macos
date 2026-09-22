import Foundation
import Testing

@testable import WritelessCore

@Suite("Whisper model catalog")
struct WhisperModelCatalogTests {
    @Test("Large v3 Turbo is the default")
    func defaultModel() {
        #expect(WhisperModelCatalog.default.id == "large")
        #expect(WhisperModelCatalog.default.folder == "openai_whisper-large-v3-v20240930_626MB")
        #expect(WhisperModelCatalog.default.tokenizerRepo == "openai/whisper-large-v3")
    }

    @Test("Five models, in ascending size order, each with a download size")
    func catalog() {
        let ids = WhisperModelCatalog.all.map(\.id)
        #expect(ids == ["tiny", "base", "small", "medium", "large"])
        for model in WhisperModelCatalog.all {
            #expect(model.downloadBytes > 0)
            #expect(model.folder.hasPrefix("openai_whisper-"))
            #expect(model.tokenizerRepo.hasPrefix("openai/whisper-"))
        }
    }

    @Test("Medium is flagged: Argmax lists no Mac as supporting it")
    func mediumIsFlagged() {
        #expect(WhisperModelCatalog.model(id: "medium")?.isUnsupportedByVendor == true)
        #expect(WhisperModelCatalog.model(id: "large")?.isUnsupportedByVendor == false)
    }

    @Test("Unknown or missing preferences fall back to the default")
    func preferences() {
        #expect(WhisperModelCatalog.model(forPreference: "small").id == "small")
        #expect(WhisperModelCatalog.model(forPreference: "huge").id == "large")
        #expect(WhisperModelCatalog.model(forPreference: nil).id == "large")
    }
}

@Suite("Language catalog")
struct LanguageCatalogTests {
    @Test("Every Whisper language, sorted by name, no duplicate codes")
    func catalog() {
        #expect(LanguageCatalog.all.count == 100)
        #expect(LanguageCatalog.all.map(\.name) == LanguageCatalog.all.map(\.name).sorted())
        #expect(Set(LanguageCatalog.all.map(\.code)).count == LanguageCatalog.all.count)
        #expect(LanguageCatalog.language(code: "ru")?.name == "Russian")
        #expect(LanguageCatalog.language(code: "en")?.name == "English")
        // Aliases such as "mandarin" collapse into the primary name.
        #expect(LanguageCatalog.language(code: "zh")?.name == "Chinese")
    }

    @Test("Automatic means no language is passed to WhisperKit")
    func automatic() {
        #expect(LanguageCatalog.decodingLanguage(forPreference: nil) == nil)
        #expect(LanguageCatalog.decodingLanguage(forPreference: "auto") == nil)
        #expect(LanguageCatalog.decodingLanguage(forPreference: "klingon") == nil)
        #expect(LanguageCatalog.decodingLanguage(forPreference: "ru") == "ru")
        #expect(LanguageCatalog.displayName(forPreference: "auto") == "Automatic")
        #expect(LanguageCatalog.displayName(forPreference: "ru") == "Russian")
    }
}

@Suite("Formatting")
struct FormattingTests {
    @Test(
        "Elapsed time",
        arguments: [(0.0, "0:00"), (7.4, "0:07"), (59.9, "0:59"), (65.0, "1:05"), (600.0, "10:00"), (-3.0, "0:00")]
    )
    func elapsed(seconds: Double, expected: String) {
        #expect(ClockFormat.elapsed(seconds) == expected)
    }

    @Test("Download progress reads in megabytes and never overshoots")
    func bytes() {
        #expect(ByteFormat.progress(downloaded: 312_000_000, total: 626_718_238) == "312 of 627 MB")
        #expect(ByteFormat.progress(downloaded: 700_000_000, total: 626_718_238) == "627 of 627 MB")
    }

    @Test(
        "A cache size reads in whole megabytes, or one decimal of a gigabyte",
        arguments: [
            (Int64(0), "0 MB"),
            (Int64(-5), "0 MB"),
            (Int64(4_096), "4 KB"),
            (Int64(626_718_238), "627 MB"),
            (Int64(999_400_000), "999 MB"),
            // The cutoff is on rounded megabytes, so this is "1.0 GB", never "1000 MB".
            (Int64(999_600_000), "1.0 GB"),
            (Int64(1_529_654_233), "1.5 GB"),
            (Int64(2_100_000_000), "2.1 GB"),
        ]
    )
    func cacheSize(bytes: Int64, expected: String) {
        #expect(ByteFormat.size(bytes) == expected)
    }
}
