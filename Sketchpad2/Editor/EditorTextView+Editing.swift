import AppKit

/// Code-aware editing behavior: smart newlines, indentation, bracket pairing, and
/// comment toggling. All edits go through `shouldChangeText`/`didChangeText` so they
/// participate in undo and update the document binding like normal typing.
extension EditorTextView {

    enum LineTransformMode {
        case indent
        case dedent
        case toggleComment
    }

    // MARK: - Newline and indentation

    func insertSmartNewline() {
        guard let storage = textStorage else { return }
        let text = string as NSString
        let selection = selectedRange()
        let caret = min(max(0, selection.location), text.length)
        let lineRange = text.lineRange(for: NSRange(location: caret, length: 0))
        let indentLength = leadingWhitespaceLength(of: text, in: lineRange)
        let indent = text.substring(with: NSRange(location: lineRange.location, length: indentLength))
        let beforeCaret = text.substring(with: NSRange(location: lineRange.location, length: max(0, caret - lineRange.location)))
        let opensBlock = trimTrailingWhitespace(beforeCaret).hasSuffix("{")
        let closesBlock = utf16Unit(at: caret, in: text) == 0x7D

        let insertion: String
        let caretOffset: Int
        if opensBlock && closesBlock {
            insertion = "\n" + indent + Self.indentUnit + "\n" + indent
            caretOffset = 1 + indent.utf16.count + Self.indentUnit.utf16.count
        } else if opensBlock {
            insertion = "\n" + indent + Self.indentUnit
            caretOffset = insertion.utf16.count
        } else {
            insertion = "\n" + indent
            caretOffset = insertion.utf16.count
        }

        let replaceRange = selection.length > 0 ? selection : NSRange(location: caret, length: 0)
        guard shouldChangeText(in: replaceRange, replacementString: insertion) else { return }
        storage.replaceCharacters(in: replaceRange, with: insertion)
        didChangeText()
        setSelectedRange(NSRange(location: replaceRange.location + caretOffset, length: 0))
    }

    func applyLineTransform(mode: LineTransformMode) {
        guard let storage = textStorage else { return }
        let text = string as NSString
        let selection = selectedRange()
        let blockRange = text.lineRange(for: selection)
        let block = text.substring(with: blockRange)
        let lines = block.components(separatedBy: "\n")

        let transform: (String) -> String
        switch mode {
        case .indent:
            transform = { $0.isEmpty ? $0 : Self.indentUnit + $0 }
        case .dedent:
            transform = Self.dedenting
        case .toggleComment:
            let significant = lines.filter { !Self.isBlank($0) }
            guard !significant.isEmpty else { return }
            transform = significant.allSatisfy(Self.isCommented) ? Self.uncommenting : Self.commenting
        }

        var transformed: [String] = []
        var deltas: [Int] = []
        for line in lines {
            let newLine = transform(line)
            transformed.append(newLine)
            deltas.append((newLine as NSString).length - (line as NSString).length)
        }

        let replacement = transformed.joined(separator: "\n")
        guard replacement != block else { return }
        guard shouldChangeText(in: blockRange, replacementString: replacement) else { return }
        storage.replaceCharacters(in: blockRange, with: replacement)
        didChangeText()

        func remap(_ offset: Int) -> Int {
            let local = offset - blockRange.location
            var originalPrefix = 0
            var transformedPrefix = 0
            for index in lines.indices {
                let originalLength = (lines[index] as NSString).length
                let newLength = (transformed[index] as NSString).length
                if local <= originalPrefix + originalLength {
                    let within = local - originalPrefix
                    let shifted = within > 0 ? within + deltas[index] : within
                    return blockRange.location + transformedPrefix + max(0, min(shifted, newLength))
                }
                originalPrefix += originalLength + 1
                transformedPrefix += newLength + 1
            }
            return blockRange.location + (replacement as NSString).length
        }

        let newStart = remap(selection.location)
        let newEnd = selection.length == 0 ? newStart : remap(NSMaxRange(selection))
        setSelectedRange(NSRange(location: newStart, length: max(0, newEnd - newStart)))
    }

    // MARK: - Bracket and quote pairing

    /// Toggles `//` on the selected lines, or on the insertion point's line.
    func toggleComment() {
        applyLineTransform(mode: .toggleComment)
    }

    func handlePairing(_ character: Character) -> Bool {
        guard let storage = textStorage else { return false }
        let text = string as NSString
        let selection = selectedRange()

        func insert(_ replacement: String, caretOffset: Int, selectionLength: Int = 0) -> Bool {
            guard shouldChangeText(in: selection, replacementString: replacement) else { return true }
            storage.replaceCharacters(in: selection, with: replacement)
            didChangeText()
            setSelectedRange(NSRange(location: selection.location + caretOffset, length: selectionLength))
            return true
        }

        switch character {
        case "(", "[", "{":
            let closer = Self.closingCharacter(for: character)
            if selection.length > 0 {
                let selected = text.substring(with: selection)
                return insert(String(character) + selected + String(closer), caretOffset: 1, selectionLength: selection.length)
            }
            return insert(String(character) + String(closer), caretOffset: 1)

        case "\"", "'":
            if selection.length == 0, utf16Unit(at: selection.location, in: text) == Self.utf16Unit(of: character) {
                setSelectedRange(NSRange(location: selection.location + 1, length: 0))
                return true
            }
            if selection.length > 0 {
                let selected = text.substring(with: selection)
                return insert(String(character) + selected + String(character), caretOffset: 1, selectionLength: selection.length)
            }
            return insert(String(character) + String(character), caretOffset: 1)

        case ")", "]", "}":
            if selection.length == 0, utf16Unit(at: selection.location, in: text) == Self.utf16Unit(of: character) {
                setSelectedRange(NSRange(location: selection.location + 1, length: 0))
                return true
            }
            if character == "}" { return handleClosingBrace() }
            return false

        default:
            return false
        }
    }

