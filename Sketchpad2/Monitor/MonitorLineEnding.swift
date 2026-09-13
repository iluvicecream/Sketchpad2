//
//  MonitorLineEnding.swift
//  Sketchpad2
//

import Foundation

/// What the serial monitor appends to a line before sending it to the board.
///
/// A board reads a line only once it sees the ending its sketch looks for, so the monitor offers
/// the same four choices as the Arduino IDE.
nonisolated enum MonitorLineEnding: String, CaseIterable, Identifiable, Sendable {
    case none
    case newline
    case carriageReturn
    case both

    var id: String { rawValue }

    /// The menu title, spelled the way the Arduino IDE spells it.
    var title: String {
        switch self {
        case .none: "No line ending"
        case .newline: "Newline"
        case .carriageReturn: "Carriage return"
        case .both: "Both NL & CR"
        }
    }

    /// The characters appended to what's being sent.
    var terminator: String {
        switch self {
        case .none: ""
        case .newline: "\n"
        case .carriageReturn: "\r"
        case .both: "\r\n"
        }
    }
}
