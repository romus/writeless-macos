import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        coordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.shutDown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Opening the app again (from Finder, Spotlight or `open -a`) has nothing
    /// to show otherwise, so treat it as a request for Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        coordinator?.showSettings()
        return true
    }

    /// `open -a "Write Less" recording.m4a`: the same path as a drop on the
    /// menu bar icon.
    func application(_ application: NSApplication, open urls: [URL]) {
        coordinator?.transcribeFiles(urls)
    }
}
