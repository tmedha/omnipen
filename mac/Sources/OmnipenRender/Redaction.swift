import CoreGraphics
import CoreImage
import Foundation

/// Destroys detail in a captured region so it can be shown without being read.
///
/// Pixelation rather than a plain blur: a gaussian blur is a reversible
/// convolution and small text can sometimes be recovered from it, whereas
/// averaging whole blocks genuinely discards the information. A light blur
/// afterwards only softens the block edges.
public enum Redaction {

    /// Scaled to the region, so a small redaction is still coarse enough to be
    /// unreadable.
    public static func blockSize(for size: CGSize) -> Double {
        let shortest = min(size.width, size.height)
        return max(10, shortest / 8)
    }

    public static func pixelate(_ image: CGImage, blockSize: Double? = nil) -> CGImage? {
        let extent = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard extent.width > 0, extent.height > 0 else { return nil }

        let block = blockSize ?? self.blockSize(
            for: CGSize(width: image.width, height: image.height)
        )

        let source = CIImage(cgImage: image)
        guard
            let pixelated = CIFilter(
                name: "CIPixellate",
                parameters: [
                    kCIInputImageKey: source.clampedToExtent(),
                    kCIInputScaleKey: block,
                    kCIInputCenterKey: CIVector(x: 0, y: 0),
                ]
            )?.outputImage,
            let softened = CIFilter(
                name: "CIGaussianBlur",
                parameters: [
                    kCIInputImageKey: pixelated.clampedToExtent(),
                    kCIInputRadiusKey: block / 4,
                ]
            )?.outputImage
        else { return nil }

        // Clamping extended the image to infinity, so crop back before rendering.
        return CIContext(options: [.useSoftwareRenderer: false])
            .createCGImage(softened, from: extent)
    }
}
