import CoreGraphics
import Foundation
import Testing

@testable import OmnipenRender

/// Builds a high-contrast checkerboard, which stands in for fine detail like
/// small text: if the redaction works, the squares stop being distinguishable.
private func checkerboard(size: Int, square: Int) -> CGImage {
    let probe = PixelProbe(width: size, height: size)
    probe.context.setFillColor(CGColor(gray: 1, alpha: 1))
    probe.context.fill(CGRect(x: 0, y: 0, width: size, height: size))

    probe.context.setFillColor(CGColor(gray: 0, alpha: 1))
    for row in 0..<(size / square) {
        for column in 0..<(size / square) where (row + column) % 2 == 0 {
            probe.context.fill(
                CGRect(x: column * square, y: row * square, width: square, height: square)
            )
        }
    }
    return probe.context.makeImage()!
}

/// Standard deviation of luminance, as a measure of how much detail survives.
private func contrast(_ image: CGImage) -> Double {
    let probe = PixelProbe(width: image.width, height: image.height)
    probe.context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

    var samples: [Double] = []
    for x in stride(from: 0, to: image.width, by: 2) {
        for y in stride(from: 0, to: image.height, by: 2) {
            let pixel = probe.pixel(x: x, y: y)
            samples.append(0.299 * pixel.red + 0.587 * pixel.green + 0.114 * pixel.blue)
        }
    }
    let mean = samples.reduce(0, +) / Double(samples.count)
    let variance = samples.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(samples.count)
    return variance.squareRoot()
}

@Suite("Redaction")
struct RedactionTests {

    @Test("block size scales with the region but never goes fine")
    func blockSizeFloor() {
        #expect(Redaction.blockSize(for: CGSize(width: 20, height: 12)) >= 10)
        #expect(
            Redaction.blockSize(for: CGSize(width: 800, height: 800))
                > Redaction.blockSize(for: CGSize(width: 200, height: 200))
        )
    }

    @Test("pixelation preserves the image dimensions")
    func preservesSize() throws {
        let source = checkerboard(size: 128, square: 8)
        let result = try #require(Redaction.pixelate(source))
        #expect(result.width == source.width)
        #expect(result.height == source.height)
    }

    @Test("pixelation destroys fine detail")
    func destroysDetail() throws {
        // 4px squares stand in for small text.
        let source = checkerboard(size: 128, square: 4)
        let result = try #require(Redaction.pixelate(source, blockSize: 32))

        let before = contrast(source)
        let after = contrast(result)
        #expect(before > 0.4, "the checkerboard should start high-contrast")
        // Averaging 32pt blocks over 4px squares leaves essentially flat grey.
        #expect(after < before / 4, "detail survived: \(before) -> \(after)")
    }

    @Test("the whole area is covered, with no transparent edges")
    func noTransparentEdges() throws {
        // Clamping matters here: blurring without it leaves the border see-through,
        // which would leak the very pixels being redacted.
        let source = checkerboard(size: 64, square: 8)
        let result = try #require(Redaction.pixelate(source, blockSize: 16))

        let probe = PixelProbe(width: result.width, height: result.height)
        probe.context.draw(result, in: CGRect(x: 0, y: 0, width: result.width, height: result.height))

        for coordinate in [0, 1, 31, 62, 63] {
            #expect(probe.pixel(x: coordinate, y: 0).alpha > 0.95, "top edge at \(coordinate)")
            #expect(probe.pixel(x: coordinate, y: 63).alpha > 0.95, "bottom edge at \(coordinate)")
            #expect(probe.pixel(x: 0, y: coordinate).alpha > 0.95, "left edge at \(coordinate)")
            #expect(probe.pixel(x: 63, y: coordinate).alpha > 0.95, "right edge at \(coordinate)")
        }
    }

    @Test("a degenerate image is refused rather than crashing")
    func degenerateImage() {
        let empty = PixelProbe(width: 1, height: 1)
        empty.context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        empty.context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        // A 1x1 image has no detail to destroy, but must not trap.
        _ = Redaction.pixelate(empty.context.makeImage()!)
    }
}
