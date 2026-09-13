import AppKit
import OmnipenCore
import OmnipenRender

@MainActor
protocol CanvasViewDelegate: AnyObject {
    func canvasViewDidEdit(_ canvas: CanvasView)

    /// A snapshot region was dragged out, in global screen coordinates.
    func canvasView(_ canvas: CanvasView, didSelectRegion screenRect: CGRect)
}

/// Coordinates are unflipped to match Core Graphics, so stroke points move
/// between the view, the bitmap cache, and screen space without a Y-axis flip at
/// every boundary.
@MainActor
final class CanvasView: NSView {

    let store: StrokeStore
    weak var state: AppState?
    weak var delegate: CanvasViewDelegate?

    private let ink = InkBitmap()
    private var liveStroke: Stroke?
    private var trackingArea: NSTrackingArea?

    private var dragAnchor: CGPoint?
    private var previousPreviewBounds: CGRect = .null

    private var selectionAnchor: CGPoint?
    private var selectionRect: CGRect = .null

    /// Kept here rather than on the stroke, so the model stays a plain Codable
    /// value.
    private var redactions: [Stroke.ID: CGImage] = [:]

    private var transients: TransientTools!
    private var textEntry: TextEntry?

    var backgroundImage: CGImage?

    /// Overlays leave this at 1. The zoom panel sets it so annotations keep their
    /// place on the captured image across a resize.
    var contentScale: CGFloat = 1 {
        didSet {
            guard contentScale != oldValue else { return }
            ink.release()
            needsDisplay = true
        }
    }

    init(frame: CGRect, store: StrokeStore) {
        self.store = store
        super.init(frame: frame)
        wantsLayer = true
        layer?.isOpaque = false
        transients = TransientTools(host: self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { false }
    override var isOpaque: Bool { false }

    /// The overlay is never the active app, so the first click would otherwise
    /// be swallowed as an activation click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        if let backgroundImage {
            context.draw(backgroundImage, in: bounds)
        }

        context.saveGState()
        defer { context.restoreGState() }
        if contentScale != 1 {
            context.scaleBy(x: contentScale, y: contentScale)
        }

        let strokes = store.strokes
        let inkStrokes = strokes.filter { $0.tool != .blur }

        // Baking assumes a 1:1 bitmap, and a zoom panel never holds enough
        // strokes for the direct path to matter.
        if contentScale == 1 && inkStrokes.count >= Settings.bakeThreshold {
            ink.configure(size: bounds.size, scale: window?.backingScaleFactor ?? 2)
            if ink.isStale {
                ink.rebuild(with: inkStrokes)
            }
            // Both are bottom-left Core Graphics contexts, so the baked image
            // round-trips without a flip.
            if let image = ink.image {
                context.draw(image, in: bounds)
            }
        } else {
            ink.release()
            for stroke in inkStrokes where stroke.bounds.intersects(dirtyRect) {
                StrokeRenderer.draw(stroke, in: context)
            }
        }

        // Drawn last, so a redaction is never partly covered by ink laid down
        // afterwards.
        for stroke in strokes where stroke.tool == .blur {
            drawRedaction(stroke, in: context)
        }

        if let liveStroke {
            StrokeRenderer.draw(liveStroke, in: context)
        }

        if !selectionRect.isNull, !selectionRect.isEmpty {
            drawMarquee(selectionRect, in: context)
        }
    }

    /// Falls back to an opaque block if the pixels are missing: a redaction that
    /// silently failed to render would expose what it was meant to hide.
    private func drawRedaction(_ stroke: Stroke, in context: CGContext) {
        guard stroke.points.count >= 2,
              let start = stroke.points.first,
              let end = stroke.points.last
        else { return }

        let rect = Geometry.rect(from: start, to: end, square: false)
        if let image = redactions[stroke.id] {
            context.draw(image, in: rect)
        } else {
            context.setFillColor(CGColor(gray: 0.22, alpha: 1))
            context.fill(rect)
        }
    }

    private func drawMarquee(_ rect: CGRect, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }

        let outside = CGMutablePath()
        outside.addRect(bounds)
        outside.addRect(rect)
        context.addPath(outside)
        context.setFillColor(CGColor(gray: 0, alpha: 0.28))
        context.fillPath(using: .evenOdd)

