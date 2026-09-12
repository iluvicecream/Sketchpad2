import AppKit

/// Token colors for the editor. Every color is resolved per appearance so the
/// editor recolors immediately when the system switches between light and dark.
struct SyntaxTheme: Sendable {
    private struct Components: Sendable {
        let red: Double
        let green: Double
        let blue: Double
    }

    static let standard = SyntaxTheme()

    func color(for kind: TokenKind) -> NSColor {
        switch kind {
        case .keyword:
            Self.dynamic(light: Components(red: 0.61, green: 0.14, blue: 0.58),
                         dark: Components(red: 1.00, green: 0.48, blue: 0.70))
        case .arduinoFunction:
            Self.dynamic(light: Components(red: 0.04, green: 0.31, blue: 0.47),
                         dark: Components(red: 0.42, green: 0.87, blue: 1.00))
        case .arduinoConstant:
            Self.dynamic(light: Components(red: 0.55, green: 0.20, blue: 0.63),
                         dark: Components(red: 0.85, green: 0.65, blue: 1.00))
        case .arduinoType:
            Self.dynamic(light: Components(red: 0.00, green: 0.44, blue: 0.44),
                         dark: Components(red: 0.51, green: 0.90, blue: 0.86))
        case .string, .character:
            Self.dynamic(light: Components(red: 0.77, green: 0.10, blue: 0.09),
                         dark: Components(red: 1.00, green: 0.51, blue: 0.44))
        case .number:
            Self.dynamic(light: Components(red: 0.11, green: 0.00, blue: 0.81),
                         dark: Components(red: 0.85, green: 0.79, blue: 0.49))
        case .comment:
            Self.dynamic(light: Components(red: 0.36, green: 0.45, blue: 0.36),
                         dark: Components(red: 0.53, green: 0.63, blue: 0.70))
        case .preprocessor:
            Self.dynamic(light: Components(red: 0.39, green: 0.22, blue: 0.13),
                         dark: Components(red: 1.00, green: 0.63, blue: 0.31))
        case .identifier:
            NSColor.textColor
        case .operator, .punctuation:
            NSColor.secondaryLabelColor
        }
    }

    private static func dynamic(light: Components, dark: Components) -> NSColor {
        NSColor(name: nil) { appearance in
            let components = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: components.red, green: components.green, blue: components.blue, alpha: 1)
        }
    }
}

/// Applies token colors to a text storage without registering undo steps.
@MainActor
enum SyntaxHighlighter {
    static func highlight(
        _ storage: NSTextStorage,
        font: NSFont,
        defaultColor: NSColor,
        theme: SyntaxTheme = .standard
    ) {
        let source = storage.string
        let fullRange = NSRange(location: 0, length: storage.length)

        storage.beginEditing()
        storage.setAttributes([.font: font, .foregroundColor: defaultColor], range: fullRange)
        for token in CppTokenizer.tokenize(source) {
            let clamped = NSIntersectionRange(token.range, fullRange)
            guard clamped.length > 0 else { continue }
            storage.addAttribute(.foregroundColor, value: theme.color(for: token.kind), range: clamped)
        }
        storage.endEditing()
    }
}
