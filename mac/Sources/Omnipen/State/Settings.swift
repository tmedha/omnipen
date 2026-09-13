import Foundation
import OmnipenCore

/// Defaults in one place so the palette and the tools cannot disagree.
enum Settings {
    /// The eight colour slots bound to keys 1 through 8.
    static let swatches: [InkColor] = [
        InkColor(red: 0.93, green: 0.20, blue: 0.24),   // red
        InkColor(red: 0.98, green: 0.55, blue: 0.10),   // orange
        InkColor(red: 0.98, green: 0.82, blue: 0.14),   // yellow
        InkColor(red: 0.24, green: 0.76, blue: 0.38),   // green
        InkColor(red: 0.16, green: 0.52, blue: 0.96),   // blue
        InkColor(red: 0.61, green: 0.35, blue: 0.92),   // purple
        InkColor(red: 1.00, green: 1.00, blue: 1.00),   // white
        InkColor(red: 0.10, green: 0.10, blue: 0.11),   // near-black
    ]

    /// Tools shown in the palette, in order. Grows as later milestones land.
    /// One slot in the palette's main row.
    enum PaletteEntry {
        case tool(ToolKind)
        /// A single button standing in for the four shapes, which keeps the bar
        /// short enough to stay unobtrusive on a shared screen.
        case shapes
    }

    static let paletteRow: [PaletteEntry] = [
        .tool(.laser), .tool(.spotlight), .tool(.pen), .tool(.highlighter),
        .shapes, .tool(.eraser),
    ]

    static let shapeTools: [ToolKind] = [.line, .arrow, .rectangle, .ellipse]

    /// Everything selectable, used by the menu bar.
    static var allTools: [ToolKind] {
        paletteRow.compactMap { if case .tool(let tool) = $0 { tool } else { nil } } + shapeTools
    }

    static let defaultStrokeWidth: Double = 4
    static let minStrokeWidth: Double = 1
    static let maxStrokeWidth: Double = 28
    static let strokeWidthStep: Double = 2

    /// The highlighter reuses the pen's hue, but wide and translucent.
    static let highlighterAlpha: Double = 0.35
    static let highlighterWidthMultiplier: Double = 5

    static let eraserRadius: Double = 14

    static let minimumPointDistance: Double = 1.5

    /// Committed strokes are redrawn directly until there are this many, past
    /// which they get baked into a bitmap. A full-screen bitmap costs about
    /// 95 MB on a Retina display, and a typical meeting never draws enough for
    /// the direct path to cost anything measurable.
    static let bakeThreshold = 24

    static let spotlightDimAlpha: Double = 0.55
    static let laserTrailDuration: Double = 0.45

    /// The spotlight hole and the laser dot both scale off the width control, so
    /// the slider and the bracket keys size them without needing their own UI.
    static func spotlightRadius(forWidth width: Double) -> Double {
        60 + width * 6
    }

    static func laserDotDiameter(forWidth width: Double) -> Double {
        max(10, width * 2.5)
    }
}
