import CoreGraphics
import CoreText
import Foundation
import OmnipenCore

/// Lays out and draws `.text` strokes with Core Text.
///
/// Lines are laid out by hand rather than through a framesetter: annotation text
/// is short, and hard-wrapping it to a box would need a width the user never
/// chose. Each newline simply starts a new line.
public enum TextRenderer {

    /// Maps the shared width control onto a usable type size. The raw width range
    /// bottoms out around 1pt, which would be illegible as text.
    public static func fontSize(forWidth width: Double) -> Double {
        max(13, width * 3)
    }

    public static func font(forWidth width: Double) -> CTFont {
        CTFontCreateUIFontForLanguage(.system, fontSize(forWidth: width), nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, fontSize(forWidth: width), nil)
    }

    /// The size the block will occupy, stored on the stroke so the model can
    /// compute bounds without a text engine.
    public static func measure(_ text: String, width: Double) -> CGSize {
        let font = font(forWidth: width)
        let lineHeight = self.lineHeight(font)
        let lines = text.components(separatedBy: "\n")

        var widest: Double = 0
        for line in lines {
            let typographic = CTLineGetTypographicBounds(ctLine(line, font: font, color: nil), nil, nil, nil)
            widest = max(widest, typographic)
        }
        return CGSize(width: widest, height: lineHeight * Double(lines.count))
    }

    public static func draw(_ stroke: Stroke, in context: CGContext) {
        guard let text = stroke.text, !text.isEmpty, let origin = stroke.points.first else { return }

        let font = font(forWidth: stroke.width)
        let lineHeight = self.lineHeight(font)
        let ascent = CTFontGetAscent(font)
        let color = StrokeRenderer.cgColor(stroke.color)

        context.saveGState()
        defer { context.restoreGState() }
        // Core Text emits glyphs the right way up in a bottom-left context, so no
        // flip is needed, only a baseline per line walking downward.
        context.setAllowsAntialiasing(true)

        for (index, line) in text.components(separatedBy: "\n").enumerated() {
            guard !line.isEmpty else { continue }
            let baseline = origin.y - ascent - lineHeight * Double(index)
            context.textPosition = CGPoint(x: origin.x, y: baseline)
            CTLineDraw(ctLine(line, font: font, color: color), context)
        }
    }

    private static func lineHeight(_ font: CTFont) -> Double {
        CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
    }

    private static func ctLine(_ string: String, font: CTFont, color: CGColor?) -> CTLine {
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        if let color {
            attributes[.foregroundColor] = color
        }
        return CTLineCreateWithAttributedString(
            NSAttributedString(string: string, attributes: attributes)
        )
    }
}
