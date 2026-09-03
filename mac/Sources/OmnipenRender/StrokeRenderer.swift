import CoreGraphics
import OmnipenCore

public enum StrokeRenderer {

    public static func cgColor(_ color: InkColor, opaque: Bool = false) -> CGColor {
        CGColor(
            srgbRed: color.red,
            green: color.green,
            blue: color.blue,
            alpha: opaque ? 1 : color.alpha
        )
    }

    /// `Smoothing` emits quadratic curves, elevated to cubics here because
    /// `CGPath` has no quadratic primitive taking an implicit current point. The
    /// elevation is exact: a quadratic is a cubic whose control points sit
    /// two-thirds of the way from each endpoint toward the shared control point.
    public static func cgPath(for stroke: Stroke) -> CGPath {
        let path = CGMutablePath()
        var current = CGPoint.zero

        for segment in Smoothing.path(for: stroke.points) {
            switch segment {
            case .move(let point):
                path.move(to: point)
                current = point
            case .line(let point):
                path.addLine(to: point)
                current = point
            case .quad(let end, let control):
                path.addCurve(
                    to: end,
                    control1: CGPoint(
                        x: current.x + 2.0 / 3.0 * (control.x - current.x),
                        y: current.y + 2.0 / 3.0 * (control.y - current.y)
                    ),
                    control2: CGPoint(
                        x: end.x + 2.0 / 3.0 * (control.x - end.x),
                        y: end.y + 2.0 / 3.0 * (control.y - end.y)
                    )
                )
                current = end
            }
        }
        return path
    }

    public static func draw(_ stroke: Stroke, in context: CGContext) {
        guard !stroke.points.isEmpty else { return }

        context.saveGState()
        defer { context.restoreGState() }

        context.setLineWidth(stroke.width)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        guard stroke.tool == .highlighter else {
            context.setStrokeColor(cgColor(stroke.color))
            context.addPath(cgPath(for: stroke))
            context.strokePath()
            return
        }

        // Stroked opaque inside a transparency layer, then composited once at the
        // tool's alpha. Stroking translucently instead would darken every place
        // the stroke crosses itself, which a real highlighter does not do.
        context.setAlpha(stroke.color.alpha)
        context.setBlendMode(.multiply)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setStrokeColor(cgColor(stroke.color, opaque: true))
        context.addPath(cgPath(for: stroke))
        context.strokePath()
        context.endTransparencyLayer()
    }
}
