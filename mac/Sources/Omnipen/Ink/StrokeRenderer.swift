import AppKit
import OmnipenCore

/// Turns the abstract stroke model into AppKit drawing.
enum StrokeRenderer {

    static func nsColor(_ color: InkColor) -> NSColor {
        NSColor(
            srgbRed: color.red,
            green: color.green,
            blue: color.blue,
            alpha: color.alpha
        )
    }

    /// `Smoothing` emits quadratic curves, elevated to cubics here rather than
    /// relying on `NSBezierPath.curve(to:controlPoint:)`. The elevation is exact:
    /// a quadratic is a cubic whose control points sit two-thirds of the way from
    /// each endpoint toward the shared control point.
    static func path(for stroke: Stroke) -> NSBezierPath {
        let path = NSBezierPath()
        var current = CGPoint.zero

        for segment in Smoothing.path(for: stroke.points) {
            switch segment {
            case .move(let point):
                path.move(to: point)
                current = point
            case .line(let point):
                path.line(to: point)
                current = point
            case .quad(let end, let control):
                let c1 = CGPoint(
                    x: current.x + 2.0 / 3.0 * (control.x - current.x),
                    y: current.y + 2.0 / 3.0 * (control.y - current.y)
                )
                let c2 = CGPoint(
                    x: end.x + 2.0 / 3.0 * (control.x - end.x),
                    y: end.y + 2.0 / 3.0 * (control.y - end.y)
                )
                path.curve(to: end, controlPoint1: c1, controlPoint2: c2)
                current = end
            }
        }

        path.lineWidth = stroke.width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        return path
    }

    static func draw(_ stroke: Stroke) {
        guard !stroke.points.isEmpty else { return }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        // Multiply so the highlighter tints what is underneath rather than
        // covering it.
        if stroke.tool == .highlighter {
            NSGraphicsContext.current?.compositingOperation = .multiply
        }

        nsColor(stroke.color).setStroke()
        path(for: stroke).stroke()
    }
}