        context.setStrokeColor(CGColor(gray: 1, alpha: 0.95))
        context.setLineWidth(1)
        context.setLineDash(phase: 0, lengths: [5, 4])
        context.stroke(rect)
    }

    private func inkPoint(from event: NSEvent) -> CGPoint {
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard contentScale != 1 else { return viewPoint }
        return CGPoint(x: viewPoint.x / contentScale, y: viewPoint.y / contentScale)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        // Moved to a display with a different scale factor.
        ink.release()
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        ink.release()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard let state, state.mode.capturesMouse else { return }
        let point = inkPoint(from: event)

        if textEntry != nil {
            finishTextEntry()
            return
        }

        if state.tool == .eraser {
            erase(at: point)
            return
        }
        guard !transients.handlesCurrentTool else { return }

        if state.tool == .text {
            beginTextEntry(at: point)
            return
        }

        if state.tool == .snapshot {
            selectionAnchor = point
            selectionRect = .null
            return
        }

        let width = state.inkWidth(for: state.tool)
        liveStroke = Stroke(
            tool: state.tool,
            color: state.inkColor(for: state.tool),
            width: width,
            points: [point]
        )

        if state.tool.isDragShape {
            dragAnchor = point
            previousPreviewBounds = .null
        }
        setNeedsDisplay(invalidation(from: point, to: point, width: width))
    }

    override func mouseDragged(with event: NSEvent) {
        guard let state, state.mode.capturesMouse else { return }
        let point = inkPoint(from: event)

        if state.tool == .eraser {
            erase(at: point)
            return
        }
        if transients.handlesCurrentTool {
            transients.cursorMoved(to: point)
            return
        }

        if let anchor = selectionAnchor {
            selectionRect = Geometry.rect(from: anchor, to: point, square: false)
            // The dimmed surround spans the whole view, so a partial repaint would
            // leave the previous dimming behind.
            needsDisplay = true
            return
        }

        guard var stroke = liveStroke else { return }

        if let anchor = dragAnchor {
            stroke.points = [anchor, constrained(point, from: anchor, event: event, tool: stroke.tool)]
            liveStroke = stroke

            // A shape preview replaces itself rather than extending, so the region
            // the previous preview occupied has to be repainted too.
            let preview = stroke.bounds
            setNeedsDisplay(viewRect(previousPreviewBounds.union(preview).insetBy(dx: -4, dy: -4)))
            previousPreviewBounds = preview
            return
        }

        let previous = stroke.points.last ?? point
        stroke.points.append(point)
        liveStroke = stroke
        setNeedsDisplay(invalidation(from: previous, to: point, width: stroke.width))
    }

    private func constrained(
        _ point: CGPoint,
        from anchor: CGPoint,
        event: NSEvent,
        tool: ToolKind
    ) -> CGPoint {
        guard event.modifierFlags.contains(.shift) else { return point }

        switch tool {
        case .line, .arrow:
            return Geometry.snapToAxis(start: anchor, end: point)
        case .rectangle, .ellipse, .blur:
            let square = Geometry.rect(from: anchor, to: point, square: true)
            // Keep the corner on the side the drag actually went.
            return CGPoint(
                x: point.x < anchor.x ? square.minX : square.maxX,
                y: point.y < anchor.y ? square.minY : square.maxY
            )
        default:
            return point
        }
    }

    override func mouseUp(with event: NSEvent) {
        if selectionAnchor != nil {
            finishSelection()
            return
        }

        guard var stroke = liveStroke else { return }
        liveStroke = nil
        let wasDragShape = dragAnchor != nil
        dragAnchor = nil
        previousPreviewBounds = .null

        if wasDragShape, stroke.tool == .blur {
            dragAnchor = nil
            commitRedaction(stroke)
            return
        }

        if wasDragShape {
            // A click without a drag is a misclick, not a shape worth keeping.
            guard stroke.points.count == 2,
                  hypot(
                      stroke.points[1].x - stroke.points[0].x,
                      stroke.points[1].y - stroke.points[0].y
                  ) > 3
            else {
                needsDisplay = true
                return
            }
        } else {
            stroke.points = Smoothing.simplify(
                stroke.points,
                minimumDistance: Settings.minimumPointDistance
            )
        }

        store.commit(stroke)
        ink.bake(stroke)
        delegate?.canvasViewDidEdit(self)
        setNeedsDisplay(viewRect(stroke.bounds.insetBy(dx: -stroke.width, dy: -stroke.width)))
    }

    /// Committed as a stroke, so undo and the eraser treat a redaction like any
    /// other mark.
    private func commitRedaction(_ stroke: Stroke) {
        guard stroke.points.count >= 2,
              let start = stroke.points.first,
              let end = stroke.points.last,
              let window
        else { return }

        let rect = Geometry.rect(from: start, to: end, square: false)
        guard rect.width > 8, rect.height > 8 else {
            needsDisplay = true
            return
        }
        let screenRect = window.convertToScreen(convert(rect, to: nil))

        Task { [weak self] in
            do {
                let captured = try await ScreenCapture.image(of: screenRect)
                guard let self else { return }
                guard let pixelated = Redaction.pixelate(captured) else { return }
                self.redactions[stroke.id] = pixelated
                self.store.commit(stroke)
                self.delegate?.canvasViewDidEdit(self)
                self.needsDisplay = true
            } catch {
                ScreenCapture.reportFailure(error)
            }
        }
    }

    private func finishSelection() {
        let rect = selectionRect
        selectionAnchor = nil
        selectionRect = .null
        needsDisplay = true

        // Too small to be deliberate, and too small to magnify usefully.
        guard rect.width > 8, rect.height > 8, let window else { return }
        let inWindow = convert(rect, to: nil)
        delegate?.canvasView(self, didSelectRegion: window.convertToScreen(inWindow))
    }

    private func erase(at point: CGPoint) {
        let removed = store.erase(at: point, radius: Settings.eraserRadius)
        guard !removed.isEmpty else { return }
        delegate?.canvasViewDidEdit(self)
        // Removing ink uncovers what was beneath, so the bitmap must be rebuilt
        // rather than painted over.
        ink.markStale()
        needsDisplay = true
    }

    /// Smoothing bulges the curve past the straight segment, so this pads by
    /// more than the nib width.
    private func invalidation(from a: CGPoint, to b: CGPoint, width: Double) -> CGRect {
        let pad = width + 8
        return viewRect(
            CGRect(
                x: min(a.x, b.x) - pad,
                y: min(a.y, b.y) - pad,
                width: abs(b.x - a.x) + pad * 2,
                height: abs(b.y - a.y) + pad * 2
            )
        )
    }

    private func viewRect(_ rect: CGRect) -> CGRect {
        guard contentScale != 1 else { return rect }
        return CGRect(
            x: rect.minX * contentScale,
            y: rect.minY * contentScale,
            width: rect.width * contentScale,
            height: rect.height * contentScale
        ).insetBy(dx: -2, dy: -2)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }

        // `.activeAlways`: Omnipen is never the active app, so the default
        // `.activeInKeyWindow` would never fire.
        let area = NSTrackingArea(
            rect: bounds,
            options: [
                .activeAlways, .mouseEnteredAndExited, .mouseMoved,
                .cursorUpdate, .inVisibleRect,
            ],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        guard transients.handlesCurrentTool else { return }
        transients.cursorMoved(to: convert(event.locationInWindow, from: nil))
    }

    override func cursorUpdate(with event: NSEvent) {
        currentCursor.set()
    }

    override func mouseEntered(with event: NSEvent) {
        currentCursor.set()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    private var currentCursor: NSCursor {
        guard let state, state.mode.capturesMouse else { return .arrow }
        switch state.tool {
        case .eraser: return Cursors.eraser
        case .laser, .spotlight: return .arrow
        default: return .crosshair
        }
    }

    func syncTransients() {
        guard let state else { return }
        transients.update(
            tool: state.tool,
            isArmed: state.mode.capturesMouse,
            color: state.color,
            width: state.strokeWidth
        )
    }

    private func beginTextEntry(at point: CGPoint) {
        guard let state, let window = window as? any TextFocusable else { return }

        let entry = TextEntry(
            origin: point,
            color: state.color,
            width: state.strokeWidth
        ) { [weak self] _ in
            self?.finishTextEntry()
        }
        addSubview(entry)
        textEntry = entry

        // Keystrokes only reach the active app's key window, so this is the one
        // place Omnipen has to take focus.
        state.isEditingText = true
        window.allowsKeyStatus = true
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(entry)
    }

    private func finishTextEntry() {
        guard let entry = textEntry, let state else { return }
        textEntry = nil

        let typed = entry.string
        let origin = CGPoint(x: entry.frame.minX + 4, y: entry.frame.maxY)
        entry.removeFromSuperview()

        // Blocks the panel from taking key status again; deactivating the app is
        // what actually drops it.
        (window as? any TextFocusable)?.allowsKeyStatus = false
        state.isEditingText = false
        NSApp.deactivate()

        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            needsDisplay = true
            return
        }

        let stroke = Stroke(
            tool: .text,
            color: state.color,
            width: state.strokeWidth,
            points: [origin],
            text: typed,
            textSize: TextRenderer.measure(typed, width: state.strokeWidth)
        )

        store.commit(stroke)
        ink.bake(stroke)
        delegate?.canvasViewDidEdit(self)
        needsDisplay = true
    }

    func commitPendingText() {
        guard textEntry != nil else { return }
        finishTextEntry()
    }

    func refresh() {
        ink.markStale()
        needsDisplay = true
    }
}
