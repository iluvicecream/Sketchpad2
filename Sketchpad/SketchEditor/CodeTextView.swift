//
//  CodeTextView.swift
//  Sketchpad
//

import AppKit

/// An `NSTextView` that can publish its edits to an external undo manager and
/// notify its owner when the effective appearance changes.
final class CodeTextView: NSTextView {

    /// When set, edits are registered with this undo manager instead of the one
    /// `NSTextView` would otherwise create for itself.
    var externalUndoManager: UndoManager?

    /// Called when the view starts using a different appearance, so dynamic
    /// colors can be re-resolved.
    var onEffectiveAppearanceChange: (() -> Void)?

    override var undoManager: UndoManager? {
        externalUndoManager ?? super.undoManager
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onEffectiveAppearanceChange?()
    }
}
