import AppKit
import Combine
import OmnipenCore

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

/// Owns one overlay panel per attached display. Ink stores are keyed by display
/// ID and outlive their windows, so unplugging a monitor and plugging it back in
/// restores what was drawn on it.
@MainActor
final class OverlayCoordinator: NSObject, CanvasViewDelegate {

    private let state: AppState
    private var windows: [CGDirectDisplayID: OverlayWindow] = [:]
    private var stores: [CGDirectDisplayID: StrokeStore] = [:]
    private var cancellables = Set<AnyCancellable>()

    /// Undo and redo act on the display most recently drawn on.
    private var lastEditedDisplay: CGDirectDisplayID?

    init(state: AppState) {
        self.state = state
        super.init()

        state.$mode
            .removeDuplicates()
            .sink { [weak self] mode in self?.apply(mode: mode) }
            .store(in: &cancellables)

        state.$tool
            .removeDuplicates()
            .sink { [weak self] _ in self?.refreshCursors() }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    /// Creates a panel for each attached display, reusing any that already exist.
    private func ensureWindows() {
        let screens = NSScreen.screens
        let liveIDs = Set(screens.map(\.displayID))

        // Tear down panels for departed displays, but keep their ink.
        for (id, window) in windows where !liveIDs.contains(id) {
            close(window)
            windows[id] = nil
        }

        for screen in screens {
            let id = screen.displayID
            if let existing = windows[id] {
                existing.reposition(to: screen)
                continue
            }

            let store = stores[id] ?? StrokeStore()
            stores[id] = store

            let window = OverlayWindow(screen: screen, store: store, state: state)
            window.canvas.delegate = self
            windows[id] = window
        }
    }

    /// A full-screen window backing store costs roughly 95 MB per Retina display,
    /// so a disarmed Omnipen holds no panels at all. Ink survives in `stores`.
    private func teardownWindows() {
        for window in windows.values { close(window) }
        windows.removeAll()
    }

    private func close(_ window: OverlayWindow) {
        window.orderOut(nil)
        window.contentView = nil
        window.close()
    }

    @objc private func screenParametersChanged() {
        guard state.mode.showsOverlay else { return }
        ensureWindows()
        apply(mode: state.mode)
    }

    private func apply(mode: AppState.Mode) {
        guard mode.showsOverlay else {
            teardownWindows()
            NSCursor.arrow.set()
            return
        }

        ensureWindows()
        for window in windows.values {
            window.setCapturesMouse(mode.capturesMouse)
            window.orderFrontRegardless()
        }
        if !mode.capturesMouse {
            NSCursor.arrow.set()
        }
    }

    private func refreshCursors() {
        for window in windows.values {
            window.invalidateCursorRects(for: window.canvas)
        }
    }

    func canvasViewDidEdit(_ canvas: CanvasView) {
        lastEditedDisplay = windows.first { $0.value.canvas === canvas }?.key
    }

    /// The last store drawn into, falling back to the display under the cursor.
    private var activeStore: StrokeStore? {
        if let id = lastEditedDisplay, let store = stores[id], store.canUndo || store.canRedo {
            return store
        }
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) {
            return stores[screen.displayID]
        }
        return stores[NSScreen.main?.displayID ?? 0]
    }

    func undo() {
        guard let store = activeStore, store.undo() else { return }
        refreshAll()
    }

    func redo() {
        guard let store = activeStore, store.redo() else { return }
        refreshAll()
    }

    func clearAll() {
        var changed = false
        for store in stores.values where store.clear() { changed = true }
        if changed { refreshAll() }
    }

    var hasInk: Bool {
        stores.values.contains { !$0.isEmpty }
    }

    private func refreshAll() {
        for window in windows.values { window.canvas.refresh() }
    }
}
