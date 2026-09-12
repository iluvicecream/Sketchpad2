import Foundation

/// Symbol tables used to tell Arduino API surface apart from ordinary identifiers.
enum ArduinoSymbols {

    /// Arduino core functions.
    static let functions: Set<String> = [
        "setup", "loop", "yield",
        "pinMode", "digitalWrite", "digitalRead",
        "analogRead", "analogWrite", "analogReference",
        "analogReadResolution", "analogWriteResolution",
        "delay", "delayMicroseconds", "millis", "micros",
        "tone", "noTone", "pulseIn", "pulseInLong",
        "shiftIn", "shiftOut",
        "attachInterrupt", "detachInterrupt", "digitalPinToInterrupt",
        "map", "constrain", "min", "max", "abs", "pow", "sqrt", "sq",
        "sin", "cos", "tan", "random", "randomSeed",
        "lowByte", "highByte", "bitRead", "bitWrite", "bitSet", "bitClear", "bit",
        "interrupts", "noInterrupts",
        "attachInterruptArg", "ledcSetup", "ledcAttachPin", "ledcWrite",
        "dacWrite", "touchRead", "espDeepSleep", "espRestart"
    ]

    /// Arduino constants and the global objects the core predefines.
    static let constants: Set<String> = [
        "HIGH", "LOW", "INPUT", "OUTPUT", "INPUT_PULLUP", "INPUT_PULLDOWN",
        "LED_BUILTIN", "CHANGE", "RISING", "FALLING", "ON", "OFF",
        "MSBFIRST", "LSBFIRST", "PI", "TWO_PI", "HALF_PI", "DEG_TO_RAD", "RAD_TO_DEG",
        "Serial", "Serial1", "Serial2", "Serial3", "Serial4",
        "Wire", "Wire1", "SPI", "SPI1", "EEPROM",
        "A0", "A1", "A2", "A3", "A4", "A5", "A6", "A7",
        "A8", "A9", "A10", "A11", "A12", "A13", "A14", "A15",
        "LED_RED", "LED_GREEN", "LED_BLUE"
    ]

    /// Arduino-specific types.
    static let types: Set<String> = [
        "byte", "boolean", "word", "String", "size_t", "ssize_t",
        "uint8_t", "uint16_t", "uint32_t", "uint64_t",
        "int8_t", "int16_t", "int32_t", "int64_t",
        "u_int8_t", "u_int16_t", "u_int32_t"
    ]

    /// C++ language keywords.
    static let keywords: Set<String> = [
        "alignas", "alignof", "and", "and_eq", "asm", "auto",
        "bitand", "bitor", "bool", "break",
        "case", "catch", "char", "char8_t", "char16_t", "char32_t", "class", "compl",
        "concept", "const", "consteval", "constexpr", "constinit", "const_cast", "continue",
        "co_await", "co_return", "co_yield",
        "decltype", "default", "delete", "do", "double", "dynamic_cast",
        "else", "enum", "explicit", "export", "extern",
        "false", "float", "for", "friend",
        "goto", "if", "inline", "int",
        "long", "mutable", "namespace", "new", "noexcept", "not", "not_eq", "nullptr",
        "operator", "or", "or_eq", "private", "protected", "public",
        "register", "reinterpret_cast", "requires", "return",
        "short", "signed", "sizeof", "static", "static_assert", "static_cast", "struct", "switch",
        "template", "this", "thread_local", "throw", "true", "try", "typedef", "typeid",
        "typename", "union", "unsigned", "using",
        "virtual", "void", "volatile", "wchar_t", "while", "xor", "xor_eq"
    ]

    /// Classifies an identifier into a token kind, falling back to `.identifier`.
    static func kind(forIdentifier identifier: String) -> TokenKind {
        if keywords.contains(identifier) { return .keyword }
        if functions.contains(identifier) { return .arduinoFunction }
        if constants.contains(identifier) { return .arduinoConstant }
        if types.contains(identifier) { return .arduinoType }
        return .identifier
    }
}
