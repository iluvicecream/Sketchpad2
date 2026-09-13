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
    private nonisolated static let instanceInitTimeout: Duration = .seconds(120)
    private nonisolated static let platformInstallTimeout: Duration = .seconds(900)
    private nonisolated static let librarySearchTimeout: Duration = .seconds(30)
    /// The whole library index runs to several megabytes, well past the transport's 4 MiB default.
    private nonisolated static let librarySearchPayloadLimit = 64 * 1024 * 1024

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

    /// Initializes an existing Arduino Core instance by loading platforms and libraries.
    ///
    /// The daemon streams its progress while it downloads and loads the platform and library
    /// indexes; each step is reported through `onProgress`. An error message in the stream is
    /// surfaced as a thrown `ArduinoCLIError`.
    func initializeInstance(
        _ instance: ArduinoCoreInstance,
        onProgress: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws {
        var options = GRPCCore.CallOptions.defaults
        options.timeout = Self.instanceInitTimeout

        var request = Cc_Arduino_Cli_Commands_V1_InitRequest()
        request.instance = instance

        try await core.`init`(request, options: options) { response in
            for try await message in response.messages {
                switch message.message {
                case .some(.initProgress(let progress)):
                    if let description = Self.progressDescription(of: progress) {
                        onProgress(description)
                    }
                case .some(.error(let status)):
                    throw ArduinoCLIError.instanceInitializationFailed(
                        reason: status.message.isEmpty ? "The daemon returned an unspecified error." : status.message
                    )
                case .some(.profile), .none:
                    break
                }
            }
        }
    }

    /// A short human-readable line for an initialization progress message, or `nil` when the
    /// message carries nothing worth reporting.
    private static func progressDescription(
        of progress: Cc_Arduino_Cli_Commands_V1_InitResponse.Progress
    ) -> String? {
        if progress.hasTaskProgress, let line = progressDescription(of: progress.taskProgress) {
            return line
        }

        if progress.hasDownloadProgress {
            return progressDescription(of: progress.downloadProgress)
        }

        return nil
    }

    /// A short human-readable line for a download progress message, or `nil` when the message
    /// carries nothing worth reporting.
    private static func progressDescription(
        of progress: Cc_Arduino_Cli_Commands_V1_DownloadProgress
    ) -> String? {
        switch progress.message {
        case .some(.start(let start)):
            return start.label.isEmpty ? "Downloading \(start.url)" : start.label
        case .some(.end(let end)):
            return end.message.isEmpty ? nil : end.message
        case .some(.update), .none:
            return nil
        }
    }

    /// A short human-readable line for a task progress message, or `nil` when the message carries
    /// nothing worth reporting.
    private static func progressDescription(
        of progress: Cc_Arduino_Cli_Commands_V1_TaskProgress
    ) -> String? {
        var line = progress.message.isEmpty ? progress.name : progress.message
        if progress.percent > 0, progress.percent < 100 {
            line += " (\(Int(progress.percent))%)"
        }
        return line.isEmpty ? nil : line
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

    /// Serializes the settings currently held in memory and returns them encoded.
    ///
    /// This does not touch the configuration file; the caller is responsible for persisting the
    /// returned settings.
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

    /// Searches the platform indexes for installable platforms and the boards they provide.
    ///
    /// This reads the indexes loaded by `Init`, so it works before anything is installed. The
    /// boards it reports for a platform that isn't installed are the author-provided names from
    /// the index; only installed platforms report FQBNs.
    func platformSearch(
        instance: ArduinoCoreInstance,
        searchArgs: String = "",
        manuallyInstalled: Bool = true
    ) async throws -> [Cc_Arduino_Cli_Commands_V1_PlatformSummary] {
        var options = GRPCCore.CallOptions.defaults
        options.timeout = Self.rpcTimeout

        var request = Cc_Arduino_Cli_Commands_V1_PlatformSearchRequest()
        request.instance = instance
        request.searchArgs = searchArgs
        request.manuallyInstalled = manuallyInstalled

        do {
            let response: Cc_Arduino_Cli_Commands_V1_PlatformSearchResponse = try await core.platformSearch(
                request,
                options: options
            )
            logger.log("arduino-cli platform search returned \(response.searchOutput.count) platforms")
            return response.searchOutput
        } catch {
            logger.error("arduino-cli platform search failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Searches the library indexes for the libraries matching `searchArgs`, or for every library
    /// when the keywords are empty.
    ///
    /// `omitReleasesDetails` leaves the per-version index data out of the response, which keeps a
    /// whole-index search tractable; the latest release of each library is always reported.
    func librarySearch(
        instance: ArduinoCoreInstance,
        searchArgs: String = "",
        omitReleasesDetails: Bool = true
    ) async throws -> Cc_Arduino_Cli_Commands_V1_LibrarySearchResponse {
        var options = GRPCCore.CallOptions.defaults
        options.timeout = Self.librarySearchTimeout
        // The NIO transport asks this option for the payload size it accepts in both directions,
        // even though the name only mentions requests. Without it a whole-index search fails to
        // decode with `resourceExhausted: Message has exceeded the configured maximum payload size`.
        options.maxRequestMessageBytes = Self.librarySearchPayloadLimit

        var request = Cc_Arduino_Cli_Commands_V1_LibrarySearchRequest()
        request.instance = instance
        request.searchArgs = searchArgs
        request.omitReleasesDetails = omitReleasesDetails

        do {
            let response: Cc_Arduino_Cli_Commands_V1_LibrarySearchResponse = try await core.librarySearch(
                request,
                options: options
            )
            logger.log("arduino-cli library search returned \(response.libraries.count) libraries")
            return response
        } catch {
            // The gRPC error carries the status code and message; Foundation's description for it
            // is only "GRPCCore.RPCError error 1", which says nothing useful.
            logger.error("arduino-cli library search failed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    /// Downloads and installs a platform and its tool dependencies, reporting progress through
    /// `onProgress`.
    func platformInstall(
        instance: ArduinoCoreInstance,
        platformID: String,
        version: String,
        onProgress: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws {
        let parts = platformID.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            throw ArduinoCLIError.platformInstallFailed(
                reason: "\"\(platformID)\" isn't a valid platform ID."
            )
        }

        var options = GRPCCore.CallOptions.defaults
        options.timeout = Self.platformInstallTimeout

        var request = Cc_Arduino_Cli_Commands_V1_PlatformInstallRequest()
        request.instance = instance
        request.platformPackage = parts[0]
        request.architecture = parts[1]
        request.version = version

        try await core.platformInstall(request, options: options) { response in
            for try await message in response.messages {
                switch message.message {
                case .some(.progress(let progress)):
                    if let description = Self.progressDescription(of: progress) {
                        onProgress(description)
                    }
                case .some(.taskProgress(let progress)):
                    if let description = Self.progressDescription(of: progress) {
                        onProgress(description)
                    }
                case .some(.result), .none:
                    break
                }
            }
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
