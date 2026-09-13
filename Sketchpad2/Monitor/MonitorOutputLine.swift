//
//  MonitorOutputLine.swift
//  Sketchpad2
//

import Foundation

/// One line of the serial monitor's output.
///
/// The last line is special: it's the one still arriving, so it grows as bytes come in and only
/// gains a new line after it when the board sends a line ending.
nonisolated struct MonitorOutputLine: Identifiable, Equatable, Sendable {
    /// Where the line sits in the monitor's list, which is also what identity means here.
    let id: Int
    /// What the line reads, which grows while the board is still writing it.
    var text: String
}
