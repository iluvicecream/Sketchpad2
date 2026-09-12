//
//  ArduinoCoreService.swift
//  Sketchpad2
//

import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import os

/// A single long-lived gRPC connection to the arduino-cli daemon, shared by every RPC.
nonisolated final class ArduinoCoreService: @unchecked Sendable {

    private nonisolated static let rpcTimeout: Duration = .seconds(10)

    let port: Int

    private let client: GRPCCore.GRPCClient<HTTP2ClientTransport.Posix>
    private let core: Cc_Arduino_Cli_Commands_V1_ArduinoCoreService.Client<HTTP2ClientTransport.Posix>
    private let connectionTask: Task<Void, Error>
    private let logger = Logger(subsystem: "com.perr.Sketchpad2", category: "ArduinoCLI")

    @MainActor
    init(port: Int) throws {
        let transport = try HTTP2ClientTransport.Posix(
            target: .ipv4(address: "127.0.0.1", port: port),
            transportSecurity: .plaintext
        )
        let client = GRPCCore.GRPCClient(transport: transport)

        self.port = port
        self.client = client
        self.core = Cc_Arduino_Cli_Commands_V1_ArduinoCoreService.Client(wrapping: client)
        self.connectionTask = Task.detached(priority: .userInitiated) {
            try await client.runConnections()
        }
    }

    /// Creates a new Arduino Core instance on the daemon.
    func createInstance() async throws -> ArduinoCoreInstance {
        var options = GRPCCore.CallOptions.defaults
        options.timeout = Self.rpcTimeout

        let response: Cc_Arduino_Cli_Commands_V1_CreateResponse = try await core.create(
            Cc_Arduino_Cli_Commands_V1_CreateRequest(),
            options: options
        )
        return response.instance
    }

    /// Stops accepting new RPCs and tears the connection down.
    func shutdown() {
        logger.log("Closing the arduino-cli connection on port \(self.port)")
        client.beginGracefulShutdown()
        connectionTask.cancel()
    }
}
