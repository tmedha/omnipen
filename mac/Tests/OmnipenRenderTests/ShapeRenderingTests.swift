import CoreGraphics
import Foundation
import Testing

@testable import OmnipenCore
@testable import OmnipenRender

private let black = InkColor(red: 0, green: 0, blue: 0)

private func shape(_ tool: ToolKind, _ a: CGPoint, _ b: CGPoint, width: Double = 4) -> Stroke {
    Stroke(tool: tool, color: black, width: width, points: [a, b])
}

@Suite("Shape rasterisation")
struct ShapeRenderingTests {

    @Test("a rectangle paints its edges and leaves the middle empty")
    func rectangleIsOutlined() {
        let probe = PixelProbe(width: 200, height: 200)
        StrokeRenderer.draw(
            shape(.rectangle, CGPoint(x: 50, y: 50), CGPoint(x: 150, y: 150)),
            in: probe.context
        )

        #expect(probe.pixel(x: 100, y: 50).alpha > 0.9)   // bottom edge
        #expect(probe.pixel(x: 100, y: 150).alpha > 0.9)  // top edge
        #expect(probe.pixel(x: 50, y: 100).alpha > 0.9)   // left edge
        #expect(probe.pixel(x: 150, y: 100).alpha > 0.9)  // right edge
        #expect(probe.pixel(x: 100, y: 100).isClear)
    }

    @Test("a rectangle drawn in any drag direction covers the same pixels")
    func rectangleDirectionAgnostic() {
        let forward = PixelProbe(width: 200, height: 200)
        StrokeRenderer.draw(
            shape(.rectangle, CGPoint(x: 50, y: 50), CGPoint(x: 150, y: 150)),
            in: forward.context
        )
        let backward = PixelProbe(width: 200, height: 200)
        StrokeRenderer.draw(
            shape(.rectangle, CGPoint(x: 150, y: 150), CGPoint(x: 50, y: 50)),
            in: backward.context
        )

        for point in [(100, 50), (100, 150), (50, 100), (150, 100), (100, 100)] {
            #expect(
                forward.pixel(x: point.0, y: point.1) == backward.pixel(x: point.0, y: point.1),
                "differed at \(point)"
            )
        }
    }

    @Test("an ellipse hits its axes and misses the corners of its box")
    func ellipseIsRound() {
        let probe = PixelProbe(width: 200, height: 200)
        StrokeRenderer.draw(
            shape(.ellipse, CGPoint(x: 50, y: 50), CGPoint(x: 150, y: 150)),
            in: probe.context
        )

        #expect(probe.pixel(x: 100, y: 50).alpha > 0.9)
        #expect(probe.pixel(x: 50, y: 100).alpha > 0.9)
        #expect(probe.pixel(x: 100, y: 100).isClear)
        // A rectangle would have painted this corner.
        #expect(probe.pixel(x: 52, y: 52).isClear)
    }

    @Test("an arrow draws a shaft plus two barbs at the head")
    func arrowHasBarbs() {
        let probe = PixelProbe(width: 200, height: 200)
        StrokeRenderer.draw(
            shape(.arrow, CGPoint(x: 40, y: 100), CGPoint(x: 160, y: 100), width: 6),
            in: probe.context
        )

        #expect(probe.pixel(x: 100, y: 100).alpha > 0.9)

        // Barbs sweep back from the head, so pixels above and below the shaft
        // near the tip are painted while the same offsets mid-shaft are not.
        let headLength = Geometry.arrowHeadLength(width: 6)
        let barbX = Int(160 - cos(Geometry.arrowHeadSpread) * headLength)
        let barbY = Int(100 + sin(Geometry.arrowHeadSpread) * headLength)
        #expect(probe.pixel(x: barbX, y: barbY).alpha > 0.5)
        #expect(probe.pixel(x: barbX, y: 200 - barbY).alpha > 0.5)
        #expect(probe.pixel(x: 100, y: barbY).isClear)
    }

    @Test("a line is just a line, with no head")
    func lineHasNoHead() {
        let probe = PixelProbe(width: 200, height: 200)
        StrokeRenderer.draw(
            shape(.line, CGPoint(x: 40, y: 100), CGPoint(x: 160, y: 100), width: 6),
            in: probe.context
        )

        #expect(probe.pixel(x: 100, y: 100).alpha > 0.9)
        let headLength = Geometry.arrowHeadLength(width: 6)
        let barbY = Int(100 + sin(Geometry.arrowHeadSpread) * headLength)
        #expect(probe.pixel(x: Int(160 - cos(Geometry.arrowHeadSpread) * headLength), y: barbY).isClear)
    }

    @Test("a degenerate shape renders nothing rather than crashing")
    func degenerateShape() {
        let probe = PixelProbe(width: 50, height: 50)
        StrokeRenderer.draw(
            Stroke(tool: .rectangle, color: black, width: 4, points: [CGPoint(x: 25, y: 25)]),
            in: probe.context
        )
        #expect(probe.pixel(x: 25, y: 25).isClear)
    }
}

