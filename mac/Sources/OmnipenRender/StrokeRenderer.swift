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
        if stroke.tool.isDragShape {
            return shapePath(for: stroke)
        }

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

    /// The Shift constraint was applied when the points were recorded, so the
    /// stored geometry is the truth and this only connects it.
    private static func shapePath(for stroke: Stroke) -> CGPath {
        let path = CGMutablePath()
        guard stroke.points.count >= 2,
              let start = stroke.points.first,
              let end = stroke.points.last
        else { return path }

        switch stroke.tool {
        case .rectangle, .blur:
            path.addRect(Geometry.rect(from: start, to: end, square: false))

        case .ellipse:
            path.addEllipse(in: Geometry.rect(from: start, to: end, square: false))

        case .arrow:
            path.move(to: start)
            path.addLine(to: end)

            let shaftAngle = atan2(end.y - start.y, end.x - start.x)
            let headLength = Geometry.arrowHeadLength(width: stroke.width)
            for side in [1.0, -1.0] {
                let barbAngle = shaftAngle + .pi - side * Geometry.arrowHeadSpread
                path.move(to: end)
                path.addLine(
                    to: CGPoint(
                        x: end.x + cos(barbAngle) * headLength,
                        y: end.y + sin(barbAngle) * headLength
                    )
                )
            }

        default:
            path.move(to: start)
            path.addLine(to: end)
        }
        return path
    }

    public static func draw(_ stroke: Stroke, in context: CGContext) {
        guard !stroke.points.isEmpty else { return }

        if stroke.tool == .text {
            TextRenderer.draw(stroke, in: context)
            return
        }

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
