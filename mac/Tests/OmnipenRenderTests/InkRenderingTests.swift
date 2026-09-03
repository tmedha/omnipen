import CoreGraphics
import Testing

@testable import OmnipenCore
@testable import OmnipenRender

private let red = InkColor(red: 1, green: 0, blue: 0)
private let yellow = InkColor(red: 1, green: 1, blue: 0)

private func stroke(
    _ tool: ToolKind,
    _ points: [CGPoint],
    color: InkColor = red,
    width: Double = 10
) -> Stroke {
    Stroke(tool: tool, color: color, width: width, points: points)
}

@Suite("Stroke rasterisation")
struct StrokeRenderingTests {

    @Test("a pen stroke paints its path and leaves the rest transparent")
    func penPaintsPath() {
        let probe = PixelProbe(width: 100, height: 100)
        StrokeRenderer.draw(
            stroke(.pen, [CGPoint(x: 10, y: 50), CGPoint(x: 90, y: 50)]),
            in: probe.context
        )

        let onPath = probe.pixel(x: 50, y: 50)
        #expect(onPath.alpha > 0.99)
        #expect(onPath.red > 0.99)
        #expect(onPath.green < 0.01)

        #expect(probe.pixel(x: 50, y: 10).isClear)
        #expect(probe.pixel(x: 5, y: 5).isClear)
    }

    @Test("nib width is honoured on both sides of the centreline")
    func nibWidth() {
        let probe = PixelProbe(width: 100, height: 100)
        StrokeRenderer.draw(
            stroke(.pen, [CGPoint(x: 10, y: 50), CGPoint(x: 90, y: 50)], width: 10),
            in: probe.context
        )

        // A 10pt nib reaches 5pt either side of y = 50.
        #expect(probe.pixel(x: 50, y: 53).alpha > 0.9)
        #expect(probe.pixel(x: 50, y: 47).alpha > 0.9)
        #expect(probe.pixel(x: 50, y: 58).isClear)
    }

    @Test("a single-point stroke renders as a round dot")
    func tapRendersDot() {
        let probe = PixelProbe(width: 100, height: 100)
        StrokeRenderer.draw(stroke(.pen, [CGPoint(x: 50, y: 50)], width: 12), in: probe.context)

        #expect(probe.pixel(x: 50, y: 50).alpha > 0.99)
        // A 12pt nib reaches 6pt along an axis.
        #expect(probe.pixel(x: 50, y: 55).alpha > 0.9)
        // The corner of that bounding square is 7.1pt out, so a round cap leaves
        // it nearly empty where a square cap would leave it solid.
        #expect(probe.pixel(x: 45, y: 45).alpha < 0.3)
        #expect(probe.pixel(x: 42, y: 42).isClear)
    }

    @Test("the highlighter keeps one uniform alpha where a stroke crosses itself")
    func highlighterDoesNotCompound() {
        let probe = PixelProbe(width: 200, height: 200)
        // An X in a single stroke, so the crossing is within one path.
        let crossing = stroke(
            .highlighter,
            [
                CGPoint(x: 40, y: 40),
                CGPoint(x: 160, y: 160),
                CGPoint(x: 100, y: 160),
                CGPoint(x: 100, y: 40),
            ],
            color: yellow.withAlpha(0.35),
            width: 20
        )
        StrokeRenderer.draw(crossing, in: probe.context)

        // A point on a single limb versus the point where the limbs overlap.
        let single = probe.pixel(x: 100, y: 100)
        let overlap = probe.pixel(x: 100, y: 60)

        #expect(single.alpha > 0.3)
        #expect(overlap.alpha > 0.3)
        // Stroking translucently instead of via a transparency layer would push
        // the overlap toward 1 - 0.65^2 = 0.58.
        #expect(abs(single.alpha - overlap.alpha) < 0.02)
    }

    @Test("the highlighter is translucent where the pen is opaque")
    func highlighterIsTranslucent() {
        let probe = PixelProbe(width: 100, height: 100)
        StrokeRenderer.draw(
            stroke(
                .highlighter,
                [CGPoint(x: 10, y: 50), CGPoint(x: 90, y: 50)],
                color: yellow.withAlpha(0.35),
                width: 20
            ),
            in: probe.context
        )

        let sample = probe.pixel(x: 50, y: 50)
        #expect(abs(sample.alpha - 0.35) < 0.02)
    }

    @Test("an empty stroke draws nothing")
    func emptyStrokeIsNoop() {
        let probe = PixelProbe(width: 20, height: 20)
        StrokeRenderer.draw(stroke(.pen, []), in: probe.context)
        #expect(probe.pixel(x: 10, y: 10).isClear)
    }
}

