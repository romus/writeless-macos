import AppKit
import UniformTypeIdentifiers

/// The two open panels the app ever shows. Both activate the app first: a
/// menu bar app is not active while its menu is used, and an inactive app's
/// panel opens behind everything else.
enum FilePanels {
    /// Audio files to transcribe, several at once. Standalone: the app has no
    /// window to attach it to.
    static func chooseAudioFiles(completion: @escaping @MainActor ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose recordings to transcribe"
        panel.prompt = "Transcribe"
        NSApp.activate()
        panel.begin { response in
            completion(response == .OK ? panel.urls : [])
        }
    }

    /// A folder for transcripts, as a sheet on Settings when it is up.
    static func chooseFolder(
        current: URL?,
        sheetOn window: NSWindow?,
        completion: @escaping @MainActor (URL?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = current
        panel.message = "Choose where transcripts are saved"
        panel.prompt = "Choose"
        NSApp.activate()
        let handler: @MainActor (NSApplication.ModalResponse) -> Void = { response in
            completion(response == .OK ? panel.url : nil)
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }
}
