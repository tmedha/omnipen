import CoreGraphics
import Foundation

/// Plain RGBA so the model stays free of AppKit.
public struct InkColor: Equatable, Codable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public func withAlpha(_ alpha: Double) -> InkColor {
        InkColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

/// One committed mark on a canvas. A value type, so undo and redo are array
/// bookkeeping and nothing holds a live reference to a stroke mid-edit.
public struct Stroke: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var tool: ToolKind
    public var color: InkColor
    public var width: Double
    public var points: [CGPoint]
    public var createdAt: TimeInterval

    public init(
        id: UUID = UUID(),
        tool: ToolKind,
        color: InkColor,
        width: Double,
        points: [CGPoint] = [],
        createdAt: TimeInterval = Date.timeIntervalSinceReferenceDate
    ) {
        self.id = id
        self.tool = tool
        self.color = color
        self.width = width
        self.points = points
        self.createdAt = createdAt
    }

    /// Inflated by half the nib width, so hit-testing accounts for the drawn
    /// thickness rather than the mathematical centreline.
    public var bounds: CGRect {
        guard let first = points.first else { return .null }
        var minX = first.x, maxX = first.x
        var minY = first.y, maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        let pad = width / 2
        return CGRect(x: minX - pad, y: minY - pad, width: (maxX - minX) + width, height: (maxY - minY) + width)
    }

    /// Cheap bounds rejection first, then per-segment distance.
    public func hitTest(_ point: CGPoint, radius: Double) -> Bool {
        let tolerance = radius + width / 2
        guard bounds.insetBy(dx: -radius, dy: -radius).contains(point) else { return false }
        guard points.count > 1 else {
            guard let only = points.first else { return false }
            return hypot(only.x - point.x, only.y - point.y) <= tolerance
        }
        for index in 0..<(points.count - 1) {
            if Geometry.distance(from: point, toSegment: points[index], points[index + 1]) <= tolerance {
                return true
            }
        }
        return false
    }
}
