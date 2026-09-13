import OmnipenCore
import SwiftUI

enum PaletteMetrics {
    static let buttonSize: CGFloat = 30
    static let barPadding: CGFloat = 6
    static let cornerRadius: CGFloat = 14
    static let swatchSize: CGFloat = 18
}

struct PaletteView: View {
    @ObservedObject var state: AppState
    @ObservedObject var model: PaletteModel
    let actions: PaletteActions

    var body: some View {
        VStack(spacing: 0) {
            bar
            if model.isColorRowOpen && !model.isCollapsed {
                Divider().opacity(0.4)
                colorRow
            }
        }
        .padding(PaletteMetrics.barPadding)
        .fixedSize()
    }

    private var bar: some View {
        HStack(spacing: 4) {
            DragGrip()
                .frame(width: 14, height: PaletteMetrics.buttonSize)

            if model.isCollapsed {
                // Collapsed shows only which tool is loaded, so a shared screen
                // stays as clean as possible.
                toolButton(state.tool)
            } else {
                separator
                passthroughButton
                ForEach(Settings.paletteTools, id: \.self) { toolButton($0) }
                separator
                colorButton
                separator
                iconButton("arrow.uturn.backward", help: "Undo (⌘Z)", action: actions.undo)
                iconButton("trash", help: "Clear all (⇧⌥⌘D)", action: actions.clearAll)
            }

            separator
            iconButton(
                model.isCollapsed ? "chevron.right" : "chevron.left",
                help: model.isCollapsed ? "Expand" : "Collapse"
            ) {
                model.isCollapsed.toggle()
            }
        }
    }

    /// Reflects and toggles click-through. Highlighted while passthrough is on,
    /// which is what tells the user their clicks are reaching the app below.
    private var passthroughButton: some View {
        let isOn = state.mode == .passthrough
        return Button {
            state.togglePassthrough()
        } label: {
            Image(systemName: "cursorarrow")
                .font(.system(size: 13, weight: .medium))
                .frame(width: PaletteMetrics.buttonSize, height: PaletteMetrics.buttonSize)
                .foregroundStyle(isOn ? Color.white : .primary)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isOn ? Color.accentColor : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isOn ? "Clicking through. Click to draw again (Esc)" : "Click through (Esc)")
    }

    private var colorRow: some View {
        HStack(spacing: 8) {
            ForEach(Array(Settings.swatches.enumerated()), id: \.offset) { index, swatch in
                Button {
                    state.selectColor(index: index)
                } label: {
                    Circle()
                        .fill(Color(swatch))
                        .frame(width: PaletteMetrics.swatchSize, height: PaletteMetrics.swatchSize)
                        .overlay(
                            Circle().stroke(.primary.opacity(0.25), lineWidth: 0.5)
                        )
                        .overlay(
                            Circle()
                                .stroke(.primary, lineWidth: 2)
                                .padding(-3)
                                .opacity(state.colorIndex == index ? 1 : 0)
                        )
                }
                .buttonStyle(.plain)
                .help("Colour \(index + 1)")
            }

            Slider(
                value: $state.strokeWidth,
                in: Settings.minStrokeWidth...Settings.maxStrokeWidth
            )
            .frame(width: 90)
            .controlSize(.mini)
            .help("Stroke width ([ and ])")
        }
        .padding(.top, 8)
        .padding(.horizontal, 4)
    }

    private func toolButton(_ tool: ToolKind) -> some View {
        let isSelected = state.tool == tool
        return Button {
            state.setTool(tool)
        } label: {
            Image(systemName: tool.symbolName)
                .font(.system(size: 14, weight: .medium))
                .frame(width: PaletteMetrics.buttonSize, height: PaletteMetrics.buttonSize)
                // The selected tool carries the current ink colour, so the palette
                // answers "what will this draw" without opening the colour row.
                .foregroundStyle(isSelected ? Color(state.color).contrastingText : .primary)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color(state.color) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tool.displayName)
    }

    private var colorButton: some View {
        Button {
            model.isColorRowOpen.toggle()
        } label: {
            HStack(spacing: 2) {
                Circle()
                    .fill(Color(state.color))
                    .frame(width: PaletteMetrics.swatchSize, height: PaletteMetrics.swatchSize)
                    .overlay(Circle().stroke(.primary.opacity(0.25), lineWidth: 0.5))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(model.isColorRowOpen ? 180 : 0))
            }
            .frame(height: PaletteMetrics.buttonSize)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Colour and width")
    }

    private func iconButton(
        _ symbol: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: PaletteMetrics.buttonSize, height: PaletteMetrics.buttonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var separator: some View {
        Divider().frame(height: 18).opacity(0.4)
    }
}

/// Hands the drag straight to AppKit so the panel moves natively, rather than
/// trying to chase the cursor from a SwiftUI gesture.
private struct DragGrip: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { GripView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class GripView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.tertiaryLabelColor.setFill()
            let dotSize: CGFloat = 2.5
            let spacing: CGFloat = 4.5
            for column in 0..<2 {
                for row in 0..<3 {
                    let origin = NSPoint(
                        x: bounds.midX - spacing / 2 - dotSize / 2 + CGFloat(column) * spacing,
                        y: bounds.midY - spacing - dotSize / 2 + CGFloat(row) * spacing
                    )
                    NSBezierPath(
                        ovalIn: NSRect(origin: origin, size: NSSize(width: dotSize, height: dotSize))
                    ).fill()
                }
            }
        }
    }
}

extension Color {
    init(_ ink: InkColor) {
        self.init(.sRGB, red: ink.red, green: ink.green, blue: ink.blue, opacity: ink.alpha)
    }

    /// Black or white, whichever stays legible on this colour. Keeps the selected
    /// tool's glyph readable on both the yellow and the near-black swatches.
    var contrastingText: Color {
        let components = NSColor(self).usingColorSpace(.sRGB)
        let luminance = 0.299 * Double(components?.redComponent ?? 0)
            + 0.587 * Double(components?.greenComponent ?? 0)
            + 0.114 * Double(components?.blueComponent ?? 0)
        return luminance > 0.6 ? .black : .white
    }
}
