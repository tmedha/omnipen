import AppKit
import Carbon.HIToolbox
import Combine
import OmnipenCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let state = AppState()
    private var overlays: OverlayCoordinator!
    private var statusItem: StatusItemController!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Also set via LSUIElement in Info.plist; repeated here so the
        // un-bundled binary behaves the same.
        NSApp.setActivationPolicy(.accessory)

        overlays = OverlayCoordinator(state: state)

        statusItem = StatusItemController(
            state: state,
            actions: MenuActions(
                toggleArmed: { [weak self] in self?.state.toggleArmed() },
                undo: { [weak self] in self?.overlays.undo() },
                redo: { [weak self] in self?.overlays.redo() },
                clearAll: { [weak self] in self?.overlays.clearAll() },
                hasInk: { [weak self] in self?.overlays.hasInk ?? false }
            )
        )

        registerGlobalHotKeys()

        // Bare keys are captured system-wide once registered, so they may only be
        // live while the pen is armed.
        state.$mode
            .removeDuplicates()
            .sink { [weak self] mode in self?.updateArmedHotKeys(for: mode) }
            .store(in: &cancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyManager.shared.unregisterGroup(.armed)
        HotKeyManager.shared.unregisterGroup(.global)
    }

    private func registerGlobalHotKeys() {
        let hotKeys = HotKeyManager.shared

        hotKeys.register(kVK_ANSI_D, modifiers: Mod.option | Mod.command) { [weak self] in
            self?.state.toggleArmed()
        }

        hotKeys.register(kVK_ANSI_D, modifiers: Mod.shift | Mod.option | Mod.command) { [weak self] in
            self?.overlays.clearAll()
        }
    }

    private func updateArmedHotKeys(for mode: AppState.Mode) {
        let hotKeys = HotKeyManager.shared
        hotKeys.unregisterGroup(.armed)
        guard mode.showsOverlay else { return }

        // Registered only while the overlay is up, so Esc is untouched otherwise.
        hotKeys.register(kVK_Escape, group: .armed) { [weak self] in
            self?.state.stepDown()
        }

        guard mode.capturesMouse else { return }

        hotKeys.register(kVK_ANSI_Z, modifiers: Mod.command, group: .armed) { [weak self] in
            self?.overlays.undo()
        }
        hotKeys.register(kVK_ANSI_Z, modifiers: Mod.shift | Mod.command, group: .armed) { [weak self] in
            self?.overlays.redo()
        }
    }
}
