import AppKit
import SwiftUI

/// Native code editor for Arduino sketches.
///
/// The SwiftUI document's `String` stays the single source of truth: the coordinator
/// pushes edits out of the text view, and `updateNSView` only writes back when the
/// document changed underneath the editor (file reload, revert, or undo elsewhere).
struct CodeEditorView: NSViewRepresentable {
    @Binding var text: String
    @Environment(\.undoManager) private var undoManager

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = EditorTextView(usingTextLayoutManager: true)
        textView.delegate = context.coordinator
        configure(textView)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        // The editor underlaps the title bar, so let AppKit inset the content past it.
        scrollView.automaticallyAdjustsContentInsets = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let ruler = GutterRulerView(scrollView: scrollView, textView: textView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        context.coordinator.ruler = ruler

        textView.string = text
        textView.applyHighlighting()
        ruler.updateLineCount(from: textView)
        ruler.updateCurrentLine(from: textView)

        Task { @MainActor in
            textView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? EditorTextView else { return }
        textView.injectedUndoManager = undoManager

        guard textView.string != text else { return }
        let selection = textView.selectedRange()
        textView.string = text
        textView.applyHighlighting()
        textView.undoManager?.removeAllActions()
        let caret = min(selection.location, (text as NSString).length)
        textView.setSelectedRange(NSRange(location: caret, length: 0))

        context.coordinator.ruler?.updateLineCount(from: textView)
        context.coordinator.ruler?.updateCurrentLine(from: textView)
    }

    private func configure(_ textView: EditorTextView) {
        textView.editorFont = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.font = textView.editorFont
        textView.defaultTextColor = .textColor
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.textContainerInset = NSSize(width: 8, height: 6)

        // Code must not be rewritten by the text system.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false

        // Long lines scroll instead of wrapping.
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        weak var ruler: GutterRulerView?

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if text.wrappedValue != textView.string {
                text.wrappedValue = textView.string
            }
            ruler?.updateLineCount(from: textView)
            ruler?.updateCurrentLine(from: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            ruler?.updateCurrentLine(from: textView)
        }
    }
}
