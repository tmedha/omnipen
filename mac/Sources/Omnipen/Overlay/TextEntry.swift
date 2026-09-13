import AppKit
import OmnipenCore
import OmnipenRender

/// Keystrokes only reach a window of the active application, so unlike every
/// other tool this activates Omnipen while editing and hands focus back on
/// commit. Bare-key shortcuts are suspended meanwhile, or typing "p" would
/// switch to the pen instead of entering a letter.
@MainActor
final class TextEntry: NSTextView {

    private let onCommit: (String) -> Void

    init(origin: CGPoint, color: InkColor, width: Double, onCommit: @escaping (String) -> Void) {
        self.onCommit = onCommit

        let fontSize = TextRenderer.fontSize(forWidth: width)
        // Generous, since the frame is only the editing affordance; the committed
        // stroke is measured to its real size.
        let height = fontSize * 1.6
        super.init(frame: NSRect(x: origin.x - 4, y: origin.y - height, width: 420, height: height))

        font = NSFont.systemFont(ofSize: fontSize)
        textColor = NSColor(
            srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha
        )
        insertionPointColor = textColor
        drawsBackground = true
        backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.22)
        isRichText = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isVerticallyResizable = true
        textContainerInset = NSSize(width: 2, height: 2)
        wantsLayer = true
        layer?.cornerRadius = 4
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Esc commits rather than discards: losing typed text to a stray keypress is
    /// worse than committing something the user can immediately undo.
    override func cancelOperation(_ sender: Any?) {
        commit()
    }

    override func insertNewline(_ sender: Any?) {
        // Enter commits, Shift-Enter and Option-Enter add a line, matching how
        // chat and comment fields behave.
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        if flags.contains(.shift) || flags.contains(.option) {
            insertNewlineIgnoringFieldEditor(sender)
        } else {
            commit()
        }
    }

    func commit() {
        onCommit(string)
    }
}
