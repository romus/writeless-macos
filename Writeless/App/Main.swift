import AppKit

@main
enum Main {
    /// `NSApplication.delegate` is a weak reference, so the app delegate needs
    /// an owner that outlives `run()`.
    private static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.mainMenu = MainMenu.build()
        app.run()
    }
}
