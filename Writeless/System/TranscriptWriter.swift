import Foundation
import WritelessCore

/// Writes a transcript next to its recording, or where Settings says. Never
/// overwrites: a name that is taken gets a number.
///
/// `nonisolated`, and called from a detached task: the first write into
/// Documents, Desktop or Downloads brings up the system's consent prompt,
/// which must not stall the main actor.
nonisolated enum TranscriptWriter {
    enum WriteError: LocalizedError {
        case cannotWrite(String)

        var errorDescription: String? {
            switch self {
            case .cannotWrite(let reason): "The transcript could not be saved: \(reason)"
            }
        }
    }

    static func save(_ text: String, for audioURL: URL, destination: TranscriptDestination) throws -> URL {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let folder = destination.folder(
            for: audioURL,
            home: home,
            temporaryDirectory: fileManager.temporaryDirectory,
            isWritable: { fileManager.isWritableFile(atPath: $0.path(percentEncoded: false)) }
        )

        do {
            return try write(text, for: audioURL, into: folder)
        } catch {
            let documents = TranscriptDestination.documentsFolder(home: home)
            guard folder != documents else { throw WriteError.cannotWrite(error.localizedDescription) }
            // A chosen folder on a disk that is no longer plugged in, say.
            Log.files.error("Could not save to \(folder.path(percentEncoded: false), privacy: .public), trying Documents: \(error.localizedDescription, privacy: .public)")
            do {
                return try write(text, for: audioURL, into: documents)
            } catch {
                throw WriteError.cannotWrite(error.localizedDescription)
            }
        }
    }

    private static func write(_ text: String, for audioURL: URL, into folder: URL) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = Data((text + "\n").utf8)

        // `.withoutOverwriting` closes the gap between picking a name and
        // using it: if something else takes the name first, pick again.
        var attempts = 0
        while true {
            let url = TranscriptDestination.uniqueTranscriptURL(for: audioURL, in: folder) {
                fileManager.fileExists(atPath: $0.path(percentEncoded: false))
            }
            do {
                try data.write(to: url, options: [.withoutOverwriting])
                return url
            } catch let error as CocoaError where error.code == .fileWriteFileExists && attempts < 5 {
                attempts += 1
            }
        }
    }
}
