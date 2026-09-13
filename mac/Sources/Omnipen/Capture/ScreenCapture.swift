import AppKit
import ScreenCaptureKit

/// Reads pixels off the screen for the snapshot and blur tools.
///
/// This is the only part of Omnipen that needs the Screen Recording permission,
/// and it is requested lazily: everything else works untouched, so a user who
/// never opens a zoom panel is never prompted.
@MainActor
enum ScreenCapture {

    enum Failure: Error {
        case noPermission
        case displayUnavailable
        case captureFailed(String)
    }

    /// Captures a screen-coordinate rect, excluding Omnipen's own windows so the
    /// overlay ink and the palette never end up inside the snapshot.
    static func image(of screenRect: CGRect) async throws -> CGImage {
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(screenRect) }) else {
            throw Failure.displayUnavailable
        }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
        } catch {
            // The only realistic reason this fails is a denied or undecided
            // permission, which is worth reporting as such.
            throw Failure.noPermission
        }

        guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else {
            throw Failure.displayUnavailable
        }

        let ownApp = content.applications.first {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: ownApp.map { [$0] } ?? [],
            exceptingWindows: []
        )

        let configuration = SCStreamConfiguration()
        // `sourceRect` is relative to the display's own top-left origin, while
        // `screenRect` is in AppKit's global bottom-left space.
        configuration.sourceRect = displayRelativeRect(screenRect, on: screen)
        configuration.scalesToFit = false

        // Ask for native resolution, so the magnified result is genuinely sharp
        // rather than an upscaled blur.
        let scale = screen.backingScaleFactor
        configuration.width = Int((configuration.sourceRect.width * scale).rounded())
        configuration.height = Int((configuration.sourceRect.height * scale).rounded())
        configuration.captureResolution = .best
        configuration.showsCursor = false

        do {
            return try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
        } catch {
            throw Failure.captureFailed(error.localizedDescription)
        }
    }

    /// Converts a global bottom-left rect into the top-left space of one display,
    /// which is what ScreenCaptureKit's `sourceRect` expects.
    private static func displayRelativeRect(_ rect: CGRect, on screen: NSScreen) -> CGRect {
        let frame = screen.frame
        let clipped = rect.intersection(frame)
        return CGRect(
            x: clipped.minX - frame.minX,
            y: frame.maxY - clipped.maxY,
            width: clipped.width,
            height: clipped.height
        )
    }

    /// Surfaces a denial in a way that points at the fix, since macOS shows its
    /// own prompt only once and silently refuses afterwards.
    static func reportFailure(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning

        switch error {
        case Failure.noPermission:
            alert.messageText = "Omnipen needs Screen Recording access"
            alert.informativeText = """
                The snapshot and blur tools read pixels from the screen, which \
                macOS gates behind Screen Recording.

                Open System Settings > Privacy & Security > Screen & System Audio \
                Recording and enable Omnipen, then try again. Drawing, shapes, and \
                text keep working without it.
                """
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Not Now")

            NSApp.activate()
            if alert.runModal() == .alertFirstButtonReturn,
               let url = URL(
                   string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
               ) {
                NSWorkspace.shared.open(url)
            }
            NSApp.deactivate()

        default:
            alert.messageText = "Could not capture the screen"
            alert.informativeText = String(describing: error)
            alert.addButton(withTitle: "OK")
            NSApp.activate()
            alert.runModal()
            NSApp.deactivate()
        }
    }
}
