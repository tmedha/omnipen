import Foundation

/// Cases reporting `producesInk` enter the stroke store; the rest render
/// transiently.
public enum ToolKind: String, CaseIterable, Codable, Sendable {
    case laser
    case pen
    case highlighter
    case eraser
    case text
    case line
    case arrow
    case rectangle
    case ellipse
    case spotlight
    case blur
    case snapshot

    public var producesInk: Bool {
        switch self {
        case .pen, .highlighter, .text, .line, .arrow, .rectangle, .ellipse, .blur:
            return true
        case .laser, .eraser, .spotlight, .snapshot:
            return false
        }
    }

    public var isDragShape: Bool {
        switch self {
        case .line, .arrow, .rectangle, .ellipse, .blur:
            return true
        default:
            return false
        }
    }

    public var displayName: String {
        switch self {
        case .laser: return "Laser"
        case .pen: return "Pen"
        case .highlighter: return "Highlighter"
        case .eraser: return "Eraser"
        case .text: return "Text"
        case .line: return "Line"
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .spotlight: return "Spotlight"
        case .blur: return "Blur"
        case .snapshot: return "Snapshot"
        }
    }

    /// Kept out of the view layer so the palette and menu bar cannot drift apart.
    public var symbolName: String {
        switch self {
        case .laser: return "cursorarrow.rays"
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .eraser: return "eraser"
        case .text: return "textbox"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .spotlight: return "flashlight.on.fill"
        case .blur: return "drop.halffull"
        case .snapshot: return "viewfinder"
        }
    }
}