    /// Dedents a closing brace and collapses the auto-indented blank line that
    /// `insertSmartNewline` leaves between a matching pair.
    private func handleClosingBrace() -> Bool {
        guard let storage = textStorage else { return false }
        let text = string as NSString
        let selection = selectedRange()
        guard selection.length == 0 else { return false }

        let caret = min(max(0, selection.location), text.length)
        let lineRange = text.lineRange(for: NSRange(location: caret, length: 0))
        let prefixLength = caret - lineRange.location
        guard prefixLength > 0 else { return false }
        let prefix = text.substring(with: NSRange(location: lineRange.location, length: prefixLength))
        guard prefix.allSatisfy({ $0 == " " || $0 == "\t" }) else { return false }

        var scan = caret
        var sawNewline = false
        while let unit = utf16Unit(at: scan, in: text) {
            guard unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D else { break }
            if unit == 0x0A || unit == 0x0D { sawNewline = true }
            scan += 1
        }
        let hasBraceAhead = utf16Unit(at: scan, in: text) == 0x7D

        if hasBraceAhead, sawNewline {
            let replaceRange = NSRange(location: lineRange.location, length: scan - lineRange.location + 1)
            guard shouldChangeText(in: replaceRange, replacementString: "}") else { return true }
            storage.replaceCharacters(in: replaceRange, with: "}")
            didChangeText()
            setSelectedRange(NSRange(location: lineRange.location + 1, length: 0))
            return true
        }

        if hasBraceAhead {
            setSelectedRange(NSRange(location: scan + 1, length: 0))
            return true
        }

        if prefixLength >= Self.indentUnit.utf16.count {
            let dedented = String(prefix.dropLast(Self.indentUnit.count))
            let replaceRange = NSRange(location: lineRange.location, length: prefixLength)
            guard shouldChangeText(in: replaceRange, replacementString: dedented) else { return true }
            storage.replaceCharacters(in: replaceRange, with: dedented)
            didChangeText()
            setSelectedRange(NSRange(location: lineRange.location + dedented.utf16.count, length: 0))
        }
        return false
    }

    func deleteEmptyPair() -> Bool {
        guard let storage = textStorage else { return false }
        let text = string as NSString
        let selection = selectedRange()
        guard selection.length == 0, selection.location > 0 else { return false }

        let caret = selection.location
        guard let opener = utf16Unit(at: caret - 1, in: text),
              let closer = utf16Unit(at: caret, in: text),
              Self.pairClosers[opener] == closer else { return false }

        let range = NSRange(location: caret - 1, length: 2)
        guard shouldChangeText(in: range, replacementString: "") else { return true }
        storage.replaceCharacters(in: range, with: "")
        didChangeText()
        setSelectedRange(NSRange(location: caret - 1, length: 0))
        return true
    }

    // MARK: - Line helpers

    private static let pairClosers: [UInt16: UInt16] = [
        0x28: 0x29,  // ( )
        0x5B: 0x5D,  // [ ]
        0x7B: 0x7D,  // { }
        0x22: 0x22,  // " "
        0x27: 0x27   // ' '
    ]

    private static func closingCharacter(for character: Character) -> Character {
        switch character {
        case "(": return ")"
        case "[": return "]"
        default: return "}"
        }
    }

    private static func utf16Unit(of character: Character) -> UInt16? {
        character.utf16.first
    }

    private static func dedenting(_ line: String) -> String {
        if line.hasPrefix(indentUnit) { return String(line.dropFirst(indentUnit.count)) }
        if line.hasPrefix("\t") { return String(line.dropFirst(1)) }
        if line.hasPrefix(" ") { return String(line.dropFirst(1)) }
        return line
    }

    private static func isBlank(_ line: String) -> Bool {
        line.allSatisfy { $0 == " " || $0 == "\t" }
    }

    private static func isCommented(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("//")
    }

    private static func commenting(_ line: String) -> String {
        guard !isBlank(line) else { return line }
        let indent = String(line.prefix { $0 == " " || $0 == "\t" })
        return indent + "// " + line.dropFirst(indent.count)
    }

    private static func uncommenting(_ line: String) -> String {
        let indent = String(line.prefix { $0 == " " || $0 == "\t" })
        var rest = line.dropFirst(indent.count)
        guard rest.hasPrefix("//") else { return line }
        rest = rest.dropFirst(2)
        if rest.hasPrefix(" ") { rest = rest.dropFirst(1) }
        return indent + rest
    }

    private func utf16Unit(at index: Int, in text: NSString) -> UInt16? {
        guard index >= 0, index < text.length else { return nil }
        return text.character(at: index)
    }

    private func leadingWhitespaceLength(of text: NSString, in lineRange: NSRange) -> Int {
        var length = 0
        while length < lineRange.length {
            let unit = text.character(at: lineRange.location + length)
            guard unit == 0x20 || unit == 0x09 else { break }
            length += 1
        }
        return length
    }

    private func trimTrailingWhitespace(_ text: String) -> String {
        String(text.reversed().drop { $0 == " " || $0 == "\t" }.reversed())
    }
}