@Suite("InkBitmap")
struct InkBitmapTests {

    private func horizontalStroke(y: Double, color: InkColor = red) -> Stroke {
        stroke(.pen, [CGPoint(x: 10, y: y), CGPoint(x: 90, y: y)], color: color)
    }

    @Test("starts stale and clears the flag once rebuilt")
    func staleLifecycle() {
        let bitmap = InkBitmap()
        #expect(bitmap.isStale)

        bitmap.configure(size: CGSize(width: 100, height: 100), scale: 1)
        #expect(bitmap.isStale)

        bitmap.rebuild(with: [])
        #expect(!bitmap.isStale)

        bitmap.markStale()
        #expect(bitmap.isStale)
    }

    @Test("rebuild rasterises every stroke it is given")
    func rebuildDrawsAll() {
        let bitmap = InkBitmap()
        bitmap.configure(size: CGSize(width: 100, height: 100), scale: 1)
        bitmap.rebuild(with: [horizontalStroke(y: 30), horizontalStroke(y: 70)])

        let image = try! #require(bitmap.image)
        #expect(PixelProbe.sampling(image, x: 50, y: 30).alpha > 0.9)
        #expect(PixelProbe.sampling(image, x: 50, y: 70).alpha > 0.9)
        #expect(PixelProbe.sampling(image, x: 50, y: 50).isClear)
    }

    @Test("bake adds a stroke without disturbing what is already there")
    func bakeIsAdditive() {
        let bitmap = InkBitmap()
        bitmap.configure(size: CGSize(width: 100, height: 100), scale: 1)
        bitmap.rebuild(with: [horizontalStroke(y: 30)])
        bitmap.bake(horizontalStroke(y: 70))

        let image = try! #require(bitmap.image)
        #expect(PixelProbe.sampling(image, x: 50, y: 30).alpha > 0.9)
        #expect(PixelProbe.sampling(image, x: 50, y: 70).alpha > 0.9)
        #expect(!bitmap.isStale)
    }

    @Test("baking onto a stale bitmap is dropped rather than half-applied")
    func bakeWhileStaleDefersToRebuild() {
        let bitmap = InkBitmap()
        bitmap.configure(size: CGSize(width: 100, height: 100), scale: 1)

        // Still stale from configure, so this stroke must not be trusted.
        bitmap.bake(horizontalStroke(y: 30))
        #expect(bitmap.isStale)

        // The rebuild is the source of truth, and it never saw that stroke.
        bitmap.rebuild(with: [])
        let image = try! #require(bitmap.image)
        #expect(PixelProbe.sampling(image, x: 50, y: 30).isClear)
    }

    @Test("rebuild clears ink that is no longer in the store")
    func rebuildClearsRemovedInk() {
        let bitmap = InkBitmap()
        bitmap.configure(size: CGSize(width: 100, height: 100), scale: 1)
        bitmap.rebuild(with: [horizontalStroke(y: 30), horizontalStroke(y: 70)])
        bitmap.rebuild(with: [horizontalStroke(y: 70)])

        let image = try! #require(bitmap.image)
        #expect(PixelProbe.sampling(image, x: 50, y: 30).isClear)
        #expect(PixelProbe.sampling(image, x: 50, y: 70).alpha > 0.9)
    }

    @Test("the backing store is allocated in device pixels")
    func retinaBacking() {
        let bitmap = InkBitmap()
        bitmap.configure(size: CGSize(width: 100, height: 50), scale: 2)
        bitmap.rebuild(with: [])

        let image = try! #require(bitmap.image)
        #expect(image.width == 200)
        #expect(image.height == 100)
    }

    @Test("stroke coordinates stay in points after a scale change")
    func scaleDoesNotMoveInk() {
        let bitmap = InkBitmap()
        bitmap.configure(size: CGSize(width: 100, height: 100), scale: 2)
        bitmap.rebuild(with: [horizontalStroke(y: 30)])

        let image = try! #require(bitmap.image)
        // The stroke was placed at y = 30 in points, so at 2x it lands on row 60.
        #expect(PixelProbe.sampling(image, x: 100, y: 60).alpha > 0.9)
        #expect(PixelProbe.sampling(image, x: 100, y: 140).isClear)
    }

    @Test("a resize discards the old raster instead of stretching it")
    func resizeInvalidates() {
        let bitmap = InkBitmap()
        bitmap.configure(size: CGSize(width: 100, height: 100), scale: 1)
        bitmap.rebuild(with: [horizontalStroke(y: 30)])
        #expect(!bitmap.isStale)

        bitmap.configure(size: CGSize(width: 200, height: 200), scale: 1)
        #expect(bitmap.isStale)
    }
}
