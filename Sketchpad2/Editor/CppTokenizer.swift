import Foundation

/// Lexical classification for a slice of Arduino/C++ source.
enum TokenKind: Sendable, Hashable {
    case keyword
    case arduinoFunction
    case arduinoConstant
    case arduinoType
    case string
    case character
    case number
    case comment
    case preprocessor
    case identifier
    case `operator`
    case punctuation
}

/// A classified slice of source, expressed in UTF-16 offsets so it can be applied
/// straight to `NSTextStorage`.
struct Token: Sendable, Hashable {
    let kind: TokenKind
    let range: NSRange
}

/// Single-pass scanner producing syntax tokens for Arduino sketches.
///
/// Block comments carry across lines. String and character literals stay colored
/// until their closing quote, but recover at the end of a line so an unterminated
/// literal typed mid-edit does not swallow the rest of the file.
enum CppTokenizer {

    static func tokenize(_ source: String) -> [Token] {
        let units = Array(source.utf16)
        var tokens: [Token] = []
        tokens.reserveCapacity(units.count / 4 + 8)

        var index = 0
        var isAtLineStart = true

        while index < units.count {
            let unit = units[index]

            if unit == newline || unit == carriageReturn {
                index += 1
                isAtLineStart = true
                continue
            }

            if unit == space || unit == tab || unit == verticalTab || unit == formFeed {
                index += 1
                continue
            }

            let start = index

            if isAtLineStart, unit == hash {
                index = endOfLine(units, from: index)
                tokens.append(Token(kind: .preprocessor, range: tokenRange(start, index)))
                isAtLineStart = false
                continue
            }

            isAtLineStart = false

            if unit == slash, unitOrNil(at: index + 1, in: units) == slash {
                index = endOfLine(units, from: index)
                tokens.append(Token(kind: .comment, range: tokenRange(start, index)))
                continue
            }

            if unit == slash, unitOrNil(at: index + 1, in: units) == star {
                index = endOfBlockComment(units, from: index)
                tokens.append(Token(kind: .comment, range: tokenRange(start, index)))
                continue
            }

            if unit == doubleQuote {
                index = endOfQuoted(units, from: index, quote: doubleQuote)
                tokens.append(Token(kind: .string, range: tokenRange(start, index)))
                continue
            }

            if unit == singleQuote {
                index = endOfQuoted(units, from: index, quote: singleQuote)
                tokens.append(Token(kind: .character, range: tokenRange(start, index)))
                continue
            }

            if isDigit(unit) || (unit == dot && isDigit(unitOrNil(at: index + 1, in: units))) {
                index = endOfNumber(units, from: index)
                tokens.append(Token(kind: .number, range: tokenRange(start, index)))
                continue
            }

            if isIdentifierStart(unit) {
                index = endOfIdentifier(units, from: index)
                let word = String(decoding: units[start..<index], as: UTF16.self)
                tokens.append(Token(kind: ArduinoSymbols.kind(forIdentifier: word), range: tokenRange(start, index)))
                continue
            }

            if isOperatorUnit(unit) {
                while index < units.count, isOperatorUnit(units[index]) {
                    index += 1
                }
                tokens.append(Token(kind: .operator, range: tokenRange(start, index)))
                continue
            }

            index += 1
            tokens.append(Token(kind: .punctuation, range: tokenRange(start, index)))
        }

        return tokens
    }

    // MARK: - Scanning helpers

    private static func tokenRange(_ start: Int, _ end: Int) -> NSRange {
        NSRange(location: start, length: end - start)
    }

    private static func unitOrNil(at index: Int, in units: [UInt16]) -> UInt16? {
        index >= 0 && index < units.count ? units[index] : nil
    }

    private static func endOfLine(_ units: [UInt16], from index: Int) -> Int {
        var index = index
        while index < units.count, units[index] != newline, units[index] != carriageReturn {
            index += 1
        }
        return index
    }

    private static func endOfBlockComment(_ units: [UInt16], from index: Int) -> Int {
        var index = index + 2
        while index + 1 < units.count {
            if units[index] == star, units[index + 1] == slash {
                return index + 2
            }
            index += 1
        }
        return units.count
    }

