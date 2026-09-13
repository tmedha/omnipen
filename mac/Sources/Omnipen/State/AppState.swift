import Combine
import Foundation
import OmnipenCore

/// Global, display-independent state: what mode the pen is in and which tool,
/// colour, and width it is carrying. Ink itself lives per-display in the
/// overlay coordinator.
@MainActor
final class AppState: ObservableObject {

    /// - `off`: overlays hidden. Ink is retained and reappears when re-armed.
    /// - `armed`: overlays visible and capturing the mouse.
    /// - `passthrough`: overlays visible but transparent to the mouse, so the
    ///   app underneath is usable with the annotations still on screen.
    enum Mode: Equatable {
        case off
        case armed
        case passthrough

        var showsOverlay: Bool { self != .off }
        var capturesMouse: Bool { self == .armed }
    }

    @Published private(set) var mode: Mode = .off
    @Published var tool: ToolKind = .pen
    @Published var colorIndex: Int = 0
    @Published var strokeWidth: Double = Settings.defaultStrokeWidth

    /// True while a text field has focus. Bare-key shortcuts are suspended for
    /// the duration, or typing would switch tools instead of entering letters.
    @Published var isEditingText = false

    var color: InkColor { Settings.swatches[colorIndex] }

    /// The colour and width the given tool actually draws with. The highlighter
    /// derives both from the pen's current settings rather than carrying its own,
    /// so switching tools keeps the chosen hue.
    func inkColor(for tool: ToolKind) -> InkColor {
        tool == .highlighter ? color.withAlpha(Settings.highlighterAlpha) : color
    }

    func inkWidth(for tool: ToolKind) -> Double {
        tool == .highlighter ? strokeWidth * Settings.highlighterWidthMultiplier : strokeWidth
    }

    func toggleArmed() {
        mode = (mode == .off) ? .armed : .off
    }

    /// Esc steps down one level. Armed drops to passthrough so the ink survives
    /// while the app underneath becomes clickable; a second Esc puts it away.
    func stepDown() {
        switch mode {
        case .armed: mode = .passthrough
        case .passthrough: mode = .off
        case .off: break
        }
    }

    func arm() { mode = .armed }

    func disarm() { mode = .off }

    /// The palette's click-through switch, and the way back from passthrough to
    /// drawing without putting the pen away first.
    func togglePassthrough() {
        switch mode {
        case .armed: mode = .passthrough
        case .passthrough, .off: mode = .armed
        }
    }

    /// Picking a tool implies wanting to use it.
    func setTool(_ tool: ToolKind) {
        self.tool = tool
        if mode != .armed { mode = .armed }
    }

    func selectColor(index: Int) {
        guard Settings.swatches.indices.contains(index) else { return }
        colorIndex = index
    }

    func adjustWidth(by delta: Double) {
        strokeWidth = min(Settings.maxStrokeWidth, max(Settings.minStrokeWidth, strokeWidth + delta))
    }
}
