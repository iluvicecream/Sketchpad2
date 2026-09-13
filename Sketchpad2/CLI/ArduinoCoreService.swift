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
    private nonisolated static let libraryInstallTimeout: Duration = .seconds(900)
    /// A cold build compiles the board's whole core, which takes minutes on the larger platforms.
    private nonisolated static let sketchBuildTimeout: Duration = .seconds(1800)
    /// Index-shaped replies take longer than a plain query, so they get their own timeout.
    private nonisolated static let bulkTimeout: Duration = .seconds(30)
    /// Index-shaped replies run to tens of megabytes, well past the transport's 4 MiB default: the
    /// whole library index for a library search, and every board's own copy of its platform release
    /// for a board list.
    private nonisolated static let bulkPayloadLimit = 64 * 1024 * 1024

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

    /// A short description of a failed RPC. Foundation's description of a gRPC error is only
    /// "GRPCCore.RPCError error 1", so prefer the status code and message the error carries.
    private static func reason(for error: any Error) -> String {
        guard let rpcError = error as? RPCError else { return error.localizedDescription }
        return "\(rpcError.code): \(rpcError.message)"
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

    /// Lists the ports the daemon detects and the boards attached to them.
    ///
    /// The RPC waits up to `timeoutMilliseconds` for the discovery sources to report, so it takes
    /// roughly that long when nothing is attached.
    func boardList(
        instance: ArduinoCoreInstance,
        timeoutMilliseconds: Int64 = 2000
    ) async throws -> [Cc_Arduino_Cli_Commands_V1_DetectedPort] {
        var options = GRPCCore.CallOptions.defaults
        options.timeout = Self.rpcTimeout

        var request = Cc_Arduino_Cli_Commands_V1_BoardListRequest()
        request.instance = instance
        request.timeout = timeoutMilliseconds

        do {
            let response: Cc_Arduino_Cli_Commands_V1_BoardListResponse = try await core.boardList(
                request,
                options: options
            )
            logger.log("arduino-cli board list returned \(response.ports.count) ports")
            for warning in response.warnings {
                logger.warning("arduino-cli board list: \(warning, privacy: .public)")
            }
            return response.ports
        } catch {
            logger.error("arduino-cli board list failed: \(String(describing: error), privacy: .public)")
            throw ArduinoCLIError.boardListFailed(reason: Self.reason(for: error))
        }
    }

    /// Lists the boards the installed platforms provide, so the editor can offer one for a port
    /// the daemon couldn't identify.
    ///
    /// This reads the boards installed for the Core instance rather than the USB ports, so it
    /// reports nothing until a platform is installed. `searchArgs` filters the list by board name
    /// or FQBN; leaving it empty returns every board.
    ///
    /// Each board carries its platform's whole release, so the reply is many times the size of the
    /// board list itself and needs the raised payload limit to decode.
    func boardListAll(
        instance: ArduinoCoreInstance,
        searchArgs: String = "",
        includeHiddenBoards: Bool = false
    ) async throws -> [Cc_Arduino_Cli_Commands_V1_BoardListItem] {
        var options = GRPCCore.CallOptions.defaults
        options.timeout = Self.bulkTimeout
        options.maxRequestMessageBytes = Self.bulkPayloadLimit

        var request = Cc_Arduino_Cli_Commands_V1_BoardListAllRequest()
        request.instance = instance
        request.searchArgs = searchArgs.isEmpty ? [] : [searchArgs]
        request.includeHiddenBoards = includeHiddenBoards

        do {
            let response: Cc_Arduino_Cli_Commands_V1_BoardListAllResponse = try await core.boardListAll(
                request,
                options: options
            )
            logger.log("arduino-cli board list all returned \(response.boards.count) boards")
            return response.boards
        } catch {
            logger.error("arduino-cli board list all failed: \(String(describing: error), privacy: .public)")
            throw ArduinoCLIError.boardListAllFailed(reason: Self.reason(for: error))
        }
    }

    /// Compiles the sketch in `sketchPath` for the board `fqbn` names, streaming whatever the
    /// builder prints until the build ends.
    ///
    /// The stream finishes with an error when the build fails, after the compiler's diagnostics
    /// have already been reported as output.
    func compile(
        instance: ArduinoCoreInstance,
        fqbn: String,
        sketchPath: String
    ) -> AsyncThrowingStream<SketchBuildEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) { [self] in
                var options = GRPCCore.CallOptions.defaults
                options.timeout = Self.sketchBuildTimeout

                var request = Cc_Arduino_Cli_Commands_V1_CompileRequest()
                request.instance = instance
                request.fqbn = fqbn
                request.sketchPath = sketchPath

                do {
                    try await core.compile(request, options: options) { response in
                        for try await message in response.messages {
                            switch message.message {
                            case .some(.outStream(let data)):
                                continuation.yield(.output(data, isError: false))
                            case .some(.errStream(let data)):
                                continuation.yield(.output(data, isError: true))
                            case .some(.progress(let progress)):
                                if let line = Self.progressDescription(of: progress) {
                                    continuation.yield(.progress(line))
                                }
                            case .some(.result), .none:
                                break
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    logger.error("arduino-cli compile failed: \(String(describing: error), privacy: .public)")
                    continuation.finish(throwing: ArduinoCLIError.sketchVerifyFailed(reason: Self.reason(for: error)))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Compiles the sketch in `sketchPath` and uploads it to `port`, streaming whatever the
    /// toolchain prints until the upload ends.
    func upload(
        instance: ArduinoCoreInstance,
        fqbn: String,
        sketchPath: String,
        port: Cc_Arduino_Cli_Commands_V1_Port
    ) -> AsyncThrowingStream<SketchBuildEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) { [self] in
                var options = GRPCCore.CallOptions.defaults
                options.timeout = Self.sketchBuildTimeout

                var request = Cc_Arduino_Cli_Commands_V1_UploadRequest()
                request.instance = instance
                request.fqbn = fqbn
                request.sketchPath = sketchPath
                request.port = port

                do {
                    try await core.upload(request, options: options) { response in
                        for try await message in response.messages {
                            switch message.message {
                            case .some(.outStream(let data)):
                                continuation.yield(.output(data, isError: false))
                            case .some(.errStream(let data)):
                                continuation.yield(.output(data, isError: true))
                            case .some(.result), .none:
                                break
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    logger.error("arduino-cli upload failed: \(String(describing: error), privacy: .public)")
                    continuation.finish(throwing: ArduinoCLIError.sketchUploadFailed(reason: Self.reason(for: error)))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Lists the settings the daemon's monitor accepts for a port, so the serial monitor can offer
    /// what that port's monitor understands rather than a fixed idea of what a port needs.
    ///
    /// The board is optional but disambiguates when more than one platform supplies the monitor for
    /// a protocol.
    func monitorPortSettings(
        instance: ArduinoCoreInstance,
        portProtocol: String,
        fqbn: String?
    ) async throws -> [MonitorPortSetting] {
        var options = GRPCCore.CallOptions.defaults
        options.timeout = Self.rpcTimeout

        var request = Cc_Arduino_Cli_Commands_V1_EnumerateMonitorPortSettingsRequest()
        request.instance = instance
        request.portProtocol = portProtocol
        if let fqbn { request.fqbn = fqbn }

        do {
            let response: Cc_Arduino_Cli_Commands_V1_EnumerateMonitorPortSettingsResponse =
                try await core.enumerateMonitorPortSettings(request, options: options)
            logger.log("arduino-cli monitor settings returned \(response.settings.count) settings")
            return response.settings.map(MonitorPortSetting.init)
        } catch {
            logger.error(
                "arduino-cli enumerate monitor port settings failed: \(String(describing: error), privacy: .public)"
            )
            throw ArduinoCLIError.monitorSettingsFailed(reason: Self.reason(for: error))
        }
    }

    /// Opens the daemon's monitor on `port` and hands back the connection it opened.
    ///
    /// The RPC is a stream in both directions, so the session is returned straight away and the
    /// daemon's replies arrive through `SerialMonitorSession.events` as they happen: the port is
    /// opened by the first request, which is already queued when this returns.
    func openMonitor(
        instance: ArduinoCoreInstance,
        port: Cc_Arduino_Cli_Commands_V1_Port,
        fqbn: String?,
        settings: [String: String]
    ) -> SerialMonitorSession {
        var openRequest = Cc_Arduino_Cli_Commands_V1_MonitorPortOpenRequest()
        openRequest.instance = instance
        openRequest.port = port
        openRequest.fqbn = fqbn ?? ""
        openRequest.portConfiguration = Cc_Arduino_Cli_Commands_V1_MonitorPortConfiguration(
            settings: settings
        )

        let (requests, requestContinuation) = AsyncStream.makeStream(
            of: Cc_Arduino_Cli_Commands_V1_MonitorRequest.self
        )
        let (events, eventContinuation) = AsyncStream.makeStream(of: SerialMonitorEvent.self)
        requestContinuation.yield(SerialMonitorSession.request { $0.openRequest = openRequest })

        logger.log("arduino-cli monitor opening \(port.address, privacy: .public)")

        let rpc = Task.detached(priority: .userInitiated) { [self] in
            do {
                try await core.monitor(metadata: [:], options: .defaults) { writer in
                    for await request in requests {
                        try await writer.write(request)
                    }
                } onResponse: { response in
                    for try await message in response.messages {
                        switch message.message {
                        case .some(.rxData(let data)):
                            eventContinuation.yield(.received(data))
                        case .some(.appliedSettings(let configuration)):
                            eventContinuation.yield(.connected(baudRate: configuration.baudRate))
                        case .some(.error(let text)):
                            eventContinuation.yield(.failed(text))
                        case .some(.success), .none:
                            break
                        }
                    }
                }
            } catch {
                logger.error("arduino-cli monitor failed: \(String(describing: error), privacy: .public)")
                eventContinuation.yield(.failed(Self.reason(for: error)))
            }
            eventContinuation.finish()
        }

        return SerialMonitorSession(
            requests: requestContinuation,
            events: events,
            rpc: rpc
        )
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
        options.timeout = Self.bulkTimeout
        // The NIO transport asks this option for the payload size it accepts in both directions,
        // even though the name only mentions requests. Without it a whole-index search fails to
        // decode with `resourceExhausted: Message has exceeded the configured maximum payload size`.
        options.maxRequestMessageBytes = Self.bulkPayloadLimit

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
        guard let parts = Self.platformComponents(of: platformID) else {
            throw ArduinoCLIError.platformInstallFailed(
                reason: "\"\(platformID)\" isn't a valid platform ID."
            )
        }

        var options = GRPCCore.CallOptions.defaults
        options.timeout = Self.platformInstallTimeout

        var request = Cc_Arduino_Cli_Commands_V1_PlatformInstallRequest()
        request.instance = instance
        request.platformPackage = parts.package
        request.architecture = parts.architecture
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

    /// Uninstalls a platform and its tool dependencies, reporting progress through `onProgress`.
    func platformUninstall(
        instance: ArduinoCoreInstance,
        platformID: String,
        onProgress: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws {
        guard let parts = Self.platformComponents(of: platformID) else {
            throw ArduinoCLIError.platformUninstallFailed(
                reason: "\"\(platformID)\" isn't a valid platform ID."
            )
        }

        var options = GRPCCore.CallOptions.defaults
        options.timeout = Self.platformInstallTimeout

        var request = Cc_Arduino_Cli_Commands_V1_PlatformUninstallRequest()
        request.instance = instance
        request.platformPackage = parts.package
        request.architecture = parts.architecture

        try await core.platformUninstall(request, options: options) { response in
            for try await message in response.messages {
                switch message.message {
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

    /// Splits a platform ID like `arduino:avr` into its vendor and architecture, or `nil` when the
    /// ID isn't in that form.
    private static func platformComponents(of platformID: String) -> (package: String, architecture: String)? {
        let parts = platformID.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return (parts[0], parts[1])
    }

    /// Lists the libraries installed in the given instance.
    ///
    /// Built-in libraries shipped with a platform are left out, so the list lines up with what
    /// the Library Manager can uninstall.
    func libraryList(instance: ArduinoCoreInstance) async throws -> [InstalledLibrary] {
        var options = GRPCCore.CallOptions.defaults
        options.timeout = Self.rpcTimeout

        var request = Cc_Arduino_Cli_Commands_V1_LibraryListRequest()
        request.instance = instance
        request.all = false

        do {
            let response: Cc_Arduino_Cli_Commands_V1_LibraryListResponse = try await core.libraryList(
                request,
                options: options
            )
            logger.log("arduino-cli library list returned \(response.installedLibraries.count) libraries")
            return response.installedLibraries.map(InstalledLibrary.init)
        } catch {
            logger.error("arduino-cli library list failed: \(String(describing: error), privacy: .public)")
            throw ArduinoCLIError.libraryListFailed(reason: Self.reason(for: error))
        }
    }

    /// Downloads and installs the given version of a library, reporting progress through
    /// `onProgress`.
    ///
    /// Installing a version newer than the installed one upgrades; an older one downgrades.
    func libraryInstall(
        instance: ArduinoCoreInstance,
        name: String,
        version: String,
        onProgress: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws {
        var options = GRPCCore.CallOptions.defaults
        options.timeout = Self.libraryInstallTimeout

        var request = Cc_Arduino_Cli_Commands_V1_LibraryInstallRequest()
        request.instance = instance
        request.name = name
        request.version = version

        try await core.libraryInstall(request, options: options) { response in
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

    /// Uninstalls the given version of a library, reporting progress through `onProgress`.
    func libraryUninstall(
        instance: ArduinoCoreInstance,
        name: String,
        version: String,
        onProgress: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws {
        var options = GRPCCore.CallOptions.defaults
        options.timeout = Self.libraryInstallTimeout

        var request = Cc_Arduino_Cli_Commands_V1_LibraryUninstallRequest()
        request.instance = instance
        request.name = name
        request.version = version

        try await core.libraryUninstall(request, options: options) { response in
            for try await message in response.messages {
                switch message.message {
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
