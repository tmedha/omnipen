import AppKit
import OmnipenCore

@MainActor
protocol CanvasViewDelegate: AnyObject {
    /// Lets the coordinator route undo and redo to the display last touched.
    func canvasViewDidEdit(_ canvas: CanvasView)
}

/// The transparent drawing surface filling one display. Coordinates are
/// unflipped to match Core Graphics, so stroke points move between the view, the
/// bitmap cache, and screen space without a Y-axis flip at every boundary.
@MainActor
final class CanvasView: NSView {

    let store: StrokeStore
    weak var state: AppState?
    weak var delegate: CanvasViewDelegate?

    private var liveStroke: Stroke?
    private var trackingArea: NSTrackingArea?

    init(frame: CGRect, store: StrokeStore) {
        self.store = store
        super.init(frame: frame)
        wantsLayer = true
        layer?.isOpaque = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { false }
    override var isOpaque: Bool { false }

    /// The overlay is never the active app, so the first click would otherwise
    /// be swallowed as an activation click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        for stroke in store.strokes where stroke.bounds.intersects(dirtyRect) {
            StrokeRenderer.draw(stroke)
        }
        if let liveStroke {
            StrokeRenderer.draw(liveStroke)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let state, state.mode.capturesMouse else { return }
        let point = convert(event.locationInWindow, from: nil)

        switch state.tool {
        case .eraser:
            erase(at: point)
        default:
            liveStroke = Stroke(
                tool: state.tool,
                color: state.inkColor(for: state.tool),
                width: state.inkWidth(for: state.tool),
                points: [point]
            )
            setNeedsDisplay(invalidation(from: point, to: point, width: state.inkWidth(for: state.tool)))
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let state, state.mode.capturesMouse else { return }
        let point = convert(event.locationInWindow, from: nil)

        if state.tool == .eraser {
            erase(at: point)
            return
        }

        guard var stroke = liveStroke else { return }
        let previous = stroke.points.last ?? point
        stroke.points.append(point)
        liveStroke = stroke
        setNeedsDisplay(invalidation(from: previous, to: point, width: stroke.width))
    }

    override func mouseUp(with event: NSEvent) {
        guard var stroke = liveStroke else { return }
        liveStroke = nil

        stroke.points = Smoothing.simplify(
            stroke.points,
            minimumDistance: Settings.minimumPointDistance
        )
        store.commit(stroke)
        delegate?.canvasViewDidEdit(self)
        setNeedsDisplay(stroke.bounds.insetBy(dx: -stroke.width, dy: -stroke.width))
    }

    private func erase(at point: CGPoint) {
        let removed = store.erase(at: point, radius: Settings.eraserRadius)
        guard !removed.isEmpty else { return }
        delegate?.canvasViewDidEdit(self)
        // Removing ink uncovers what was beneath, so the region must be rebuilt
        // rather than painted over.
        needsDisplay = true
    }

    /// Smoothing bulges the curve past the straight segment, so this pads by
    /// more than the nib width.
    private func invalidation(from a: CGPoint, to b: CGPoint, width: Double) -> CGRect {
        let pad = width + 8
        return CGRect(
            x: min(a.x, b.x) - pad,
            y: min(a.y, b.y) - pad,
            width: abs(b.x - a.x) + pad * 2,
            height: abs(b.y - a.y) + pad * 2
        )
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }

        // `.activeAlways`: Omnipen is never the active app, so the default
        // `.activeInKeyWindow` would never fire.
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .cursorUpdate, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
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
        return state.tool == .eraser ? .disappearingItem : .crosshair
    }

    func refresh() {
        needsDisplay = true
    }
}
