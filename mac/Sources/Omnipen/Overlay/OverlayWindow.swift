import AppKit
import OmnipenCore

/// A window whose canvas may take keyboard focus for text entry.
@MainActor
protocol TextFocusable: NSWindow {
    var allowsKeyStatus: Bool { get set }
}

/// A full-screen transparent panel, one per display.
///
/// The `.nonactivatingPanel` style mask is the load-bearing choice here: it lets
/// the panel receive mouse events without activating Omnipen, so Chrome or VS Code
/// underneath keeps focus and keeps its own menu bar while you draw over it.
final class OverlayWindow: NSPanel, TextFocusable {

    let canvas: CanvasView

    /// Text editing is the only feature that needs real keyboard focus, so key
    /// status stays off until a text box opens.
    var allowsKeyStatus = false

    init(screen: NSScreen, store: StrokeStore, state: AppState) {
        canvas = CanvasView(frame: CGRect(origin: .zero, size: screen.frame.size), store: store)
        canvas.state = state

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true

        // Above the menu bar and other apps' full-screen spaces.
        level = .screenSaver

        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        contentView = canvas
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { allowsKeyStatus }
    override var canBecomeMain: Bool { false }

    func reposition(to screen: NSScreen) {
        setFrame(screen.frame, display: true)
        canvas.frame = CGRect(origin: .zero, size: screen.frame.size)
        canvas.refresh()
    }

    func setCapturesMouse(_ captures: Bool) {
        ignoresMouseEvents = !captures
        // Cursor rects go stale across a passthrough flip.
        canvas.updateTrackingAreas()
        invalidateCursorRects(for: canvas)
    }
}
