//
//  ArduinoCoreService.swift
//  Sketchpad2
//

import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import SwiftProtobuf
import os

/// A single long-lived gRPC connection to the arduino-cli daemon, shared by every RPC.
nonisolated final class ArduinoCoreService: @unchecked Sendable {

    private nonisolated static let rpcTimeout: Duration = .seconds(10)
    private nonisolated static let indexUpdateTimeout: Duration = .seconds(120)

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

    /// Fetches the daemon configuration and writes a dump of it to the log.
    func configuration() async throws -> ArduinoConfiguration {
        var options = GRPCCore.CallOptions.defaults
        options.timeout = Self.rpcTimeout

        let response: Cc_Arduino_Cli_Commands_V1_ConfigurationGetResponse = try await core.configurationGet(
            Cc_Arduino_Cli_Commands_V1_ConfigurationGetRequest(),
            options: options
        )

        let configuration = response.configuration
        logConfiguration(configuration)
        return configuration
    }

    /// Sets a single value in the daemon's configuration.
    func settingsSetValue(key: String, encodedValue: String, valueFormat: String = "json") async throws {
        var options = GRPCCore.CallOptions.defaults
        options.timeout = Self.rpcTimeout

        var request = Cc_Arduino_Cli_Commands_V1_SettingsSetValueRequest()
        request.key = key
        request.encodedValue = encodedValue
        request.valueFormat = valueFormat

        let _: Cc_Arduino_Cli_Commands_V1_SettingsSetValueResponse = try await core.settingsSetValue(
            request,
            options: options
        )
    }

    /// Persists the settings currently held in memory to the daemon's configuration file and
    /// returns the encoded settings.
    @discardableResult
    func configurationSave(settingsFormat: String = "yaml") async throws -> String {
        var options = GRPCCore.CallOptions.defaults
        options.timeout = Self.rpcTimeout

        var request = Cc_Arduino_Cli_Commands_V1_ConfigurationSaveRequest()
        request.settingsFormat = settingsFormat

        let response: Cc_Arduino_Cli_Commands_V1_ConfigurationSaveResponse = try await core.configurationSave(
            request,
            options: options
        )
        return response.encodedSettings
    }

    /// Downloads the package indexes for the given instance, reporting high-level progress
    /// through `onProgress` and returning the per-index result.
    @discardableResult
    func updateIndex(
        _ instance: ArduinoCoreInstance,
        onProgress: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> [Cc_Arduino_Cli_Commands_V1_IndexUpdateReport] {
        var options = GRPCCore.CallOptions.defaults
        options.timeout = Self.indexUpdateTimeout

        var indexRequest = Cc_Arduino_Cli_Commands_V1_UpdateIndexRequest()
        indexRequest.instance = instance

        let reports: [Cc_Arduino_Cli_Commands_V1_IndexUpdateReport] = try await core.updateIndex(
            indexRequest,
            options: options
        ) { response in
            var updatedIndexes: [Cc_Arduino_Cli_Commands_V1_IndexUpdateReport] = []
            for try await message in response.messages {
                switch message.message {
                case .some(.downloadProgress(let progress)):
                    switch progress.message {
                    case .some(.start(let start)):
                        onProgress(start.label.isEmpty ? "Downloading \(start.url)" : start.label)
                    case .some(.end(let end)):
                        if !end.message.isEmpty {
                            onProgress(end.message)
                        }
                    case .some(.update), .none:
                        break
                    }
                case .some(.result(let result)):
                    updatedIndexes = result.updatedIndexes
                case .none:
                    break
                }
            }
            return updatedIndexes
        }
        return reports
    }

    /// Logs the configuration one line at a time so long dumps aren't truncated.
    private func logConfiguration(_ configuration: ArduinoConfiguration) {
        let lines = configuration.textFormatString()
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)

        logger.log("arduino-cli configuration (\(lines.count) lines)")
        for line in lines {
            logger.log("\(line, privacy: .public)")
        }
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
