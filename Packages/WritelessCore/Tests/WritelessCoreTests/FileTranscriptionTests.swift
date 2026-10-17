import Foundation
import Testing

@testable import WritelessCore

private let sampleRate = 16_000

private func silence(seconds: Double) -> [Float] {
    Array(repeating: 0, count: Int(Double(sampleRate) * seconds))
}

private func tone(seconds: Double, amplitude: Float = 0.2, frequency: Double = 220) -> [Float] {
    (0..<Int(Double(sampleRate) * seconds)).map { index in
        amplitude * Float(sin(2 * Double.pi * frequency * Double(index) / Double(sampleRate)))
    }
}

private func seconds(_ value: Double) -> Int { Int(Double(sampleRate) * value) }

/// One 100 ms frame either way: the cut is placed on a frame boundary.
private func isNear(_ cut: Int, _ expected: Int) -> Bool { abs(cut - expected) <= seconds(0.1) }

@Suite("Pause finder")
struct PauseFinderTests {
    @Test("A stretch no longer than the search window is not cut")
    func shortStretch() {
        let samples = tone(seconds: 20)
        #expect(PauseFinder.cutIndex(samples: samples) == samples.count)
        let exactly = silence(seconds: 30)
        #expect(PauseFinder.cutIndex(samples: exactly) == exactly.count)
    }

    @Test("The cut lands in the middle of the pause near the end")
    func cutsInThePause() {
        let samples = tone(seconds: 50) + silence(seconds: 2) + tone(seconds: 10)
        #expect(isNear(PauseFinder.cutIndex(samples: samples), seconds(51)))
    }

    @Test("A pause outside the trailing window does not count")
    func ignoresEarlyPause() {
        let samples = tone(seconds: 10) + silence(seconds: 2) + tone(seconds: 60)
        #expect(PauseFinder.cutIndex(samples: samples) == samples.count)
    }

    @Test("Speech with no pause at all is cut at the end")
    func noPause() {
        let samples = tone(seconds: 90)
        #expect(PauseFinder.cutIndex(samples: samples) == samples.count)
    }

    @Test("The longest pause wins")
    func longestPause() {
        let samples = tone(seconds: 40) + silence(seconds: 1) + tone(seconds: 5) + silence(seconds: 3) + tone(seconds: 5)
        #expect(isNear(PauseFinder.cutIndex(samples: samples), seconds(47.5)))
    }

    @Test("Between equal pauses, the later one wins")
    func laterPauseOnTie() {
        let samples = tone(seconds: 40) + silence(seconds: 2) + tone(seconds: 5) + silence(seconds: 2) + tone(seconds: 5)
        #expect(isNear(PauseFinder.cutIndex(samples: samples), seconds(48)))
    }

    @Test("A silent stretch is cut in the middle of the window, never at zero")
    func allSilent() {
        let samples = silence(seconds: 40)
        let cut = PauseFinder.cutIndex(samples: samples)
        #expect(cut > 0)
        #expect(isNear(cut, seconds(25)))
    }
}

@Suite("File transcription progress")
struct FileTranscriptionProgressTests {
    @Test("The fraction is clamped and zero until the length is known")
    func fraction() {
        var progress = FileTranscriptionProgress(fileName: "Meeting.m4a")
        progress.doneSeconds = 50
        #expect(progress.fraction == 0)
        progress.totalSeconds = 100
        #expect(progress.fraction == 0.5)
        progress.doneSeconds = 150
        #expect(progress.fraction == 1)
    }

    @Test("Labels follow the design")
    func labels() {
        var progress = FileTranscriptionProgress(fileName: "Meeting.m4a")
        #expect(progress.title == "Transcribing Meeting.m4a")
        #expect(progress.positionLabel == nil)
        progress.totalSeconds = 4360
        progress.doneSeconds = 1832
        #expect(progress.positionLabel == "30:32 of 1:12:40")
        progress.doneSeconds = 5000
        #expect(progress.positionLabel == "1:12:40 of 1:12:40")
    }

    @Test("The estimate extrapolates from the pieces done so far")
    func remaining() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var progress = FileTranscriptionProgress(fileName: "Meeting.m4a")
        progress.totalSeconds = 3600
        #expect(progress.remainingLabel(now: start) == nil)

        progress.startedAt = start
        #expect(progress.remainingLabel(now: start + 60) == nil)

        progress.doneSeconds = 600
        #expect(progress.remainingLabel(now: start + 60) == "about 5 min left")
        #expect(progress.remainingLabel(now: start) == nil)

        progress.doneSeconds = 3590
        #expect(progress.remainingLabel(now: start + 100) == "about 1 min left")

        progress.doneSeconds = 3600
        #expect(progress.remainingLabel(now: start + 100) == nil)

        progress.isFormatting = true
        #expect(progress.remainingLabel(now: start + 100) == "Adding paragraphs…")
    }

    @Test("Long estimates read in hours")
    func hours() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var progress = FileTranscriptionProgress(fileName: "Lecture.mp3")
        progress.totalSeconds = 36_000
        progress.startedAt = start
        progress.doneSeconds = 600
        #expect(progress.remainingLabel(now: start + 600) == "about 9 h 50 min left")
        progress.totalSeconds = 7800
        #expect(progress.remainingLabel(now: start + 600) == "about 2 h left")
    }
}