@Suite("Shape hit testing and bounds")
struct ShapeHitTests {

    @Test("the eraser catches a rectangle's edge, not its interior")
    func rectangleEraseFollowsOutline() {
        let rect = shape(.rectangle, CGPoint(x: 50, y: 50), CGPoint(x: 150, y: 150), width: 4)

        #expect(rect.hitTest(CGPoint(x: 100, y: 50), radius: 6))    // on an edge
        #expect(rect.hitTest(CGPoint(x: 50, y: 100), radius: 6))
        // The middle is empty, so a swipe through it must not delete the box.
        #expect(!rect.hitTest(CGPoint(x: 100, y: 100), radius: 6))
        // Nor should the diagonal between the two stored corners.
        #expect(!rect.hitTest(CGPoint(x: 75, y: 75), radius: 6))
    }

    @Test("the eraser catches an ellipse's perimeter, not its centre")
    func ellipseEraseFollowsPerimeter() {
        let ellipse = shape(.ellipse, CGPoint(x: 50, y: 50), CGPoint(x: 150, y: 150), width: 4)

        #expect(ellipse.hitTest(CGPoint(x: 100, y: 50), radius: 6))
        #expect(ellipse.hitTest(CGPoint(x: 150, y: 100), radius: 6))
        #expect(!ellipse.hitTest(CGPoint(x: 100, y: 100), radius: 6))
        // The corner of the bounding box is outside the curve.
        #expect(!ellipse.hitTest(CGPoint(x: 55, y: 55), radius: 6))
    }

    @Test("a line and arrow are erasable along the shaft")
    func lineErase() {
        let line = shape(.line, CGPoint(x: 40, y: 100), CGPoint(x: 160, y: 100), width: 4)
        #expect(line.hitTest(CGPoint(x: 100, y: 101), radius: 4))
        #expect(!line.hitTest(CGPoint(x: 100, y: 140), radius: 4))
    }

    @Test("arrow bounds leave room for the barbs")
    func arrowBoundsIncludeHead() {
        let arrow = shape(.arrow, CGPoint(x: 40, y: 100), CGPoint(x: 160, y: 100), width: 6)
        let plain = shape(.line, CGPoint(x: 40, y: 100), CGPoint(x: 160, y: 100), width: 6)

        // Without the extra padding the invalidation rect would clip the head.
        #expect(arrow.bounds.height > plain.bounds.height)
        let head = Geometry.arrowHeadLength(width: 6)
        #expect(arrow.bounds.maxY >= 100 + sin(Geometry.arrowHeadSpread) * head)
    }

    @Test("ellipse sampling produces a closed polyline")
    func ellipsePolylineIsClosed() {
        let points = Geometry.ellipsePoints(
            in: CGRect(x: 0, y: 0, width: 100, height: 50),
            segments: 16
        )
        #expect(points.count == 17)
        #expect(points.first == points.last)
    }
}
