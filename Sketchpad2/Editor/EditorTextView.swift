import AppKit

/// `NSTextView` configured and extended for code: syntax highlighting, current-line
/// highlight, smart indentation, bracket pairing, and comment toggling.
@MainActor
final class EditorTextView: NSTextView {

    static let indentUnit = "  "

    /// Undo manager handed down from the SwiftUI document environment so edits take
    /// part in the document's undo stack and edited state.
    var injectedUndoManager: UndoManager?

    var editorFont: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular)
    var theme: SyntaxTheme = .standard
    var defaultTextColor: NSColor = .textColor

    private var currentLineRect: NSRect?
    private var isHighlightScheduled = false

    override var undoManager: UndoManager? {
        injectedUndoManager ?? super.undoManager
    }

    // MARK: - Highlighting

    func applyHighlighting() {
        guard let storage = textStorage else { return }
        let undo = undoManager
        undo?.disableUndoRegistration()
        SyntaxHighlighter.highlight(storage, font: editorFont, defaultColor: defaultTextColor, theme: theme)
        undo?.enableUndoRegistration()
        typingAttributes = [.font: editorFont, .foregroundColor: defaultTextColor]
        updateCurrentLineRect()
    }

    private func scheduleHighlighting() {
        guard !isHighlightScheduled else { return }
        isHighlightScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isHighlightScheduled = false
            self.applyHighlighting()
        }
    }

    override func didChangeText() {
        super.didChangeText()
        typingAttributes = [.font: editorFont, .foregroundColor: defaultTextColor]
        scheduleHighlighting()
        updateCurrentLineRect()
    }

    // MARK: - Current line highlight

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let lineRect = currentLineRect else { return }
        let visible = lineRect.intersection(rect)
        guard !visible.isNull, visible.height > 0 else { return }
        NSColor.selectedTextBackgroundColor.withAlphaComponent(0.12).setFill()
        visible.fill()
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        updateCurrentLineRect()
    }

    private func updateCurrentLineRect() {
        guard let layoutManager = textLayoutManager else {
            currentLineRect = nil
            return
        }

        let text = string as NSString
        let caret = min(max(0, selectedRange().location), text.length)
        let lineRange = text.lineRange(for: NSRange(location: caret, length: 0))
        guard let location = layoutManager.location(layoutManager.documentRange.location, offsetBy: lineRange.location),
              let fragment = layoutFragment(containing: location, in: layoutManager) else {
            currentLineRect = nil
            return
        }

        let frame = fragment.layoutFragmentFrame
        currentLineRect = NSRect(
            x: 0,
            y: frame.minY + textContainerInset.height,
            width: bounds.width,
            height: frame.height
        )
        needsDisplay = true
    }

    private func layoutFragment(containing location: NSTextLocation, in layoutManager: NSTextLayoutManager) -> NSTextLayoutFragment? {
        if let fragment = layoutManager.textLayoutFragment(for: location) {
            return fragment
        }
        var found: NSTextLayoutFragment?
        layoutManager.enumerateTextLayoutFragments(from: location, options: [.ensuresLayout]) { fragment in
            found = fragment
            return false
        }
        return found
    }

    // MARK: - Commands

    override func insertNewline(_ sender: Any?) {
        insertSmartNewline()
    }

    override func insertTab(_ sender: Any?) {
        applyLineTransform(mode: .indent)
    }

    override func insertBacktab(_ sender: Any?) {
        applyLineTransform(mode: .dedent)
    }

    override func deleteBackward(_ sender: Any?) {
        if deleteEmptyPair() { return }
        super.deleteBackward(sender)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        guard let typed = string as? String, typed.count == 1, let character = typed.first else {
            super.insertText(string, replacementRange: replacementRange)
            return
        }
        if handlePairing(character) { return }
        super.insertText(string, replacementRange: replacementRange)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isCommentShortcut(event) {
            toggleComment()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if isCommentShortcut(event) {
            toggleComment()
            return
        }
        super.keyDown(with: event)
    }

    private func isCommentShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), !flags.contains(.option), !flags.contains(.control) else { return false }
        return event.charactersIgnoringModifiers == "/"
    }
}
