import CoreGraphics
import Testing

@testable import OmnipenCore
@testable import OmnipenRender

private func textStroke(
    _ text: String,
    at origin: CGPoint = CGPoint(x: 20, y: 150),
    width: Double = 6
) -> Stroke {
    Stroke(
        tool: .text,
        color: InkColor(red: 0, green: 0, blue: 0),
        width: width,
        points: [origin],
        text: text,
        textSize: TextRenderer.measure(text, width: width)
    )
}

@Suite("Text rendering")
struct TextRenderingTests {

    @Test("font size never drops below a legible floor")
    func fontSizeFloor() {
        // The width control bottoms out at 1pt, which would be unreadable as type.
        #expect(TextRenderer.fontSize(forWidth: 1) >= 13)
        // Above the floor it scales with the control.
        #expect(TextRenderer.fontSize(forWidth: 20) > TextRenderer.fontSize(forWidth: 10))
    }

    @Test("measuring grows with the text and with the size")
    func measureScales() {
        let short = TextRenderer.measure("Hi", width: 6)
        let long = TextRenderer.measure("Hi there, everyone", width: 6)
        #expect(long.width > short.width)
        #expect(abs(long.height - short.height) < 0.01)

        let bigger = TextRenderer.measure("Hi", width: 20)
        #expect(bigger.height > short.height)
        #expect(bigger.width > short.width)
    }

    @Test("each newline adds a line of height")
    func measureCountsLines() {
        let one = TextRenderer.measure("one", width: 6)
        let three = TextRenderer.measure("one\ntwo\nthree", width: 6)
        #expect(abs(three.height - one.height * 3) < 0.01)
        // Width follows the longest line, not the total.
        #expect(three.width > one.width)
    }

    @Test("empty text measures to nothing and draws nothing")
    func emptyText() {
        #expect(TextRenderer.measure("", width: 6).width == 0)

        let probe = PixelProbe(width: 100, height: 100)
        TextRenderer.draw(textStroke(""), in: probe.context)
        #expect(probe.pixel(x: 50, y: 50).isClear)
    }

    @Test("text rasterises inside the bounds the model reports")
    func drawsWithinBounds() {
        let stroke = textStroke("Omnipen", at: CGPoint(x: 20, y: 150))
        let probe = PixelProbe(width: 300, height: 200)
        TextRenderer.draw(stroke, in: probe.context)

        // Something was actually drawn.
        var inked = 0
        let bounds = stroke.bounds
        for x in stride(from: Int(bounds.minX), to: Int(bounds.maxX), by: 2) {
            for y in stride(from: Int(bounds.minY), to: Int(bounds.maxY), by: 2) {
                guard x >= 0, y >= 0, x < 300, y < 200 else { continue }
                if !probe.pixel(x: x, y: y).isClear { inked += 1 }
            }
        }
        #expect(inked > 20)

        // And nothing escaped the reported bounds, which is what the invalidation
        // rect relies on.
        for x in stride(from: 0, to: 300, by: 3) {
            for y in stride(from: 0, to: 200, by: 3) {
                guard !bounds.insetBy(dx: -2, dy: -2).contains(CGPoint(x: x, y: y)) else { continue }
                #expect(probe.pixel(x: x, y: y).isClear, "ink outside bounds at (\(x), \(y))")
            }
        }
    }

    @Test("bounds hang below the origin, which is the top-left of the block")
    func boundsAnchorAtTopLeft() {
        let origin = CGPoint(x: 20, y: 150)
        let stroke = textStroke("Omnipen", at: origin)
        let bounds = stroke.bounds

        #expect(bounds.maxY <= origin.y + 3)
        #expect(bounds.minY < origin.y)
        #expect(bounds.minX <= origin.x)
    }

    @Test("a text block is erasable by touching anywhere inside it")
    func textErasesAsABlock() {
        let stroke = textStroke("Omnipen", at: CGPoint(x: 20, y: 150))
        let centre = CGPoint(x: stroke.bounds.midX, y: stroke.bounds.midY)

        // Unlike a traced stroke, the interior counts: there is no centreline to
        // swipe along.
        #expect(stroke.hitTest(centre, radius: 1))
        #expect(!stroke.hitTest(CGPoint(x: 280, y: 20), radius: 4))
    }

    @Test("a text stroke with no measurement has null bounds rather than crashing")
    func unmeasuredText() {
        let stroke = Stroke(
            tool: .text,
            color: InkColor(red: 0, green: 0, blue: 0),
            width: 6,
            points: [CGPoint(x: 10, y: 10)],
            text: "hi"
        )
        #expect(stroke.bounds.isNull)
        #expect(!stroke.hitTest(CGPoint(x: 10, y: 10), radius: 4))
    }

    @Test("text routes through the shared renderer, not just the text entry point")
    func strokeRendererHandlesText() {
        let probe = PixelProbe(width: 300, height: 200)
        StrokeRenderer.draw(textStroke("Hello"), in: probe.context)

        var inked = false
        for x in stride(from: 20, to: 120, by: 2) where !inked {
            for y in stride(from: 120, to: 155, by: 2) where !inked {
                if !probe.pixel(x: x, y: y).isClear { inked = true }
            }
        }
        #expect(inked)
    }
}
