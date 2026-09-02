import AppKit

/// An `@main` type rather than a `main.swift`, because top-level code runs
/// outside any actor and every piece of this app is main-actor bound.
@main
enum Omnipen {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
