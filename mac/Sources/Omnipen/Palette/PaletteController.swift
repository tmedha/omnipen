import AppKit
import Combine

/// Shows and hides the palette with the app's mode, and remembers where it was
/// left. Like the overlays, the window is built on first use rather than at
/// launch so a disarmed Omnipen owns nothing.
@MainActor
final class PaletteController {

    private let state: AppState
    private let actions: PaletteActions
    private let model = PaletteModel()
    private var window: PaletteWindow?
    private var cancellables = Set<AnyCancellable>()

    private static let positionKey = "palette.origin"

    init(state: AppState, actions: PaletteActions) {
        self.state = state
        self.actions = actions

        state.$mode
            .removeDuplicates()
            .sink { [weak self] mode in self?.apply(mode: mode) }
            .store(in: &cancellables)

        // The panel is sized in AppKit, so any SwiftUI state that changes the
        // layout has to be followed by a refit.
        model.objectWillChange
            .sink { [weak self] in
                DispatchQueue.main.async { self?.window?.fitToContent() }
            }
            .store(in: &cancellables)
    }

    private func apply(mode: AppState.Mode) {
        // The palette stays up in passthrough: it is the only affordance for
        // getting back to drawing, and it is what shows that clicks are currently
        // falling through to the app underneath.
        guard mode.showsOverlay else {
            hide()
            return
        }
        show()
    }

    private func show() {
        let panel = window ?? makeWindow()
        panel.fitToContent()
        panel.setFrameOrigin(clamped(savedOrigin ?? defaultOrigin(for: panel)))
        panel.orderFrontRegardless()
    }

    private func hide() {
        guard let window else { return }
        savedOrigin = window.frame.origin
        window.orderOut(nil)
        window.contentView = nil
        window.close()
        self.window = nil
    }

    private func makeWindow() -> PaletteWindow {
        let panel = PaletteWindow(state: state, model: model, actions: actions)
        window = panel
        return panel
    }

    private func defaultOrigin(for panel: PaletteWindow) -> NSPoint {
        guard let screen = NSScreen.main else { return NSPoint(x: 200, y: 200) }
        return NSPoint(
            x: screen.frame.midX - panel.frame.width / 2,
            y: screen.frame.minY + 120
        )
    }

    /// Keeps the palette reachable if it was last left on a display that is gone.
    private func clamped(_ origin: NSPoint) -> NSPoint {
        guard let size = window?.frame.size else { return origin }
        let candidate = NSRect(origin: origin, size: size)

        if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(candidate) }) {
            return origin
        }
        return window.map(defaultOrigin) ?? origin
    }

    private var savedOrigin: NSPoint? {
        get {
            guard let stored = UserDefaults.standard.string(forKey: Self.positionKey) else {
                return nil
            }
            return NSPointFromString(stored)
        }
        set {
            guard let newValue else { return }
            UserDefaults.standard.set(NSStringFromPoint(newValue), forKey: Self.positionKey)
        }
    }
}
