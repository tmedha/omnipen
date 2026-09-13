import AppKit
import Carbon.HIToolbox
import Combine
import OmnipenCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let state = AppState()
    private var overlays: OverlayCoordinator!
    private var statusItem: StatusItemController!
    private var palette: PaletteController!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Also set via LSUIElement in Info.plist; repeated here so the
        // un-bundled binary behaves the same.
        NSApp.setActivationPolicy(.accessory)

        overlays = OverlayCoordinator(state: state)

        palette = PaletteController(
            state: state,
            actions: PaletteActions(
                undo: { [weak self] in self?.overlays.undo() },
                clearAll: { [weak self] in self?.overlays.clearAll() }
            )
        )

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

        #if DEBUG
        installDebugModeControl()
        #endif

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

        for (keyCode, tool) in Self.toolKeys {
            hotKeys.register(keyCode, group: .armed) { [weak self] in
                self?.state.setTool(tool)
            }
        }

        for (offset, keyCode) in Self.digitKeys.enumerated() {
            hotKeys.register(keyCode, group: .armed) { [weak self] in
                self?.state.selectColor(index: offset)
            }
        }

        hotKeys.register(kVK_ANSI_LeftBracket, group: .armed) { [weak self] in
            self?.state.adjustWidth(by: -Settings.strokeWidthStep)
        }
        hotKeys.register(kVK_ANSI_RightBracket, group: .armed) { [weak self] in
            self?.state.adjustWidth(by: Settings.strokeWidthStep)
        }
    }

    #if DEBUG
    /// Drives the mode from a script. The real entry points are global hotkeys,
    /// which cannot be synthesised without the Accessibility permission, so
    /// there is otherwise no way to exercise the overlay and palette lifecycle
    /// in an automated check. Compiled out of release builds.
    private func installDebugModeControl() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.omnipen.debug.mode"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch note.object as? String {
                case "armed": self.state.arm()
                case "passthrough": self.state.mode == .armed ? self.state.stepDown() : self.state.arm()
                case "off": self.state.disarm()
                default: break
                }
            }
        }
    }
    #endif

    /// Bare keys, so these may only ever be registered in the `armed` group.
    private static let toolKeys: [(Int, ToolKind)] = [
        (kVK_ANSI_P, .pen),
        (kVK_ANSI_H, .highlighter),
        (kVK_ANSI_E, .eraser),
    ]

    private static let digitKeys = [
        kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4,
        kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8,
    ]
}
