//
//  LineNumberRulerView.swift
//  Sketchpad
//

import AppKit

/// Draws right-aligned line numbers in a scroll view's vertical ruler.
///
/// The ruler only draws the line fragments that intersect the visible rect, and
/// it relies on the editor not wrapping lines so that one layout fragment maps
/// to exactly one logical line.
final class LineNumberRulerView: NSRulerView {

    private weak var textView: NSTextView?
    private let numberFont: NSFont
    private var digitCount = 2

    private static let horizontalPadding: CGFloat = 6
    private static let lineFeed: unichar = 0x0A

    init(textView: NSTextView, scrollView: NSScrollView, font: NSFont) {
        self.textView = textView
        self.numberFont = font
        super.init(scrollView: scrollView, orientation: .verticalRuler)

        clientView = textView
        ruleThickness = thickness(forDigitCount: digitCount)

        scrollView.contentView.postsBoundsChangedNotifications = true
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleTextChange),
            name: NSText.didChangeNotification,
            object: textView
        )
        center.addObserver(
            self,
            selector: #selector(handleViewportChange),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        center.addObserver(
            self,
            selector: #selector(handleViewportChange),
            name: NSView.frameDidChangeNotification,
            object: textView
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()

        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let text = textView.string as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: numberFont,
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        guard layoutManager.numberOfGlyphs > 0 else {
            draw(number: 1, lineRect: .zero, textView: textView, attributes: attributes)
            return
        }

        let visibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        guard glyphRange.length > 0 else { return }

        // The visible glyph range can start mid-line, so anchor the first number
        // on the first whole line fragment that intersects the viewport.
        let anchorGlyph = min(glyphRange.location, layoutManager.numberOfGlyphs - 1)
        var anchorGlyphRange = NSRange()
        _ = layoutManager.lineFragmentRect(forGlyphAt: anchorGlyph, effectiveRange: &anchorGlyphRange)
        let anchorCharacterRange = layoutManager.characterRange(forGlyphRange: anchorGlyphRange, actualGlyphRange: nil)
        var lineNumber = 1 + newlineCount(
            in: text,
            range: NSRange(location: 0, length: min(anchorCharacterRange.location, text.length))
        )

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { fragmentRect, _, _, lineGlyphRange, _ in
            self.draw(number: lineNumber, lineRect: fragmentRect, textView: textView, attributes: attributes)

            let lineCharacterRange = layoutManager.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)
            lineNumber += max(1, self.newlineCount(in: text, in: lineCharacterRange))
        }
    }

    private func draw(
        number: Int,
        lineRect: NSRect,
        textView: NSTextView,
        attributes: [NSAttributedString.Key: Any]
    ) {
        let label = "\(number)" as NSString
        let size = label.size(withAttributes: attributes)

        let containerOrigin = textView.textContainerOrigin
        let rectInText = NSRect(
            x: 0,
            y: lineRect.minY + containerOrigin.y,
            width: 1,
            height: max(lineRect.height, size.height)
        )
        let rectInRuler = convert(rectInText, from: textView)

        let origin = NSPoint(
            x: ruleThickness - size.width - Self.horizontalPadding,
            y: rectInRuler.minY + (rectInRuler.height - size.height) / 2
        )
        label.draw(at: origin, withAttributes: attributes)
    }

    private func newlineCount(in text: NSString, in range: NSRange) -> Int {
        let start = max(0, range.location)
        let end = min(range.location + range.length, text.length)
        guard start < end else { return 0 }

        var count = 0
        for index in start..<end where text.character(at: index) == Self.lineFeed {
            count += 1
        }
        return count
    }

    @objc private func handleTextChange() {
        updateThickness()
        needsDisplay = true
    }

    @objc private func handleViewportChange() {
        needsDisplay = true
    }

    private func updateThickness() {
        guard let textView else { return }
        let text = textView.string as NSString
        let lineCount = newlineCount(in: text, in: NSRange(location: 0, length: text.length)) + 1
        let digits = max(2, String(lineCount).count)
        guard digits != digitCount else { return }

        digitCount = digits
        ruleThickness = thickness(forDigitCount: digits)
        needsDisplay = true
    }

    private func thickness(forDigitCount digits: Int) -> CGFloat {
        let digitWidth = ("0" as NSString).size(withAttributes: [.font: numberFont]).width
        return (digitWidth * CGFloat(digits)).rounded(.up) + Self.horizontalPadding * 2
    }
}
