//
//  SerialMonitorEvent.swift
//  Sketchpad2
//

import Foundation

/// One thing an open serial monitor reports back to the app.
///
/// The monitor is a stream in both directions, so what the board sends arrives here while the app
/// keeps sending what the user types and what the port should be configured as.
nonisolated enum SerialMonitorEvent: Sendable {
    /// Bytes the board sent. Chunks aren't aligned to lines, so the reader has to join them up.
    case received(Data)
    /// The daemon opened the port and reported the settings it applied, the baud rate included.
    case connected(baudRate: String?)
    /// The daemon reported a problem, or the RPC ended because of one.
    case failed(String)
}
