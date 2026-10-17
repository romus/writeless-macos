import Foundation

/// Where a file's transcript is written. The default keeps it next to the
/// recording, because that is where the user will look for it.
public enum TranscriptDestination: Sendable, Equatable, Codable {
    case nextToRecording
    case documents
    case custom(path: String)

    public static let documentsSubfolder = "Writeless"

    /// `~/Documents/Writeless`: the second option in Settings, and the fallback
    /// for recordings that live somewhere a transcript should not go.
    public static func documentsFolder(home: URL) -> URL {
        home.appending(path: "Documents", directoryHint: .isDirectory)
            .appending(path: documentsSubfolder, directoryHint: .isDirectory)
    }

    /// The folder to write into. "Next to recording" moves to Documents when
    /// the recording's folder is under `~/Library` (a Voice Memos store, a Mail
    /// attachment), in a temporary folder, or not writable. A custom folder is
    /// returned as is; the writer copes with one that has gone away.
    public func folder(
        for audioURL: URL,
        home: URL,
        temporaryDirectory: URL,
        isWritable: (URL) -> Bool
    ) -> URL {
        switch self {
        case .documents:
            return Self.documentsFolder(home: home)
        case .custom(let path):
            return URL(filePath: path, directoryHint: .isDirectory)
        case .nextToRecording:
            let folder = audioURL.deletingLastPathComponent()
            let library = home.appending(path: "Library", directoryHint: .isDirectory)
            if Self.isInside(folder, library) || Self.isInside(folder, temporaryDirectory) || !isWritable(folder) {
                return Self.documentsFolder(home: home)
            }
            return folder
        }
    }

    public var popupTitle: String {
        switch self {
        case .nextToRecording: "Next to recording"
        case .documents: "Documents › Writeless"
        case .custom(let path): URL(filePath: path).lastPathComponent
        }
    }

    /// The row's subtitle: the effective path, or for "next to recording" the
    /// place it falls back to.
    public func settingsSubtitle(home: URL) -> String {
        let documents = Self.abbreviated(Self.documentsFolder(home: home).path(percentEncoded: false), home: home)
        switch self {
        case .nextToRecording: return "Falls back to \(documents)"
        case .documents: return documents
        case .custom(let path): return Self.abbreviated(path, home: home)
        }
    }

    /// "~/Documents/Writeless" for a path under `home`; other paths unchanged.
    public static func abbreviated(_ path: String, home: URL) -> String {
        let homePath = trimmed(home.path(percentEncoded: false))
        let path = trimmed(path)
        if path == homePath { return "~" }
        if path.hasPrefix(homePath + "/") { return "~" + path.dropFirst(homePath.count) }
        return path
    }

    /// `Name.md`, then `Name 2.md`, `Name 3.md`… — a transcript never replaces
    /// a file that is already there.
    public static func uniqueTranscriptURL(for audioURL: URL, in folder: URL, exists: (URL) -> Bool) -> URL {
        var base = audioURL.deletingPathExtension().lastPathComponent
        if base.isEmpty { base = "Transcript" }
        let first = folder.appending(path: "\(base).md")
        guard exists(first) else { return first }
        var number = 2
        while true {
            let candidate = folder.appending(path: "\(base) \(number).md")
            if !exists(candidate) { return candidate }
            number += 1
        }
    }

    /// Both sides resolved, so `/var/folders` and `/private/var/folders` agree.
    private static func isInside(_ url: URL, _ ancestor: URL) -> Bool {
        let path = trimmed(url.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false))
        let root = trimmed(ancestor.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false))
        return path == root || path.hasPrefix(root + "/")
    }

    private static func trimmed(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
