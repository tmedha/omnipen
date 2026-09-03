import CoreGraphics
import Foundation

/// A small offscreen surface that can be drawn into and then sampled, so the
/// ink engine can be asserted against real rasterised pixels rather than against
/// the drawing calls it happens to make.
struct PixelProbe {

    struct Pixel: Equatable, CustomStringConvertible {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double

        var isClear: Bool { alpha < 0.01 }

        var description: String {
            String(format: "rgba(%.3f, %.3f, %.3f, %.3f)", red, green, blue, alpha)
        }
    }

    let context: CGContext
    let width: Int
    let height: Int

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        )!
    }

    /// Samples in Core Graphics coordinates, origin bottom-left.
    func pixel(x: Int, y: Int) -> Pixel {
        Self.sample(context.data, bytesPerRow: context.bytesPerRow, x: x, y: height - 1 - y)
    }

    /// Rasterises a `CGImage` into a fresh surface and samples it, which is how
    /// the baked-bitmap output gets inspected.
    static func sampling(_ image: CGImage, x: Int, y: Int) -> Pixel {
        let probe = PixelProbe(width: image.width, height: image.height)
        probe.context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
        )
        return probe.pixel(x: x, y: y)
    }

    /// Byte order is `premultipliedFirst | byteOrder32Little`, which lays out as
    /// B, G, R, A in memory. Colour components are un-premultiplied so they can
    /// be compared against the source colour directly.
    private static func sample(
        _ data: UnsafeMutableRawPointer?,
        bytesPerRow: Int,
        x: Int,
        y: Int
    ) -> Pixel {
        guard let data else { return Pixel(red: 0, green: 0, blue: 0, alpha: 0) }
        let byte = data.assumingMemoryBound(to: UInt8.self) + y * bytesPerRow + x * 4

        let alpha = Double(byte[3]) / 255
        guard alpha > 0 else { return Pixel(red: 0, green: 0, blue: 0, alpha: 0) }

        return Pixel(
            red: Double(byte[2]) / 255 / alpha,
            green: Double(byte[1]) / 255 / alpha,
            blue: Double(byte[0]) / 255 / alpha,
            alpha: alpha
        )
    }
}
