import AppKit
import OmnipenCore

/// A floating window showing a magnified screen capture that can be annotated.
///
/// The surrounding screen stays visible, so viewers keep their context. The
/// annotation surface is the same `CanvasView` the overlays use, with the capture
/// as its background and a content scale so ink keeps its place on the image when
/// the panel is resized.
final class ZoomPanel: NSPanel, TextFocusable {

    let canvas: CanvasView

    /// Size of the captured region in points, which is the ink coordinate space.
    private let regionSize: CGSize
    private let container = ZoomContainerView()
    private let header = NSVisualEffectView()
    private let closeButton = NSButton()
    private let scaleLabel = NSTextField(labelWithString: "")
    private let onClose: (ZoomPanel) -> Void

    private static let headerHeight: CGFloat = 24

    init(
        image: CGImage,
        regionSize: CGSize,
        origin: CGPoint,
        magnification: CGFloat,
        state: AppState,
        onClose: @escaping (ZoomPanel) -> Void
    ) {
        self.regionSize = regionSize
        self.onClose = onClose

        let contentSize = CGSize(
            width: (regionSize.width * magnification).rounded(),
            height: (regionSize.height * magnification).rounded() + Self.headerHeight
        )

        canvas = CanvasView(frame: .zero, store: StrokeStore())
        canvas.state = state
        canvas.backgroundImage = image

        super.init(
            contentRect: CGRect(origin: origin, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        // Above the overlays but below the palette, so the tools stay reachable.
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        // Resizing is the zoom control, so the capture must not distort.
        aspectRatio = contentSize
        minSize = CGSize(width: 120, height: 120 * contentSize.height / contentSize.width)

        configureChrome()
        container.panel = self
        container.addSubview(canvas)
        container.addSubview(header)
        contentView = container
    }

    var allowsKeyStatus = false

    override var canBecomeKey: Bool { allowsKeyStatus }
    override var canBecomeMain: Bool { false }

    private func configureChrome() {
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor

        header.material = .hudWindow
        header.blendingMode = .withinWindow
        header.state = .active

        scaleLabel.font = .systemFont(ofSize: 10, weight: .medium)
        scaleLabel.textColor = .secondaryLabelColor
        scaleLabel.alignment = .center

        closeButton.bezelStyle = .circular
        closeButton.isBordered = false
        closeButton.image = NSImage(
            systemSymbolName: "xmark.circle.fill",
            accessibilityDescription: "Close"
        )
        closeButton.target = self
        closeButton.action = #selector(closePanel)

        header.addSubview(scaleLabel)
        header.addSubview(closeButton)
    }

    /// Called by the container on every layout pass.
    func layoutChrome() {
        let size = container.bounds.size
        let canvasHeight = max(0, size.height - Self.headerHeight)

        canvas.frame = CGRect(x: 0, y: 0, width: size.width, height: canvasHeight)
        header.frame = CGRect(
            x: 0,
            y: canvasHeight,
            width: size.width,
            height: Self.headerHeight
        )
        closeButton.frame = CGRect(x: 4, y: 4, width: 16, height: 16)
        scaleLabel.frame = CGRect(x: 24, y: 5, width: size.width - 48, height: 14)

        guard regionSize.width > 0 else { return }
        let scale = size.width / regionSize.width
        canvas.contentScale = scale
        scaleLabel.stringValue = String(format: "%.1f×", scale)
    }

    /// Scroll to zoom, resizing about the panel's centre so the subject does not
    /// walk off screen.
    func zoom(by factor: CGFloat) {
        let current = frame
        let proposed = CGSize(
            width: current.width * factor,
            height: current.height * factor
        )
        guard proposed.width >= minSize.width,
              proposed.width <= (screen?.frame.width ?? 4000) * 1.5
        else { return }

        setFrame(
            CGRect(
                x: current.midX - proposed.width / 2,
                y: current.midY - proposed.height / 2,
                width: proposed.width,
                height: proposed.height
            ),
            display: true
        )
    }

    @objc private func closePanel() {
        canvas.commitPendingText()
        onClose(self)
    }

    func dismiss() {
        canvas.commitPendingText()
        orderOut(nil)
        contentView = nil
        close()
    }
}

/// Hosts the capture and its chrome, and turns scroll and drag into window moves.
private final class ZoomContainerView: NSView {
    weak var panel: ZoomPanel?

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        panel?.layoutChrome()
    }

    override func scrollWheel(with event: NSEvent) {
        // Trackpad deltas are small and continuous; a wheel click is coarse.
        let step = event.hasPreciseScrollingDeltas ? 0.004 : 0.04
        let factor = 1 + event.scrollingDeltaY * step
        guard abs(factor - 1) > 0.0001 else { return }
        panel?.zoom(by: factor)
    }

    /// Dragging anywhere on the header moves the panel. The canvas below it is
    /// for annotating, so it must not also drag.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let panel, point.y > bounds.height - 24 else { return }
        panel.performDrag(with: event)
    }
}
