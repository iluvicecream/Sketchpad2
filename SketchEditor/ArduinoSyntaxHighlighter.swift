//
//  ArduinoSyntaxHighlighter.swift
//  Sketchpad
//

import AppKit

/// The kinds of tokens the Arduino/C++ lexer produces.
enum ArduinoTokenKind: Hashable {
    case lineComment
    case blockComment
    case string
    case character
    case preprocessor
    case number
    case keyword
    case type
    case builtIn
    case call
}

/// A lexed source range and the kind of token it represents.
struct ArduinoToken: Equatable {
    let kind: ArduinoTokenKind
    let range: NSRange
}

/// A hand-written Arduino/C++ lexer plus the editor's syntax color palette.
///
/// Highlighting is applied as *temporary* layout manager attributes, so the text
/// storage, the undo stack, and the pasteboard are never modified by it.
final class ArduinoSyntaxHighlighter {

    private let colors: [ArduinoTokenKind: NSColor]

    init() {
        colors = [
            .lineComment: Self.dynamicColor(light: 0x536579, dark: 0x7F8C98),
            .blockComment: Self.dynamicColor(light: 0x536579, dark: 0x7F8C98),
            .string: Self.dynamicColor(light: 0xC41A16, dark: 0xFC6A5D),
            .character: Self.dynamicColor(light: 0xC41A16, dark: 0xFC6A5D),
            .preprocessor: Self.dynamicColor(light: 0x78492A, dark: 0xFFA14F),
            .number: Self.dynamicColor(light: 0x1C00CF, dark: 0xD0BF69),
            .keyword: Self.dynamicColor(light: 0x9B2393, dark: 0xFF7AB2),
            .type: Self.dynamicColor(light: 0x0B4F79, dark: 0x6BDFFF),
            .builtIn: Self.dynamicColor(light: 0x2F7F6F, dark: 0x74D6C0),
            .call: Self.dynamicColor(light: 0x2F6D9E, dark: 0x6FB4FF)
        ]
    }

    // MARK: - Attributes

