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
        // Arrow barbs extend past the end point, so they need room or the
        // invalidation rect would clip the head.
        let pad = width / 2 + (tool == .arrow ? Geometry.arrowHeadLength(width: width) : 0)
        return CGRect(
            x: minX - pad,
            y: minY - pad,
            width: (maxX - minX) + pad * 2,
            height: (maxY - minY) + pad * 2
        )
    }

    /// The polylines the eraser tests against. A traced stroke is its own points,
    /// but a drag shape stores only two corners and has to be expanded into its
    /// outline, or the eraser would only catch the diagonal of a rectangle.
    public var hitTestPolylines: [[CGPoint]] {
        guard tool.isDragShape, points.count >= 2,
              let start = points.first, let end = points.last
        else {
            return [points]
        }

        switch tool {
        case .rectangle, .blur:
            let rect = Geometry.rect(from: start, to: end, square: false)
            return [[
                CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.maxY),
                CGPoint(x: rect.minX, y: rect.maxY),
                CGPoint(x: rect.minX, y: rect.minY),
            ]]
        case .ellipse:
            return [Geometry.ellipsePoints(in: Geometry.rect(from: start, to: end, square: false))]
        default:
            return [[start, end]]
        }
    }

    /// Cheap bounds rejection first, then per-segment distance.
    public func hitTest(_ point: CGPoint, radius: Double) -> Bool {
        let tolerance = radius + width / 2
        guard bounds.insetBy(dx: -radius, dy: -radius).contains(point) else { return false }

        for polyline in hitTestPolylines {
            guard polyline.count > 1 else {
                if let only = polyline.first, hypot(only.x - point.x, only.y - point.y) <= tolerance {
                    return true
                }
                continue
            }
            for index in 0..<(polyline.count - 1) {
                if Geometry.distance(from: point, toSegment: polyline[index], polyline[index + 1]) <= tolerance {
                    return true
                }
            }
        }
        return false
    }
}
