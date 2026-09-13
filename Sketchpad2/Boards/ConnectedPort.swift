//
//  ConnectedPort.swift
//  Sketchpad2
//

import Foundation

/// A port the daemon detects, shaped for the editor's port menu.
nonisolated struct ConnectedPort: Identifiable, Equatable, Sendable {
    /// The port address, e.g. `/dev/cu.usbmodem1101`, which identifies the port.
    let id: String
    /// A human-friendly description of the port's protocol, e.g. `Serial Port (USB)`.
    let protocolLabel: String
    /// The port exactly as the daemon reported it, so an upload can name it back without guessing.
    let daemonPort: Cc_Arduino_Cli_Commands_V1_Port
    /// The boards the daemon matched to the port, most likely first. Empty when the daemon can't
    /// tell what's attached, which is what the board and port dialog is there to fix.
    let boards: [KnownBoard]

    /// Names of the boards the daemon matched to the port.
    var boardNames: [String] { boards.map(\.name) }

    /// The board the daemon is most confident about, or `nil` when it recognized nothing.
    var board: KnownBoard? { boards.first }

    /// An `Arduino Uno (/dev/cu.usbmodem1101)` style line, dropping whatever the daemon leaves out.
    var displayName: String {
        guard let board = boards.first else { return id }
        return "\(board.name) (\(id))"
    }

    init(_ detected: Cc_Arduino_Cli_Commands_V1_DetectedPort) {
        let port = detected.port
        self.daemonPort = port
        self.id = port.address.isEmpty ? port.label : port.address
        self.protocolLabel = port.protocolLabel.isEmpty ? port.protocol : port.protocolLabel
        self.boards = detected.matchingBoards
            .map(KnownBoard.init)
            .filter { !$0.name.isEmpty }
    }
}
