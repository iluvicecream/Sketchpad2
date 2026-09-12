//
//  CoreEditorView.swift
//  Sketchpad
//
//  Created by perr on 9/12/2569 BE.
//

import SwiftUI
import STTextView
import AppKit

struct CoreEditorView : NSViewRepresentable {
    @Binding var text: String
    var font: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular)
    var showLineNumbers: Bool = true
    var highlightSelectedLine: Bool = true
    var wrapLines: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        // Create scrollable container provided by STTextView
        let scrollView = STTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? STTextView else {
            return scrollView
        }

        // Setup Delegate and Configurations
        textView.textDelegate = context.coordinator
        textView.font = font
        textView.showsLineNumbers = showLineNumbers
        textView.highlightSelectedLine = highlightSelectedLine
        textView.isHorizontallyResizable = !wrapLines
        textView.allowsUndo = true

        // Set initial content
        textView.text = text
        context.coordinator.lastHandledText = text

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? STTextView else { return }

        // Update view only if text changed externally (e.g., file revert/open)
        if context.coordinator.lastHandledText != text && textView.text != text {
            context.coordinator.lastHandledText = text
            textView.text = text
        }
    }

    // MARK: - Coordinator
    class Coordinator: NSObject, STTextViewDelegate {
        var parent: CoreEditorView
        var lastHandledText: String = ""

        init(_ parent: CoreEditorView) {
            self.parent = parent
        }

        // Fires when user types in STTextView
        func textViewDidChangeText(_ notification: Notification) {
            guard let textView = notification.object as? STTextView else { return }
            let newText = textView.text
            lastHandledText = newText ?? ""

            // Defer state mutation to prevent "Modifying state during view update"
            DispatchQueue.main.async {
                if self.parent.text != newText {
                    self.parent.text = newText ?? ""
                }
            }
        }
    }
}