    private static func endOfQuoted(_ units: [UInt16], from index: Int, quote: UInt16) -> Int {
        var index = index + 1
        while index < units.count {
            let unit = units[index]
            if unit == backslash {
                index += 2
                continue
            }
            if unit == quote {
                return index + 1
            }
            if unit == newline || unit == carriageReturn {
                return index
            }
            index += 1
        }
        return units.count
    }

    private static func endOfIdentifier(_ units: [UInt16], from index: Int) -> Int {
        var index = index
        while index < units.count, isIdentifierContinuation(units[index]) {
            index += 1
        }
        return index
    }

    private static func endOfNumber(_ units: [UInt16], from index: Int) -> Int {
        var index = index
        let next = unitOrNil(at: index + 1, in: units)

        if units[index] == zero,
           next == xLower || next == xUpper || next == bLower || next == bUpper {
            index += 2
            while index < units.count, isHexDigit(units[index]) || units[index] == underscore {
                index += 1
            }
        } else {
            while index < units.count, isDigit(units[index]) || units[index] == underscore {
                index += 1
            }
            if index < units.count, units[index] == dot, isDigit(unitOrNil(at: index + 1, in: units)) {
                index += 1
                while index < units.count, isDigit(units[index]) || units[index] == underscore {
                    index += 1
                }
            }
            if index < units.count, units[index] == eLower || units[index] == eUpper {
                var exponent = index + 1
                let sign = unitOrNil(at: exponent, in: units)
                if sign == plus || sign == minus {
                    exponent += 1
                }
                if isDigit(unitOrNil(at: exponent, in: units)) {
                    index = exponent
                    while index < units.count, isDigit(units[index]) {
                        index += 1
                    }
                }
            }
        }

        while index < units.count, isNumericSuffix(units[index]) {
            index += 1
        }
        return index
    }

    // MARK: - Character classes

    private static let newline: UInt16 = 0x0A
    private static let carriageReturn: UInt16 = 0x0D
    private static let space: UInt16 = 0x20
    private static let tab: UInt16 = 0x09
    private static let verticalTab: UInt16 = 0x0B
    private static let formFeed: UInt16 = 0x0C
    private static let hash: UInt16 = 0x23
    private static let slash: UInt16 = 0x2F
    private static let star: UInt16 = 0x2A
    private static let backslash: UInt16 = 0x5C
    private static let doubleQuote: UInt16 = 0x22
    private static let singleQuote: UInt16 = 0x27
    private static let dot: UInt16 = 0x2E
    private static let underscore: UInt16 = 0x5F
    private static let zero: UInt16 = 0x30
    private static let plus: UInt16 = 0x2B
    private static let minus: UInt16 = 0x2D
    private static let xLower: UInt16 = 0x78
    private static let xUpper: UInt16 = 0x58
    private static let bLower: UInt16 = 0x62
    private static let bUpper: UInt16 = 0x42
    private static let eLower: UInt16 = 0x65
    private static let eUpper: UInt16 = 0x45

    private static func isDigit(_ unit: UInt16?) -> Bool {
        guard let unit else { return false }
        return unit >= 0x30 && unit <= 0x39
    }

    private static func isHexDigit(_ unit: UInt16) -> Bool {
        if unit >= 0x30, unit <= 0x39 { return true }
        if unit >= 0x61, unit <= 0x66 { return true }
        if unit >= 0x41, unit <= 0x46 { return true }
        return false
    }

    private static func isNumericSuffix(_ unit: UInt16) -> Bool {
        switch unit {
        case 0x75, 0x55, 0x6C, 0x4C, 0x66, 0x46:
            return true
        default:
            return false
        }
    }

    private static func isIdentifierStart(_ unit: UInt16) -> Bool {
        if unit >= 0x41, unit <= 0x5A { return true }
        if unit >= 0x61, unit <= 0x7A { return true }
        return unit == underscore || unit == 0x24
    }

    private static func isIdentifierContinuation(_ unit: UInt16) -> Bool {
        isIdentifierStart(unit) || isDigit(unit)
    }

    private static func isOperatorUnit(_ unit: UInt16) -> Bool {
        switch unit {
        case 0x2B, 0x2D, 0x2A, 0x2F, 0x25, 0x3D, 0x3C, 0x3E, 0x21,
             0x26, 0x7C, 0x5E, 0x7E, 0x3F, 0x2E, 0x3A:
            return true
        default:
            return false
        }
    }
}
