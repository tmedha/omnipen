import CoreGraphics
import Foundation

public enum Geometry {
    public static func distance(from point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy

        guard lengthSquared > 0 else {
            return hypot(point.x - a.x, point.y - a.y)
        }

        // Projected onto the segment, clamped to its extent.
        var t = ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared
        t = max(0, min(1, t))

        let projX = a.x + t * dx
        let projY = a.y + t * dy
        return hypot(point.x - projX, point.y - projY)
    }

    public static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    /// Single source of truth for arrowhead size, shared by the renderer that
    /// draws the barbs and the bounds that must leave room for them.
    public static func arrowHeadLength(width: Double) -> Double {
        max(width * 3.5, 10)
    }

    public static let arrowHeadSpread = Double.pi / 7

    /// Samples an ellipse perimeter into a closed polyline, so the eraser can hit
    /// the outline of an ellipse instead of only its diagonal.
    public static func ellipsePoints(in rect: CGRect, segments: Int = 32) -> [CGPoint] {
        guard segments >= 3, rect.width > 0 || rect.height > 0 else { return [] }
        let radiusX = rect.width / 2
        let radiusY = rect.height / 2

        var points = (0..<segments).map { step in
            let angle = 2 * Double.pi * Double(step) / Double(segments)
            return CGPoint(
                x: rect.midX + cos(angle) * radiusX,
                y: rect.midY + sin(angle) * radiusY
            )
        }
        // Closed by repeating the first point rather than by evaluating the angle
        // at 2 pi, which rounds to a hair off the start and leaves a seam.
        points.append(points[0])
        return points
    }

    public static func snapToAxis(start: CGPoint, end: CGPoint) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0 else { return end }

        let step = Double.pi / 4
        let snapped = (atan2(dy, dx) / step).rounded() * step
        return CGPoint(x: start.x + cos(snapped) * length, y: start.y + sin(snapped) * length)
    }

    /// Rectangle spanning two corners. When `square` is set, the shorter side is
    /// extended to match the longer one, growing away from `start`.
    public static func rect(from start: CGPoint, to end: CGPoint, square: Bool) -> CGRect {
        var dx = end.x - start.x
        var dy = end.y - start.y

        if square {
            let side = max(abs(dx), abs(dy))
            dx = dx < 0 ? -side : side
            dy = dy < 0 ? -side : side
        }

        return CGRect(
            x: min(start.x, start.x + dx),
            y: min(start.y, start.y + dy),
            width: abs(dx),
            height: abs(dy)
        )
    }
}
