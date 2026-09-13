//
//  SerialMonitorSession.swift
//  Sketchpad2
//

import Foundation
import os

/// A monitor connection that's open on the daemon: what the app writes to the port, and what the
/// board sends back.
///
/// The daemon's monitor is a bidirectional gRPC stream whose requests carry the port's
/// configuration and the bytes to write, and whose responses carry the bytes the board sent. This
/// type splits that stream into two doors — `send` and `apply` going out, `events` coming back —
/// so nothing else in the app has to hold on to a gRPC writer.
nonisolated final class SerialMonitorSession: @unchecked Sendable {
    /// What the monitor reports back: the byte stream, the applied settings, and any failure.
    let events: AsyncStream<SerialMonitorEvent>

    /// Requests queued for the daemon, in the order they were made.
    private let requests: AsyncStream<Cc_Arduino_Cli_Commands_V1_MonitorRequest>.Continuation

    /// The RPC itself, held so the connection stays open for as long as the session is in use.
    private let rpc: Task<Void, Never>

    private let logger = Logger(subsystem: "com.perr.Sketchpad2", category: "SerialMonitor")

    init(
        requests: AsyncStream<Cc_Arduino_Cli_Commands_V1_MonitorRequest>.Continuation,
        events: AsyncStream<SerialMonitorEvent>,
        rpc: Task<Void, Never>
    ) {
        self.requests = requests
        self.events = events
        self.rpc = rpc
    }

    /// Writes bytes to the board, as though they had been typed straight into the port.
    func send(_ data: Data) {
        requests.yield(Self.request { $0.txData = data })
    }

    /// Reconfigures the port while it's open, which is how the baud rate changes mid-session.
    func apply(settings: [String: String]) {
        requests.yield(Self.request { request in
            request.updatedConfiguration = Cc_Arduino_Cli_Commands_V1_MonitorPortConfiguration(
                settings: settings
            )
        })
    }

    /// Asks the daemon to let go of the port, which ends the stream once it has.
    func close() {
        logger.log("Closing the serial monitor")
        requests.yield(Self.request { $0.close = true })
        requests.finish()
    }

    /// Builds a request around the one field it's setting, since the message is a choice of one.
    static func request(
        _ build: (inout Cc_Arduino_Cli_Commands_V1_MonitorRequest) -> Void
    ) -> Cc_Arduino_Cli_Commands_V1_MonitorRequest {
        var request = Cc_Arduino_Cli_Commands_V1_MonitorRequest()
        build(&request)
        return request
    }
}
