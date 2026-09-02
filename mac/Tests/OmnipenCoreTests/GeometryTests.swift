import CoreGraphics
import Foundation
import Testing

@testable import OmnipenCore

@Suite("Geometry")
struct GeometryTests {

    @Test("distance to a segment uses the perpendicular when the foot is inside")
    func perpendicularDistance() {
        let d = Geometry.distance(
            from: CGPoint(x: 5, y: 3),
            toSegment: CGPoint(x: 0, y: 0),
            CGPoint(x: 10, y: 0)
        )
        #expect(abs(d - 3) < 1e-9)
    }

    @Test("distance clamps to the endpoints when the foot falls outside")
    func clampedDistance() {
        // Projection lands left of the segment, so the nearer endpoint wins.
        let d = Geometry.distance(
            from: CGPoint(x: -4, y: 3),
            toSegment: CGPoint(x: 0, y: 0),
            CGPoint(x: 10, y: 0)
        )
        #expect(abs(d - 5) < 1e-9)
    }

    @Test("a degenerate segment behaves as a point")
    func degenerateSegment() {
        let d = Geometry.distance(
            from: CGPoint(x: 3, y: 4),
            toSegment: CGPoint(x: 0, y: 0),
            CGPoint(x: 0, y: 0)
        )
        #expect(abs(d - 5) < 1e-9)
    }

    @Test("axis snapping picks the nearest 45 degrees and keeps the length")
    func snapPreservesLength() {
        let start = CGPoint(x: 0, y: 0)
        // 10 degrees off horizontal should snap flat.
        let end = CGPoint(x: 100, y: 17.6)
        let snapped = Geometry.snapToAxis(start: start, end: end)

        let originalLength = hypot(end.x, end.y)
        let snappedLength = hypot(snapped.x, snapped.y)
        #expect(abs(snappedLength - originalLength) < 1e-6)
        #expect(abs(snapped.y) < 1e-6)
    }

    @Test("axis snapping reaches the diagonal")
    func snapToDiagonal() {
        let snapped = Geometry.snapToAxis(
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 100, y: 90)
        )
        // 42 degrees rounds to 45, so the components come out equal.
        #expect(abs(snapped.x - snapped.y) < 1e-6)
    }

    @Test("rect spans two corners regardless of drag direction")
    func rectNormalises() {
        let a = Geometry.rect(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 40, y: 50), square: false)
        let b = Geometry.rect(from: CGPoint(x: 40, y: 50), to: CGPoint(x: 10, y: 10), square: false)
        #expect(a == b)
        #expect(a == CGRect(x: 10, y: 10, width: 30, height: 40))
    }

    @Test("square constraint grows the short side away from the start")
    func squareConstraint() {
        // Dragging down-left: the square must extend down-left too, not flip.
        let rect = Geometry.rect(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 60, y: 90), square: true)
        #expect(rect.width == rect.height)
        #expect(rect == CGRect(x: 60, y: 60, width: 40, height: 40))
    }
}

@Suite("Stroke hit testing")
struct StrokeHitTests {

    private func stroke(_ points: [CGPoint], width: Double) -> Stroke {
        Stroke(tool: .pen, color: InkColor(red: 0, green: 0, blue: 0), width: width, points: points)
    }

    @Test("thickness counts toward a hit")
    func nibWidthCounts() {
        // Centreline is 9pt away, but a 20pt nib reaches 10pt from the centre.
        let s = stroke([CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)], width: 20)
        #expect(s.hitTest(CGPoint(x: 50, y: 9), radius: 0))
        #expect(!s.hitTest(CGPoint(x: 50, y: 40), radius: 0))
    }

    @Test("a single-point stroke is still erasable")
    func dotIsHittable() {
        let s = stroke([CGPoint(x: 50, y: 50)], width: 6)
        #expect(s.hitTest(CGPoint(x: 52, y: 52), radius: 4))
        #expect(!s.hitTest(CGPoint(x: 200, y: 200), radius: 4))
    }

    @Test("bounds are inflated by half the nib")
    func boundsIncludeNib() {
        let s = stroke([CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 10)], width: 8)
        #expect(s.bounds == CGRect(x: 6, y: 6, width: 28, height: 8))
    }
}
