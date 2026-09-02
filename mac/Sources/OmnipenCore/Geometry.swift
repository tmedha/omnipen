import CoreGraphics
import Foundation

public enum Geometry {
    /// Shortest distance from `point` to the line segment `a`-`b`.
    /// Used by the eraser to decide which strokes a swipe touches.
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

    /// Snaps the vector `start` to `end` onto the nearest 45 degree angle,
    /// preserving length. Backs the Shift-constrain behaviour of the shape tools.
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
