import AppKit

/// Marker kinds the gutter can render next to a line.
enum GutterMark: Sendable, Hashable {
    case breakpoint
    case bookmark
    case error
    case warning
}

/// Line-number gutter with a reserved marker lane.
///
/// Line numbers come from the text view's TextKit 2 layout fragments, so they stay
/// aligned while scrolling. The marker lane is drawn but intentionally empty: it is
/// the seam where compile diagnostics or breakpoints can be attached later.
@MainActor
final class GutterRulerView: NSRulerView {

    /// Marks keyed by one-based line number.
    var marks: [Int: GutterMark] = [:] {
        didSet { needsDisplay = true }
    }

    /// One-based number of the line containing the insertion point.
    var currentLine: Int = 1 {
        didSet {
            if currentLine != oldValue { needsDisplay = true }
        }
    }

    private(set) var lineCount: Int = 1 {
        didSet {
            if lineCount != oldValue { updateThickness() }
        }
    }

    private let markerLaneWidth: CGFloat = 16
    private let numberPadding: CGFloat = 8
    private let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private var numberAttributes: [NSAttributedString.Key: Any] {
        [.font: numberFont, .foregroundColor: NSColor.secondaryLabelColor]
    }
    private var currentNumberAttributes: [NSAttributedString.Key: Any] {
        [.font: numberFont, .foregroundColor: NSColor.labelColor]
    }

    init(scrollView: NSScrollView, textView: NSTextView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        // Document windows give the content view the full window height, so AppKit lets the
        // ruler draw up behind the title bar. Clip it to its own bounds so the gutter stops
        // at the top of the code area instead of running through the title bar.
        clipsToBounds = true
        reservedThicknessForMarkers = 0
        reservedThicknessForAccessoryView = 0
        updateThickness()

        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrolledClipView(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("GutterRulerView does not support NSCoding")
    }

    // MARK: - State updates

    /// Recomputes the cached line count. Called when the document text changes.
    func updateLineCount(from textView: NSTextView) {
        let text = textView.string as NSString
        lineCount = newlineCount(in: text, limit: text.length) + 1
        needsDisplay = true
    }

    /// Recomputes the highlighted line from the text view's insertion point.
    func updateCurrentLine(from textView: NSTextView) {
        let text = textView.string as NSString
        let caret = min(max(0, textView.selectedRange().location), text.length)
        currentLine = newlineCount(in: text, limit: caret) + 1
    }

    /// Counts line breaks before `limit`, treating CRLF as a single break.
    private func newlineCount(in text: NSString, limit: Int) -> Int {
        var count = 0
        var index = 0
        while index < limit {
            let found = text.rangeOfCharacter(
                from: .newlines,
                options: [],
                range: NSRange(location: index, length: limit - index)
            )
            guard found.location != NSNotFound else { break }
            count += 1
            var next = found.location + found.length
            if text.character(at: found.location) == 0x0D, next < text.length, text.character(at: next) == 0x0A {
                next += 1
            }
            index = next
        }
        return count
    }

    // MARK: - Drawing

    override func drawHashMarksAndLabels(in rect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()

        NSColor.separatorColor.setFill()
        NSRect(x: bounds.maxX - 1, y: bounds.minY, width: 1, height: bounds.height).fill()

        guard let textView = clientView as? NSTextView,
              let layoutManager = textView.textLayoutManager else {
            return
        }

        let inset = textView.textContainerInset
        let normal = numberAttributes
        let current = currentNumberAttributes
        var lineNumber = 1

        layoutManager.enumerateTextLayoutFragments(
            from: layoutManager.documentRange.location,
            options: [.ensuresLayout]
        ) { fragment in
            let frame = fragment.layoutFragmentFrame
            let top = self.convert(NSPoint(x: 0, y: frame.minY + inset.height), from: textView).y
            let lineRect = NSRect(x: 0, y: top, width: self.bounds.width, height: frame.height)

            if lineRect.minY > rect.maxY {
                return false
            }

            if lineRect.maxY >= rect.minY {
                self.drawLineNumber(lineNumber, in: lineRect, attributes: lineNumber == self.currentLine ? current : normal)
                self.drawMark(for: lineNumber, in: lineRect)
            }

            lineNumber += self.paragraphCount(of: fragment)
            return true
        }
    }

    private func drawLineNumber(_ lineNumber: Int, in lineRect: NSRect, attributes: [NSAttributedString.Key: Any]) {
        let text = "\(lineNumber)" as NSString
        let size = text.size(withAttributes: attributes)
        let y = lineRect.midY - size.height / 2
        text.draw(at: NSPoint(x: bounds.width - numberPadding - size.width, y: y), withAttributes: attributes)
    }

    private func drawMark(for lineNumber: Int, in lineRect: NSRect) {
        guard let mark = marks[lineNumber] else { return }
        let diameter: CGFloat = 7
        let dot = NSRect(
            x: (markerLaneWidth - diameter) / 2,
            y: lineRect.midY - diameter / 2,
            width: diameter,
            height: diameter
        )
        color(for: mark).setFill()
        NSBezierPath(ovalIn: dot).fill()
    }

    private func color(for mark: GutterMark) -> NSColor {
        switch mark {
        case .breakpoint: return .systemBlue
        case .bookmark: return .systemGreen
        case .error: return .systemRed
        case .warning: return .systemYellow
        }
    }

    /// Number of lines covered by a layout fragment. Wrapping is off, so a fragment
    /// is normally a single line; the newline count keeps multi-paragraph fragments correct.
    private func paragraphCount(of fragment: NSTextLayoutFragment) -> Int {
        guard let paragraph = fragment.textElement as? NSTextParagraph else { return 1 }
        let text = paragraph.attributedString.string as NSString
        var count = 0
        var index = 0
        while index < text.length {
            let found = text.rangeOfCharacter(from: .newlines, options: [], range: NSRange(location: index, length: text.length - index))
            guard found.location != NSNotFound else { break }
            count += 1
            index = found.location + found.length
        }
        return max(1, count)
    }

    private func updateThickness() {
        let digits = max(2, "\(lineCount)".count)
        let digitWidth = ("0" as NSString).size(withAttributes: numberAttributes).width
        let thickness = markerLaneWidth + digitWidth * CGFloat(digits) + numberPadding * 2
        guard abs(thickness - ruleThickness) > 0.5 else { return }
        ruleThickness = thickness
        scrollView?.tile()
    }

    @objc private func scrolledClipView(_ notification: Notification) {
        needsDisplay = true
    }
}
