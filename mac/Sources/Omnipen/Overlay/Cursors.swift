import AppKit

enum Cursors {

    /// Sized to the eraser's actual reach, so what gets removed matches what the
    /// cursor covers. Doubled in black and white to stay visible over anything.
    static let eraser: NSCursor = {
        let radius = Settings.eraserRadius
        let diameter = radius * 2
        let inset: CGFloat = 2
        let size = NSSize(width: diameter + inset * 2, height: diameter + inset * 2)

        let image = NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return true }
            let circle = CGRect(x: inset, y: inset, width: diameter, height: diameter)

            context.setLineWidth(3)
            context.setStrokeColor(CGColor(gray: 0, alpha: 0.55))
            context.strokeEllipse(in: circle)

            context.setLineWidth(1.5)
            context.setStrokeColor(CGColor(gray: 1, alpha: 0.95))
            context.strokeEllipse(in: circle)
            return true
        }

        return NSCursor(image: image, hotSpot: NSPoint(x: size.width / 2, y: size.height / 2))
    }()
}
