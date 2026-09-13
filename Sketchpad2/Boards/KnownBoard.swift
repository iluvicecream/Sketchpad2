//
//  KnownBoard.swift
//  Sketchpad2
//

import Foundation

/// A board the daemon can name, either one an installed platform provides or one it matched to a
/// connected port.
///
/// The board and port dialog offers these when the daemon can't tell what's on a port, so the user
/// can name the board themselves the way the Arduino IDE does.
nonisolated struct KnownBoard: Identifiable, Equatable, Sendable {
    /// The name to show, e.g. `Arduino Uno`.
    let name: String
    /// The fully qualified board name used to compile and upload, e.g. `arduino:avr:uno`.
    let fqbn: String
    /// The name of the platform the board belongs to, e.g. `Arduino AVR Boards`.
    let platformName: String

    var id: String { fqbn.isEmpty ? name : fqbn }

    init(name: String, fqbn: String, platformName: String) {
        self.name = name
        self.fqbn = fqbn
        self.platformName = platformName
    }

    init(_ board: Cc_Arduino_Cli_Commands_V1_BoardListItem) {
        let release = board.platform.release.name
        self.init(
            name: board.name,
            fqbn: board.fqbn,
            platformName: release.isEmpty ? board.platform.metadata.id : release
        )
    }
}
