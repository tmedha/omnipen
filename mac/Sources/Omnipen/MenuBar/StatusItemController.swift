import AppKit
import Combine
import OmnipenCore

/// Passed in as closures so the status item needs no reference to the overlay
/// coordinator.
struct MenuActions {
    let toggleArmed: () -> Void
    let undo: () -> Void
    let redo: () -> Void
    let clearAll: () -> Void
    let hasInk: () -> Bool
}

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {

    private let statusItem: NSStatusItem
    private let state: AppState
    private let actions: MenuActions
    private var cancellables = Set<AnyCancellable>()

    init(state: AppState, actions: MenuActions) {
        self.state = state
        self.actions = actions
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        state.$mode
            .removeDuplicates()
            .sink { [weak self] mode in self?.updateIcon(for: mode) }
            .store(in: &cancellables)
    }

    private func updateIcon(for mode: AppState.Mode) {
        guard let button = statusItem.button else { return }

        let symbol = mode == .off ? "pencil.tip.crop.circle" : "pencil.tip.crop.circle.fill"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Omnipen")
        image?.isTemplate = true

        button.image = image
        button.toolTip = switch mode {
        case .off: "Omnipen: press ⌥⌘D to draw"
        case .armed: "Omnipen: drawing (Esc to click through)"
        case .passthrough: "Omnipen: annotations visible, clicks passing through"
        }
    }

    /// Rebuilt on every open so enabled states and titles are never stale.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let toggleTitle = state.mode == .off ? "Start Drawing" : "Stop Drawing"
        menu.addItem(item(toggleTitle, key: "d", modifiers: [.option, .command], action: #selector(toggleArmed)))

        if state.mode == .armed {
            let hint = NSMenuItem(title: "Press Esc to click through", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
        }

        menu.addItem(.separator())

        let undo = item("Undo", key: "z", modifiers: [.command], action: #selector(undoInk))
        undo.isEnabled = actions.hasInk()
        menu.addItem(undo)

        menu.addItem(item("Redo", key: "z", modifiers: [.command, .shift], action: #selector(redoInk)))

        let clear = item("Clear All", key: "d", modifiers: [.shift, .option, .command], action: #selector(clearAll))
        clear.isEnabled = actions.hasInk()
        menu.addItem(clear)

        menu.addItem(.separator())
        menu.addItem(item("Quit Omnipen", key: "q", modifiers: [.command], action: #selector(quit)))
    }

    private func item(
        _ title: String,
        key: String,
        modifiers: NSEvent.ModifierFlags,
        action: Selector
    ) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.keyEquivalentModifierMask = modifiers
        menuItem.target = self
        return menuItem
    }

    @objc private func toggleArmed() { actions.toggleArmed() }
    @objc private func undoInk() { actions.undo() }
    @objc private func redoInk() { actions.redo() }
    @objc private func clearAll() { actions.clearAll() }
    @objc private func quit() { NSApp.terminate(nil) }
}