@Suite("Transcript destination")
struct TranscriptDestinationTests {
    private let home = URL(filePath: "/Users/test", directoryHint: .isDirectory)
    private let temporary = URL(filePath: "/Users/test/tmp", directoryHint: .isDirectory)
    private let documents = URL(filePath: "/Users/test/Documents/Writeless", directoryHint: .isDirectory)

    private func folder(_ destination: TranscriptDestination, for path: String, writable: Bool = true) -> URL {
        destination.folder(
            for: URL(filePath: path), home: home, temporaryDirectory: temporary, isWritable: { _ in writable }
        )
    }

    @Test("Next to the recording means the recording's own folder")
    func nextToRecording() {
        #expect(folder(.nextToRecording, for: "/Users/test/Desktop/Meeting.m4a") == URL(filePath: "/Users/test/Desktop/", directoryHint: .isDirectory))
        #expect(folder(.nextToRecording, for: "/Volumes/Stick/Talk.wav") == URL(filePath: "/Volumes/Stick/", directoryHint: .isDirectory))
    }

    @Test("Recordings under Library, in a temporary folder or somewhere read-only fall back to Documents")
    func fallbacks() {
        #expect(folder(.nextToRecording, for: "/Users/test/Library/Group Containers/VoiceMemos/Recordings/Memo.m4a") == documents)
        #expect(folder(.nextToRecording, for: "/Users/test/tmp/drop/Memo.m4a") == documents)
        #expect(folder(.nextToRecording, for: "/Users/test/Desktop/Meeting.m4a", writable: false) == documents)
        // The real temporary directory resolves through /private/var on macOS.
        let real = FileManager.default.temporaryDirectory
        let scratch = real.appending(path: "some-app/Memo.m4a")
        let resolved = TranscriptDestination.nextToRecording.folder(
            for: scratch, home: home, temporaryDirectory: real, isWritable: { _ in true }
        )
        #expect(resolved == documents)
    }

    @Test("Documents and a custom folder ignore where the recording is")
    func fixedFolders() {
        #expect(folder(.documents, for: "/Users/test/Desktop/Meeting.m4a") == documents)
        #expect(folder(.custom(path: "/Users/test/Notes/Transcripts"), for: "/Volumes/Stick/Talk.wav")
            == URL(filePath: "/Users/test/Notes/Transcripts", directoryHint: .isDirectory))
    }

    @Test("A transcript never replaces an existing file")
    func uniqueNames() {
        let folder = URL(filePath: "/Users/test/Desktop", directoryHint: .isDirectory)
        let audio = URL(filePath: "/Users/test/Desktop/Meeting.m4a")
        let fresh = TranscriptDestination.uniqueTranscriptURL(for: audio, in: folder, exists: { _ in false })
        #expect(fresh.lastPathComponent == "Meeting.md")

        let taken: Set<String> = ["Meeting.md", "Meeting 2.md"]
        let next = TranscriptDestination.uniqueTranscriptURL(for: audio, in: folder) { taken.contains($0.lastPathComponent) }
        #expect(next.lastPathComponent == "Meeting 3.md")
        #expect(next.deletingLastPathComponent() == folder)
    }

    @Test("Titles and subtitles follow the design")
    func titles() {
        #expect(TranscriptDestination.nextToRecording.popupTitle == "Next to recording")
        #expect(TranscriptDestination.documents.popupTitle == "Documents › Writeless")
        #expect(TranscriptDestination.custom(path: "/Users/test/Notes/Transcripts").popupTitle == "Transcripts")

        #expect(TranscriptDestination.nextToRecording.settingsSubtitle(home: home) == "Falls back to ~/Documents/Writeless")
        #expect(TranscriptDestination.documents.settingsSubtitle(home: home) == "~/Documents/Writeless")
        #expect(TranscriptDestination.custom(path: "/Users/test/Notes/Transcripts").settingsSubtitle(home: home) == "~/Notes/Transcripts")
        #expect(TranscriptDestination.custom(path: "/Volumes/Notes").settingsSubtitle(home: home) == "/Volumes/Notes")
        #expect(TranscriptDestination.abbreviated("/Users/test/", home: home) == "~")
        #expect(TranscriptDestination.abbreviated("/Users/tester/Notes", home: home) == "/Users/tester/Notes")
    }

    @Test("The preference survives a round trip through JSON")
    func codable() throws {
        for destination in [TranscriptDestination.nextToRecording, .documents, .custom(path: "/Users/test/Notes")] {
            let data = try JSONEncoder().encode(destination)
            #expect(try JSONDecoder().decode(TranscriptDestination.self, from: data) == destination)
        }
    }
}

@Suite("File notices")
struct FileNoticeTests {
    @Test("The file notices name the outcome")
    func texts() {
        #expect(Notice.transcriptSaved("Meeting.md").text == "Saved Meeting.md")
        #expect(Notice.transcriptSaved("Meeting.md").symbolName == "doc.text")
        #expect(Notice.fileUnreadable.text == "Couldn't read the audio file")
        #expect(Notice.transcriptNotSaved.text == "Couldn't save the transcript")
        #expect(Notice.fileUnreadable.symbolName == "exclamationmark.triangle")
        #expect(Notice.transcriptNotSaved.symbolName == "exclamationmark.triangle")
    }
}
