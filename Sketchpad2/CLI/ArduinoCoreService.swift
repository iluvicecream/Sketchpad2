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

    /// The arduino-cli version the daemon reports.
    func currentVersion() async throws -> String {
        var options = GRPCCore.CallOptions.defaults
        options.timeout = Self.rpcTimeout

        let response: Cc_Arduino_Cli_Commands_V1_VersionResponse = try await core.version(
            Cc_Arduino_Cli_Commands_V1_VersionRequest(),
            options: options
        )
        return response.version
    }

    /// Destroys the given Arduino Core instance, waiting up to `timeout` for the daemon's reply.
    ///
    /// This blocks the calling thread so it can run from `applicationWillTerminate`, where the app
    /// has no way to await work before exiting. The RPC itself runs off the main actor.
    @discardableResult
    func destroyInstance(_ instance: ArduinoCoreInstance, timeout: Duration = .seconds(2)) -> Bool {
        let finished = DispatchSemaphore(value: 0)
        let result = DestroyResult()

        Task.detached(priority: .userInitiated) { [self] in
            var options = GRPCCore.CallOptions.defaults
            options.timeout = timeout

            var request = Cc_Arduino_Cli_Commands_V1_DestroyRequest()
            request.instance = instance

            do {
                let _: Cc_Arduino_Cli_Commands_V1_DestroyResponse = try await core.destroy(
                    request,
                    options: options
                )
                logger.log("Destroyed Arduino Core instance \(instance.id)")
                result.set(true)
            } catch {
                logger.error("Couldn't destroy the Arduino Core instance: \(error.localizedDescription, privacy: .public)")
            }
            finished.signal()
        }

        let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) * 1e-18
        guard finished.wait(timeout: .now() + seconds) == .success else {
            logger.error("Timed out waiting for the arduino-cli daemon to destroy the instance")
            return false
        }
        return result.value
    }

    /// Stops accepting new RPCs and tears the connection down.
    func shutdown() {
        logger.log("Closing the arduino-cli connection on port \(self.port)")
        client.beginGracefulShutdown()
        connectionTask.cancel()
    }
}

/// A lock-protected flag shared with the detached `Destroy` task.
private nonisolated final class DestroyResult: @unchecked Sendable {
    private let lock = NSLock()
    private var succeeded = false

    func set(_ newValue: Bool) {
        lock.withLock { succeeded = newValue }
    }

    var value: Bool {
        lock.withLock { succeeded }
    }
}
