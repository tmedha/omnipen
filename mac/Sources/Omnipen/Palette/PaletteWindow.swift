import AppKit
import SwiftUI

/// The floating tool palette.
///
/// Sits one level above the overlay canvases so its clicks are never swallowed
/// by the drawing surface underneath, and like the overlay it is a
/// `.nonactivatingPanel` so using it does not pull focus from the app being
/// annotated.
final class PaletteWindow: NSPanel {

    private let hosting: NSHostingView<PaletteView>

    init(state: AppState, model: PaletteModel, actions: PaletteActions) {
        hosting = PaletteHostingView(rootView: PaletteView(state: state, model: model, actions: actions))
        hosting.translatesAutoresizingMaskIntoConstraints = false

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        // `.behindWindow` samples whatever is on screen underneath, which is what
        // makes the palette legible over both a white document and a dark IDE.
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = PaletteMetrics.cornerRadius
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 0.5
        effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor

        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])

        contentView = effect
    }

    /// Key status lets SwiftUI controls track properly. On a non-activating panel
    /// this does not activate Omnipen, and because the app stays inactive the
    /// panel never steals keystrokes from the app being annotated.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Resizes to the SwiftUI content, anchored at the top-left so opening the
    /// colour row grows the panel downward instead of making the bar jump.
    func fitToContent() {
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        guard size.width > 0, size.height > 0, size != frame.size else { return }

        var updated = frame
        updated.origin.y += updated.height - size.height
        updated.size = size
        setFrame(updated, display: true)
    }
}

/// Omnipen is never the active app, so without this the first click on the
/// palette would be consumed activating it instead of pressing the button.
private final class PaletteHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