    /// Base attributes for uncolored text. Used for typing attributes and for the
    /// attributes that live in the text storage.
    func baseAttributes(font: NSFont) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.tabStops = []
        paragraphStyle.defaultTabInterval = 4 * (" " as NSString).size(withAttributes: [.font: font]).width
        return [
            .font: font,
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraphStyle
        ]
    }

    /// Clears and re-applies temporary syntax highlighting for `text`.
    func apply(to layoutManager: NSLayoutManager, in text: String) {
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)

        for token in tokenize(text) {
            guard let color = colors[token.kind] else { continue }
            layoutManager.addTemporaryAttributes([.foregroundColor: color], forCharacterRange: token.range)
        }
    }

    // MARK: - Lexing

    /// Scans `source` and returns the tokens in source order.
    func tokenize(_ source: String) -> [ArduinoToken] {
        let text = source as NSString
        let length = text.length
        var tokens: [ArduinoToken] = []
        var index = 0
        var isAtLineStart = true

        while index < length {
            let character = text.character(at: index)

            if character == Self.lineFeed {
                isAtLineStart = true
                index += 1
                continue
            }

            if Self.isWhitespace(character) {
                index += 1
                continue
            }

            if character == Self.slash, index + 1 < length {
                let next = text.character(at: index + 1)

                if next == Self.slash {
                    let start = index
                    while index < length, text.character(at: index) != Self.lineFeed {
                        index += 1
                    }
                    tokens.append(ArduinoToken(kind: .lineComment, range: NSRange(location: start, length: index - start)))
                    isAtLineStart = false
                    continue
                }

                if next == Self.asterisk {
                    let start = index
                    index += 2
                    while index + 1 < length,
                          !(text.character(at: index) == Self.asterisk && text.character(at: index + 1) == Self.slash) {
                        index += 1
                    }
                    index = min(index + 2, length)
                    tokens.append(ArduinoToken(kind: .blockComment, range: NSRange(location: start, length: index - start)))
                    isAtLineStart = false
                    continue
                }
            }

            if character == Self.numberSign, isAtLineStart {
                let start = index
                while index < length {
                    if text.character(at: index) == Self.lineFeed {
                        // A trailing backslash continues the directive on the next line.
                        var backslashes = 0
                        var scan = index - 1
                        while scan >= start, text.character(at: scan) == Self.backslash {
                            backslashes += 1
                            scan -= 1
                        }
                        if backslashes % 2 == 1 {
                            index += 1
                            continue
                        }
                        break
                    }
                    index += 1
                }
                tokens.append(ArduinoToken(kind: .preprocessor, range: NSRange(location: start, length: index - start)))
                isAtLineStart = true
                continue
            }

            if character == Self.doubleQuote || character == Self.singleQuote {
                let isString = character == Self.doubleQuote
                let start = index
                index += 1
                while index < length {
                    let current = text.character(at: index)
                    if current == Self.backslash {
                        index += 2
                        continue
                    }
                    index += 1
                    if current == character || current == Self.lineFeed {
                        break
                    }
                }
                index = min(index, length)
                tokens.append(ArduinoToken(kind: isString ? .string : .character, range: NSRange(location: start, length: index - start)))
                isAtLineStart = false
                continue
            }

            if Self.isDigit(character) {
                let start = index
                index = Self.scanNumber(in: text, from: index)
                tokens.append(ArduinoToken(kind: .number, range: NSRange(location: start, length: index - start)))
                isAtLineStart = false
                continue
            }

            if Self.isIdentifierStart(character) {
                let start = index
                while index < length, Self.isIdentifierBody(text.character(at: index)) {
                    index += 1
                }
                let word = text.substring(with: NSRange(location: start, length: index - start))
                if let kind = Self.kind(of: word) {
                    tokens.append(ArduinoToken(kind: kind, range: NSRange(location: start, length: index - start)))
                } else if Self.isCall(in: text, from: index) {
                    tokens.append(ArduinoToken(kind: .call, range: NSRange(location: start, length: index - start)))
                }
                isAtLineStart = false
                continue
            }

            isAtLineStart = false
            index += 1
        }

        return tokens
    }

    private static func kind(of word: String) -> ArduinoTokenKind? {
        if keywords.contains(word) { return .keyword }
        if types.contains(word) { return .type }
        if builtIns.contains(word) { return .builtIn }
        return nil
    }

    /// True when the identifier ending at `index` is followed by an opening parenthesis.
    private static func isCall(in text: NSString, from index: Int) -> Bool {
        var cursor = index
        while cursor < text.length, isWhitespace(text.character(at: cursor)) {
            cursor += 1
        }
        return cursor < text.length && text.character(at: cursor) == openParen
    }

    private static func scanNumber(in text: NSString, from start: Int) -> Int {
        var index = start
        let first = text.character(at: index)

        if first == zero, index + 1 < text.length, hexPrefixes.contains(text.character(at: index + 1)) {
            index += 2
            while index < text.length, isHexDigit(text.character(at: index)) || text.character(at: index) == underscore {
                index += 1
            }
        } else if first == zero, index + 1 < text.length, binaryPrefixes.contains(text.character(at: index + 1)) {
            index += 2
            while index < text.length,
                  text.character(at: index) == zero || text.character(at: index) == one || text.character(at: index) == underscore {
                index += 1
            }
        } else {
            while index < text.length, isDigit(text.character(at: index)) || text.character(at: index) == underscore {
                index += 1
            }
            if index + 1 < text.length, text.character(at: index) == period, isDigit(text.character(at: index + 1)) {
                index += 1
                while index < text.length, isDigit(text.character(at: index)) || text.character(at: index) == underscore {
                    index += 1
                }
            }
            if index < text.length, exponentCharacters.contains(text.character(at: index)) {
                var lookahead = index + 1
                if lookahead < text.length, text.character(at: lookahead) == plus || text.character(at: lookahead) == minus {
                    lookahead += 1
                }
                if lookahead < text.length, isDigit(text.character(at: lookahead)) {
                    index = lookahead
                    while index < text.length, isDigit(text.character(at: index)) {
                        index += 1
                    }
                }
            }
        }

        while index < text.length, numberSuffixes.contains(text.character(at: index)) {
            index += 1
        }

        return index
    }

    // MARK: - Character classification

    private static func isDigit(_ character: unichar) -> Bool {
        character >= zero && character <= nine
    }

    private static func isHexDigit(_ character: unichar) -> Bool {
        isDigit(character)
            || (character >= uppercaseA && character <= uppercaseF)
            || (character >= lowercaseA && character <= lowercaseF)
    }

    private static func isIdentifierStart(_ character: unichar) -> Bool {
        (character >= uppercaseA && character <= uppercaseZ)
            || (character >= lowercaseA && character <= lowercaseZ)
            || character == underscore
            || character >= nonASCII
    }

    private static func isIdentifierBody(_ character: unichar) -> Bool {
        isIdentifierStart(character) || isDigit(character)
    }

    private static func isWhitespace(_ character: unichar) -> Bool {
        character == 0x20 || character == 0x09 || character == 0x0B
            || character == 0x0C || character == 0x0D || character == lineFeed
    }

    // MARK: - Character codes

    private static let lineFeed: unichar = 0x0A
    private static let slash: unichar = 0x2F
    private static let asterisk: unichar = 0x2A
    private static let numberSign: unichar = 0x23
    private static let doubleQuote: unichar = 0x22
    private static let singleQuote: unichar = 0x27
    private static let backslash: unichar = 0x5C
    private static let underscore: unichar = 0x5F
    private static let period: unichar = 0x2E
    private static let plus: unichar = 0x2B
    private static let minus: unichar = 0x2D
    private static let openParen: unichar = 0x28
    private static let zero: unichar = 0x30
    private static let one: unichar = 0x31
    private static let nine: unichar = 0x39
    private static let uppercaseA: unichar = 0x41
    private static let uppercaseF: unichar = 0x46
    private static let uppercaseZ: unichar = 0x5A
    private static let lowercaseA: unichar = 0x61
    private static let lowercaseF: unichar = 0x66
    private static let lowercaseZ: unichar = 0x7A
    private static let nonASCII: unichar = 0x80

    private static let hexPrefixes: Set<unichar> = [0x78, 0x58]         // x X
    private static let binaryPrefixes: Set<unichar> = [0x62, 0x42]      // b B
    private static let exponentCharacters: Set<unichar> = [0x65, 0x45]  // e E
    private static let numberSuffixes: Set<unichar> = [0x75, 0x55, 0x6C, 0x4C, 0x66, 0x46] // u U l L f F

    // MARK: - Words

    private static let keywords: Set<String> = [
        "alignas", "alignof", "asm", "auto", "break", "case", "catch", "class",
        "const", "constexpr", "continue", "decltype", "default", "delete", "do",
        "else", "enum", "explicit", "export", "extern", "false", "final", "for",
        "friend", "goto", "if", "inline", "mutable", "namespace", "new", "noexcept",
        "nullptr", "operator", "override", "private", "protected", "public",
        "register", "return", "sizeof", "static", "static_assert", "struct",
        "switch", "template", "this", "throw", "true", "try", "typedef", "typeid",
        "typename", "union", "using", "virtual", "volatile", "while"
    ]

    private static let types: Set<String> = [
        "bool", "byte", "char", "char16_t", "char32_t", "double", "float", "int",
        "int8_t", "int16_t", "int32_t", "int64_t", "long", "short", "signed",
        "size_t", "uint8_t", "uint16_t", "uint32_t", "uint64_t", "unsigned",
        "void", "wchar_t"
    ]

    private static let builtIns: Set<String> = Set([
        "HIGH", "LOW", "INPUT", "INPUT_PULLUP", "OUTPUT", "OUTPUT_OPEN_DRAIN",
        "LED_BUILTIN", "String", "Serial", "Serial1", "Wire", "SPI",
        "setup", "loop",
        "pinMode", "digitalWrite", "digitalRead", "analogRead", "analogWrite",
        "analogReference", "delay", "delayMicroseconds", "millis", "micros",
        "map", "constrain", "random", "randomSeed", "min", "max", "abs", "pow",
        "sqrt", "sin", "cos", "tan", "tone", "noTone", "pulseIn", "shiftOut",
        "shiftIn", "attachInterrupt", "detachInterrupt", "interrupts",
        "noInterrupts", "bitRead", "bitWrite", "bitSet", "bitClear", "lowByte",
        "highByte", "isDigit", "isAlpha", "isSpace", "toUpperCase", "toLowerCase"
    ] + (0...15).map { "A\($0)" })

    // MARK: - Colors

    private static func dynamicColor(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(rgb: isDark ? dark : light)
        }
    }
}

private extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
