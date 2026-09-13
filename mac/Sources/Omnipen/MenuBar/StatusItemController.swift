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
        addToolItems(to: menu)
        menu.addItem(colorItem())
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

    /// The menu mirrors the palette rather than offering a second, divergent set
    /// of controls, so either route leaves the app in the same state.
    private func addToolItems(to menu: NSMenu) {
        for (index, tool) in Settings.allTools.enumerated() {
            let menuItem = NSMenuItem(
                title: tool.displayName,
                action: #selector(selectTool(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.tag = index
            menuItem.image = NSImage(
                systemSymbolName: tool.symbolName,
                accessibilityDescription: tool.displayName
            )
            menuItem.state = (state.tool == tool && state.mode == .armed) ? .on : .off
            menu.addItem(menuItem)
        }
    }

    private func colorItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Colour", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for (index, swatch) in Settings.swatches.enumerated() {
            let menuItem = NSMenuItem(
                title: "Colour \(index + 1)",
                action: #selector(selectColor(_:)),
                keyEquivalent: "\(index + 1)"
            )
            menuItem.keyEquivalentModifierMask = []
            menuItem.target = self
            menuItem.tag = index
            menuItem.image = Self.swatchImage(swatch)
            menuItem.state = state.colorIndex == index ? .on : .off
            submenu.addItem(menuItem)
        }

        parent.submenu = submenu
        parent.image = Self.swatchImage(state.color)
        return parent
    }

    private static func swatchImage(_ color: InkColor) -> NSImage {
        let size = NSSize(width: 12, height: 12)
        return NSImage(size: size, flipped: false) { rect in
            NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1).setFill()
            NSBezierPath(ovalIn: rect).fill()
            NSColor.tertiaryLabelColor.setStroke()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.25, dy: 0.25)).stroke()
            return true
        }
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

    @objc private func selectTool(_ sender: NSMenuItem) {
        guard Settings.allTools.indices.contains(sender.tag) else { return }
        state.setTool(Settings.allTools[sender.tag])
    }

    @objc private func selectColor(_ sender: NSMenuItem) {
        state.selectColor(index: sender.tag)
    }

    @objc private func undoInk() { actions.undo() }
    @objc private func redoInk() { actions.redo() }
    @objc private func clearAll() { actions.clearAll() }
    @objc private func quit() { NSApp.terminate(nil) }
}
