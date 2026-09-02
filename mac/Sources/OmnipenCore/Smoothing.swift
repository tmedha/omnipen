import CoreGraphics
import Foundation

/// A resolution-independent description of a stroke's outline, kept abstract so
/// the smoothing is testable without a graphics context.
public enum PathSegment: Equatable, Sendable {
    case move(CGPoint)
    case line(CGPoint)
    case quad(to: CGPoint, control: CGPoint)
}

public enum Smoothing {

    /// Drops points closer together than `minimumDistance`. Trackpads emit
    /// clusters of near-identical points when moving slowly, which make the
    /// smoothed curve wobble.
    public static func simplify(_ points: [CGPoint], minimumDistance: Double = 1.5) -> [CGPoint] {
        guard let first = points.first else { return [] }

        var result = [first]
        for point in points.dropFirst() {
            let previous = result[result.count - 1]
            if hypot(point.x - previous.x, point.y - previous.y) >= minimumDistance {
                result.append(point)
            }
        }

        // Without this, a stroke visibly falls short of where the user lifted off.
        if let last = points.last, result.count > 1, result[result.count - 1] != last {
            result[result.count - 1] = last
        }
        return result
    }

    /// Midpoint-quadratic smoothing: each recorded point becomes a control point,
    /// and the curve passes through the midpoints between them. Chosen over
    /// Catmull-Rom, which overshoots on a sharp reversal.
    public static func path(for points: [CGPoint]) -> [PathSegment] {
        switch points.count {
        case 0:
            return []
        case 1:
            // A tap: a zero-length segment the renderer caps into a dot.
            return [.move(points[0]), .line(points[0])]
        case 2:
            return [.move(points[0]), .line(points[1])]
        default:
            var segments: [PathSegment] = [.move(points[0])]
            for index in 1..<(points.count - 1) {
                let control = points[index]
                let end = Geometry.midpoint(points[index], points[index + 1])
                segments.append(.quad(to: end, control: control))
            }
            segments.append(.quad(to: points[points.count - 1], control: points[points.count - 2]))
            return segments
        }
    }
}
