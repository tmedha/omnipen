import CoreGraphics
import OmnipenCore

/// Without this, each frame of a drag would re-stroke the entire history and
/// drawing would slow down the more had been drawn. Committed ink is baked once
/// and thereafter only blitted, leaving per-frame cost proportional to the live
/// stroke alone.
public final class InkBitmap {

    private var context: CGContext?
    private var cachedImage: CGImage?
    private var size: CGSize = .zero
    private var scale: CGFloat = 1

    /// Set when the bitmap no longer matches the stroke store, which happens on
    /// erase, undo, redo, and clear. Appending is handled incrementally instead.
    public private(set) var isStale = true

    public init() {}

    public func configure(size: CGSize, scale: CGFloat) {
        guard context == nil || size != self.size || scale != self.scale else { return }
        self.size = size
        self.scale = scale
        context = Self.makeContext(size: size, scale: scale)
        markStale()
    }

    public func markStale() {
        isStale = true
        cachedImage = nil
    }

    public var isAllocated: Bool { context != nil }

    /// Frees the backing store. A full-screen bitmap costs roughly 95 MB on a
    /// Retina display, so it is not worth holding for a handful of strokes that
    /// can simply be redrawn.
    public func release() {
        context = nil
        markStale()
    }

    public func rebuild(with strokes: [Stroke]) {
        guard let context else { return }
        context.clear(CGRect(origin: .zero, size: size))
        for stroke in strokes {
            StrokeRenderer.draw(stroke, in: context)
        }
        isStale = false
        cachedImage = nil
    }

    public func bake(_ stroke: Stroke) {
        guard let context, !isStale else {
            // A stale bitmap gets rebuilt wholesale on the next draw anyway.
            markStale()
            return
        }
        StrokeRenderer.draw(stroke, in: context)
        cachedImage = nil
    }

    /// `makeImage` copies the whole buffer, so the result is held until the ink
    /// changes rather than being remade every frame.
    public var image: CGImage? {
        if cachedImage == nil {
            cachedImage = context?.makeImage()
        }
        return cachedImage
    }

    private static func makeContext(size: CGSize, scale: CGFloat) -> CGContext? {
        let pixelWidth = Int((size.width * scale).rounded())
        let pixelHeight = Int((size.height * scale).rounded())
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        )
        context?.scaleBy(x: scale, y: scale)
        return context
    }
}
