//
//  MainController.swift
//  Sketchpad2
//

import AppKit
import Foundation
import GRPCCore
import Observation
import os

/// App-wide root controller. Owns the observable state the UI binds to and delegates the work
/// behind it to `ArduinoCLIService`.
@Observable
@MainActor
final class MainController {

    /// Where the app is in the arduino-cli setup flow.
    enum Phase: Equatable {
        case idle
        case checking
        case downloading
        case extracting
        case startingDaemon
        case initializing(message: String?)
        case ready(port: Int)
        case failed(ArduinoCLIError)
    }

    /// Where the app is in the board index refresh flow.
    enum BoardIndexUpdate: Equatable {
        case idle
        case updating(message: String?)
        case failed(String)
    }

    /// Where the app is in the configuration fetch.
    enum ConfigurationLoad: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    /// Where the app is in the installable-board catalog flow.
    enum BoardCatalog: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    /// Where the app is in the fetch of the boards the installed platforms provide.
    enum KnownBoardCatalog: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    /// Where the app is in the installable-library catalog flow.
    enum LibraryCatalog: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    /// The platform install or uninstall in flight, if any.
    enum PlatformOperation: Equatable {
        case idle
        case installing(platformID: String, message: String?)
        case uninstalling(platformID: String, message: String?)
        case failed(platformID: String, message: String)
    }

    /// The library install or uninstall in flight, if any.
    enum LibraryOperation: Equatable {
        case idle
        case installing(libraryName: String, message: String?)
        case uninstalling(libraryName: String, message: String?)
        case failed(libraryName: String, message: String)
    }

    /// Where the app is in verifying or uploading the sketch the editor holds.
    enum SketchOperation: Equatable {
        case idle
        case verifying(message: String?)
        case uploading(message: String?)
        case failed(message: String)
        case finished(message: String)

        /// Whether the toolchain is still working, which is when the editor holds off repeating it.
        var isRunning: Bool {
            switch self {
            case .verifying, .uploading:
                true
            case .idle, .failed, .finished:
                false
            }
        }
    }

    private(set) var phase: Phase = .idle
    private(set) var daemonPort: Int?
    /// The Arduino Core instance created on the daemon via the `Create` RPC.
    private(set) var instance: ArduinoCoreInstance?

    /// The arduino-cli version reported by the daemon at startup.
    private(set) var arduinoCLIVersion: String?

    /// The daemon configuration, fetched when the Settings window opens.
    private(set) var configuration: ArduinoConfiguration?

    /// The state of the configuration fetch, used to gate the Settings window.
    private(set) var configurationLoad: ConfigurationLoad = .idle

    /// The board index refresh triggered after board manager URLs are saved.
    private(set) var boardIndexUpdate: BoardIndexUpdate = .idle

    /// The state of the installable-board catalog, used to gate the Board Manager window.
    private(set) var boardCatalog: BoardCatalog = .idle

    /// The platforms the indexes offer, sorted by name.
    private(set) var installablePlatforms: [InstallablePlatform] = []

    /// The state of the installable-library catalog, used to gate the Library Manager window.
    private(set) var libraryCatalog: LibraryCatalog = .idle

    /// The libraries the indexes offer, sorted by name.
    private(set) var installableLibraries: [InstallableLibrary] = []

    /// The platform install or uninstall currently in flight, if any.
    private(set) var platformOperation: PlatformOperation = .idle

    /// The library install or uninstall currently in flight, if any.
    private(set) var libraryOperation: LibraryOperation = .idle

    /// The verify or upload currently in flight, if any, and how the last one ended.
    private(set) var sketchOperation: SketchOperation = .idle

    /// What the toolchain printed during the last verify or upload, as the output pane lists it.
    private(set) var buildOutput: [BuildOutputLine] = []

    /// The bytes of the current build that don't make a whole line yet, one buffer per stream.
    private var standardOutput = Data()
    private var errorOutput = Data()

    /// The identifier to give the next output line, which only has to be unique among the pane's
    /// current lines.
    private var nextOutputLineID = 0

    /// How many lines of build output the pane keeps before it starts dropping the oldest.
    private nonisolated static let outputLineLimit = 2000

    /// The ports the daemon last reported, listed by the editor's port menu.
    private(set) var connectedPorts: [ConnectedPort] = []

    /// The state of the known-board fetch, used to gate the board and port dialog's board list.
    private(set) var knownBoardCatalog: KnownBoardCatalog = .idle

    /// The boards the installed platforms provide, sorted by name.
    private(set) var knownBoards: [KnownBoard] = []

    /// The address of the port the editor is set to use, or `nil` when none is picked.
    var selectedPortID: ConnectedPort.ID?

    /// The port the editor is set to use.
    var selectedPort: ConnectedPort? {
        connectedPorts.first { $0.id == selectedPortID }
    }

    /// The FQBN of the board the editor is set to use, or `nil` when none is picked.
    var selectedBoardFQBN: String?

    /// The board the editor is set to use, whether it came from the installed platforms or from
    /// what the daemon matched to the selected port.
    var selectedBoard: KnownBoard? {
        guard let selectedBoardFQBN else { return nil }
        return knownBoards.first { $0.fqbn == selectedBoardFQBN }
            ?? selectedPort?.boards.first { $0.fqbn == selectedBoardFQBN }
    }

    /// The additional package index URLs currently configured in the daemon.
    var boardManagerURLs: [String] {
        configuration?.boardManager.additionalUrls ?? []
    }

    /// The shared gRPC connection to the daemon, available once setup finishes.
    var coreService: ArduinoCoreService? {
        service.coreService
    }

    private let service: any ArduinoCLIServicing
    private var setupTask: Task<Void, Never>?
    @ObservationIgnored
    private nonisolated(unsafe) var terminationObserver: (any NSObjectProtocol)?
    
    private let logger = Logger(subsystem: "com.perr.Sketchpad2", category: "MainController")

    init(service: any ArduinoCLIServicing = ArduinoCLIService()) {
        self.service = service
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.shutdown()
            }
        }
    }

    deinit {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
    }

    var isReady: Bool {
        if case .ready = phase { return true }
        return false
    }

    /// Starts the setup flow. Safe to call from every window; only the first call does work.
    func start() {
        guard setupTask == nil, !isReady else { return }
        runSetup()
    }

    /// Re-runs the setup flow after a failure.
    func retry() {
        setupTask?.cancel()
        setupTask = nil
        runSetup()
    }

    func shutdown() {
        setupTask?.cancel()
        setupTask = nil
        service.shutdown()
        daemonPort = nil
        instance = nil
        arduinoCLIVersion = nil
        configuration = nil
        configurationLoad = .idle
        boardIndexUpdate = .idle
        boardCatalog = .idle
        installablePlatforms = []
        libraryCatalog = .idle
        installableLibraries = []
        platformOperation = .idle
        libraryOperation = .idle
        connectedPorts = []
        selectedPortID = nil
        knownBoardCatalog = .idle
        knownBoards = []
        selectedBoardFQBN = nil
        sketchOperation = .idle
        clearBuildOutput()
        nextOutputLineID = 0
        phase = .idle
    }

    /// Fetches the daemon configuration so it can be inspected. Safe to call whenever Settings opens.
    func loadConfiguration() async {
        guard let coreService else {
            configurationLoad = .idle
            return
        }

        if configuration == nil {
            configurationLoad = .loading
        }

        do {
            configuration = try await coreService.configuration()
            configurationLoad = .loaded
        } catch {
            // Keep any configuration already on screen; only surface a failure when there's none.
            if configuration == nil {
                configurationLoad = .failed(error.localizedDescription)
            }
        }
    }

    /// Asks the daemon which ports are connected, publishes them for the editor's port menu, and
    /// writes each detected port to the log.
    ///
    /// The editor calls this as it loads, so the menu and the log record what was plugged in when
    /// the sketch opened. A failure is logged rather than surfaced, since detection is best effort.
    func refreshConnectedBoards() async {
        guard let coreService, let instance else { return }

        do {
            let ports = try await coreService.boardList(instance: instance).map(ConnectedPort.init)
            connectedPorts = ports
            dropUnavailableSelection()

            guard !ports.isEmpty else {
                logger.log("Detected no boards on any port")
                return
            }
            for port in ports {
                logger.log("Detected port \(Self.description(of: port), privacy: .public)")
            }
        } catch {
            let failure = error as? ArduinoCLIError ?? .boardListFailed(reason: Self.reason(for: error))
            logger.error("Couldn't list the boards: \(failure.errorDescription ?? "unknown error", privacy: .public)")
        }
    }

    /// Clears a selection whose port is no longer connected, so the menu asks for a port again
    /// instead of showing one that's gone.
    private func dropUnavailableSelection() {
        if !connectedPorts.contains(where: { $0.id == selectedPortID }) {
            selectedPortID = nil
        }
    }

    /// Loads the boards the installed platforms provide, so the board and port dialog can offer
    /// them. Safe to call each time the dialog opens.
    func refreshKnownBoards() async {
        guard let coreService, let instance else { return }

        knownBoardCatalog = .loading
        do {
            knownBoards = try await coreService.boardListAll(instance: instance)
                .map(KnownBoard.init)
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            knownBoardCatalog = .loaded
            logger.log("Loaded \(self.knownBoards.count) boards from the installed platforms")
        } catch {
            let failure = error as? ArduinoCLIError ?? .boardListAllFailed(reason: Self.reason(for: error))
            knownBoardCatalog = .failed(failure.errorDescription ?? "unknown error")
            logger.error("Couldn't list the installed boards: \(failure.errorDescription ?? "unknown error", privacy: .public)")
        }
    }

    /// Picks a port, along with the board the daemon matched to it.
    ///
    /// A port the daemon couldn't identify leaves whatever board was already picked alone, since
    /// naming that board is the user's job — that's what the board and port dialog is for.
    func select(port: ConnectedPort) {
        selectedPortID = port.id
        if let board = port.board { selectedBoardFQBN = board.fqbn }
    }

    /// Picks the board and port chosen in the board and port dialog, either of which may be
    /// cleared to leave the editor without one.
    func select(board: KnownBoard?, port: ConnectedPort.ID?) {
        selectedBoardFQBN = board?.fqbn
        selectedPortID = port
    }

    /// Compiles the sketch for the selected board, streaming what the builder prints to the pane.
    func verify(_ sketch: SketchSource) async {
        guard !sketchOperation.isRunning else { return }
        guard let fqbn = selectedBoardFQBN else {
            sketchOperation = .failed(message: "Pick a board before verifying.")
            return
        }
        guard let coreService, let instance else { return }

        begin(.verifying(message: nil))
        logger.log("Verifying \(sketch.name, privacy: .public) for \(fqbn, privacy: .public)")

        do {
            let folder = try sketch.stage()
            try await run(coreService.compile(instance: instance, fqbn: fqbn, sketchPath: folder.path))
            sketchOperation = .finished(message: "Verify succeeded.")
        } catch {
            report(error as? ArduinoCLIError ?? .sketchVerifyFailed(reason: Self.reason(for: error)))
        }
    }

    /// Compiles the sketch for the selected board and uploads it through the selected port.
    func upload(_ sketch: SketchSource) async {
        guard !sketchOperation.isRunning else { return }
        guard let fqbn = selectedBoardFQBN else {
            sketchOperation = .failed(message: "Pick a board before uploading.")
            return
        }
        guard let port = selectedPort else {
            sketchOperation = .failed(message: "Pick a port before uploading.")
            return
        }
        guard let coreService, let instance else { return }

        begin(.uploading(message: nil))
        logger.log("Uploading \(sketch.name, privacy: .public) to \(port.id, privacy: .public)")

        do {
            let folder = try sketch.stage()
            try await run(
                coreService.upload(
                    instance: instance,
                    fqbn: fqbn,
                    sketchPath: folder.path,
                    port: port.daemonPort
                )
            )
            sketchOperation = .finished(message: "Uploaded to \(port.id).")
        } catch {
            report(error as? ArduinoCLIError ?? .sketchUploadFailed(reason: Self.reason(for: error)))
        }
    }

    /// Empties the output pane without disturbing what the last build ended as.
    func clearBuildOutput() {
        buildOutput.removeAll()
        standardOutput.removeAll()
        errorOutput.removeAll()
    }

    /// Clears the pane for a build that's about to start and records what it's doing.
    private func begin(_ operation: SketchOperation) {
        clearBuildOutput()
        nextOutputLineID = 0
        sketchOperation = operation
    }

    /// Drains one build's events into the pane until the stream ends.
    private func run(_ stream: AsyncThrowingStream<SketchBuildEvent, Error>) async throws {
        for try await event in stream {
            switch event {
            case .output(let data, let isError):
                append(data, isError: isError)
            case .progress(let message):
                updateProgress(message)
            }
        }
        flushOutput()
    }

    /// Shows a failed build in the pane and the log, keeping whatever the toolchain printed.
    private func report(_ failure: ArduinoCLIError) {
        flushOutput()
        let message = failure.errorDescription ?? "The build failed."
        sketchOperation = .failed(message: message)
        logger.error("\(message, privacy: .public)")
    }

    /// Puts the daemon's latest progress line in the pane's headline, leaving the kind of build it
    /// belongs to alone.
    private func updateProgress(_ message: String) {
        switch sketchOperation {
        case .verifying:
            sketchOperation = .verifying(message: message)
        case .uploading:
            sketchOperation = .uploading(message: message)
        case .idle, .failed, .finished:
            break
        }
    }

    /// Adds streamed bytes to the pane, a line at a time, holding back a trailing part-line until
    /// the rest of it arrives. The two streams are drained separately so a line is never assembled
    /// out of both.
    private func append(_ data: Data, isError: Bool) {
        if isError {
            errorOutput.append(data)
            drain(&errorOutput, isError: true)
        } else {
            standardOutput.append(data)
            drain(&standardOutput, isError: false)
        }
    }

    private func drain(_ buffer: inout Data, isError: Bool) {
        while let newline = buffer.firstIndex(of: 0x0A) {
            var line = Data(buffer[buffer.startIndex..<newline])
            if line.last == 0x0D { line.removeLast() }
            buffer.removeSubrange(buffer.startIndex...newline)
            appendLine(String(decoding: line, as: UTF8.self), isError: isError)
        }
    }

    /// Adds whatever a finished build left without a closing newline, so its last line survives.
    private func flushOutput() {
        if !standardOutput.isEmpty {
            appendLine(String(decoding: standardOutput, as: UTF8.self), isError: false)
            standardOutput.removeAll()
        }
        if !errorOutput.isEmpty {
            appendLine(String(decoding: errorOutput, as: UTF8.self), isError: true)
            errorOutput.removeAll()
        }
    }

    /// Appends one finished line, dropping the oldest once the pane holds more than anyone reads.
    private func appendLine(_ text: String, isError: Bool) {
        buildOutput.append(BuildOutputLine(id: nextOutputLineID, isError: isError, text: text))
        nextOutputLineID += 1

        if buildOutput.count > Self.outputLineLimit {
            buildOutput.removeFirst(buildOutput.count - Self.outputLineLimit)
        }
    }

    /// An `address (protocol) — board, board` line for one detected port, dropping whatever the
    /// daemon leaves out.
    private static func description(of port: ConnectedPort) -> String {
        var line = port.id
        if !port.protocolLabel.isEmpty { line += " (\(port.protocolLabel))" }
        if !port.boardNames.isEmpty { line += " — \(port.boardNames.joined(separator: ", "))" }
        return line
    }

    /// Loads the platforms the indexes offer, so the Board Manager can browse and install them.
    /// Safe to call whenever the Board Manager window opens.
    func loadBoards() async {
        guard let coreService, let instance else { return }

        boardCatalog = .loading
        if case .failed = platformOperation {
            platformOperation = .idle
        }

        do {
            let summaries = try await coreService.platformSearch(instance: instance)
            installablePlatforms = summaries
                .map(InstallablePlatform.init)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            boardCatalog = .loaded
        } catch {
            let failure = error as? ArduinoCLIError ?? .platformSearchFailed(reason: error.localizedDescription)
            logger.error("Couldn't load the board catalog: \(failure.errorDescription ?? "unknown error", privacy: .public)")
            boardCatalog = .failed(failure.errorDescription ?? "Couldn't load the platform indexes.")
        }
    }

    /// Installs the given version of a platform, upgrading or downgrading as needed, and
    /// refreshes the catalog when it finishes.
    func installPlatform(_ platform: InstallablePlatform, version: String) async {
        guard let coreService, let instance else { return }
        guard platform.version(version) != nil else { return }

        platformOperation = .installing(platformID: platform.id, message: nil)
        do {
            try await coreService.platformInstall(
                instance: instance,
                platformID: platform.id,
                version: version
            ) { [weak self] message in
                Task { @MainActor in
                    guard let self, case .installing(let id, _) = self.platformOperation, id == platform.id else { return }
                    self.platformOperation = .installing(platformID: id, message: message)
                }
            }
            platformOperation = .idle
            await loadBoards()
        } catch {
            let failure = error as? ArduinoCLIError ?? .platformInstallFailed(reason: Self.reason(for: error))
            platformOperation = .failed(
                platformID: platform.id,
                message: failure.errorDescription ?? "Couldn't install the platform."
            )
        }
    }

    /// Uninstalls a platform and refreshes the catalog when it finishes.
    func uninstallPlatform(_ platform: InstallablePlatform) async {
        guard let coreService, let instance else { return }
        guard platform.isInstalled else { return }

        platformOperation = .uninstalling(platformID: platform.id, message: nil)
        do {
            try await coreService.platformUninstall(
                instance: instance,
                platformID: platform.id
            ) { [weak self] message in
                Task { @MainActor in
                    guard let self, case .uninstalling(let id, _) = self.platformOperation, id == platform.id else { return }
                    self.platformOperation = .uninstalling(platformID: id, message: message)
                }
            }
            platformOperation = .idle
            await loadBoards()
        } catch {
            let failure = error as? ArduinoCLIError ?? .platformUninstallFailed(reason: Self.reason(for: error))
            platformOperation = .failed(
                platformID: platform.id,
                message: failure.errorDescription ?? "Couldn't uninstall the platform."
            )
        }
    }

    /// Loads the libraries the indexes offer and the versions already installed, so the Library
    /// Manager can browse, install, and uninstall them. Installed libraries the index doesn't list
    /// are included too, so they can still be uninstalled. Safe to call whenever the window opens.
    func loadLibraries() async {
        guard let coreService, let instance else { return }

        libraryCatalog = .loading
        if case .failed = libraryOperation {
            libraryOperation = .idle
        }

        do {
            async let installed = coreService.libraryList(instance: instance)
            async let search = coreService.librarySearch(instance: instance)
            let (installedLibraries, response) = try await (installed, search)
            let installedVersions = Self.installedLibraryVersions(installedLibraries)

            let indexed = response.libraries
                .map { InstallableLibrary($0, installedVersion: installedVersions[$0.name] ?? "") }
            let indexedNames = Set(indexed.map(\.name))
            let unindexed = installedVersions
                .filter { !indexedNames.contains($0.key) }
                .map { InstallableLibrary(installedName: $0.key, version: $0.value) }

            installableLibraries = (indexed + unindexed)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            libraryCatalog = .loaded
        } catch {
            let failure = error as? ArduinoCLIError ?? .librarySearchFailed(reason: Self.reason(for: error))
            logger.error("Couldn't load the library catalog: \(failure.errorDescription ?? "unknown error", privacy: .public)")
            libraryCatalog = .failed(failure.errorDescription ?? "Couldn't load the library indexes.")
        }
    }

    /// Installs the given version of a library, upgrading or downgrading as needed, and refreshes
    /// the catalog when it finishes.
    func installLibrary(_ library: InstallableLibrary, version: String) async {
        guard let coreService, let instance else { return }
        guard library.hasVersion(version) else { return }

        libraryOperation = .installing(libraryName: library.name, message: nil)
        do {
            try await coreService.libraryInstall(
                instance: instance,
                name: library.name,
                version: version
            ) { [weak self] message in
                Task { @MainActor in
                    guard let self, case .installing(let name, _) = self.libraryOperation, name == library.name else { return }
                    self.libraryOperation = .installing(libraryName: name, message: message)
                }
            }
            libraryOperation = .idle
            await loadLibraries()
        } catch {
            let failure = error as? ArduinoCLIError ?? .libraryInstallFailed(reason: Self.reason(for: error))
            libraryOperation = .failed(
                libraryName: library.name,
                message: failure.errorDescription ?? "Couldn't install the library."
            )
        }
    }

    /// Uninstalls the installed version of a library and refreshes the catalog when it finishes.
    func uninstallLibrary(_ library: InstallableLibrary) async {
        guard let coreService, let instance else { return }
        guard library.isInstalled else { return }

        libraryOperation = .uninstalling(libraryName: library.name, message: nil)
        do {
            try await coreService.libraryUninstall(
                instance: instance,
                name: library.name,
                version: library.installedVersion
            ) { [weak self] message in
                Task { @MainActor in
                    guard let self, case .uninstalling(let name, _) = self.libraryOperation, name == library.name else { return }
                    self.libraryOperation = .uninstalling(libraryName: name, message: message)
                }
            }
            libraryOperation = .idle
            await loadLibraries()
        } catch {
            let failure = error as? ArduinoCLIError ?? .libraryUninstallFailed(reason: Self.reason(for: error))
            libraryOperation = .failed(
                libraryName: library.name,
                message: failure.errorDescription ?? "Couldn't uninstall the library."
            )
        }
    }

    /// The installed version of each library, keyed by name. A library installed more than once
    /// keeps the first version the daemon reports.
    private static func installedLibraryVersions(_ libraries: [InstalledLibrary]) -> [String: String] {
        var versions: [String: String] = [:]
        for library in libraries where !library.name.isEmpty {
            if versions[library.name] == nil {
                versions[library.name] = library.version
            }
        }
        return versions
    }

    /// A short description of a failed RPC. Foundation's description of a gRPC error is only
    /// "GRPCCore.RPCError error 1", so prefer the status code and message the error carries.
    private static func reason(for error: any Error) -> String {
        guard let rpcError = error as? RPCError else { return error.localizedDescription }
        return "\(rpcError.code): \(rpcError.message)"
    }

    /// Replaces the board manager additional URLs, persists the configuration, and refreshes the
    /// cached configuration so the UI reflects the stored values.
    func saveBoardManagerURLs(_ urls: [String]) async throws {
        guard let coreService else { throw ArduinoCLIError.daemonNotRunning }

        let encodedValue = try Self.encodeBoardManagerURLs(urls)

        do {
            try await coreService.settingsSetValue(
                key: ArduinoCLISettingsKey.boardManagerAdditionalURLs,
                encodedValue: encodedValue,
                valueFormat: "json"
            )
        } catch {
            throw ArduinoCLIError.settingsUpdateFailed(reason: error.localizedDescription)
        }

        do {
            let encodedSettings = try await coreService.configurationSave(settingsFormat: "yaml")
            try Self.persistConfiguration(encodedSettings, to: service.configurationFileURL)
        } catch {
            throw ArduinoCLIError.configurationSaveFailed(reason: error.localizedDescription)
        }

        await loadConfiguration()
    }

    /// Writes the encoded settings to the daemon's configuration file so they survive a restart.
    ///
    /// arduino-cli's gRPC API only mutates settings in memory: `ConfigurationSave` returns them
    /// encoded and never touches the file, so the app has to persist them itself.
    private static func persistConfiguration(_ encodedSettings: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encodedSettings.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Downloads the package indexes so newly added board manager URLs take effect.
    func refreshBoardIndex() async throws {
        guard let coreService, let instance else { throw ArduinoCLIError.daemonNotRunning }

        boardIndexUpdate = .updating(message: nil)
        do {
            try await coreService.updateIndex(instance) { [weak self] message in
                Task { @MainActor in
                    guard let self, case .updating = self.boardIndexUpdate else { return }
                    self.boardIndexUpdate = .updating(message: message)
                }
            }
            boardIndexUpdate = .idle
        } catch {
            let failure = error as? ArduinoCLIError ?? .indexUpdateFailed(reason: error.localizedDescription)
            boardIndexUpdate = .failed(failure.errorDescription ?? "Couldn't update the board index.")
            throw failure
        }
    }

    /// Trims whitespace, drops empty entries, and removes duplicates while preserving order.
    static func normalizeBoardManagerURLs(_ urls: [String]) -> [String] {
        var seen = Set<String>()
        return urls
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }

    private static func encodeBoardManagerURLs(_ urls: [String]) throws -> String {
        let data = try JSONEncoder().encode(normalizeBoardManagerURLs(urls))
        return String(decoding: data, as: UTF8.self)
    }

    private func runSetup() {
        phase = .checking
        setupTask = Task { [service] in
            let stream = service.ensureReady()
            do {
                for try await progress in stream {
                    if Task.isCancelled { return }
                    apply(progress)
                }
                if !Task.isCancelled, !isReady {
                    phase = .failed(.daemonStartFailed(reason: "arduino-cli setup ended unexpectedly."))
                    setupTask = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(error as? ArduinoCLIError ?? .daemonStartFailed(reason: error.localizedDescription))
                setupTask = nil
            }
        }
    }

    private func apply(_ progress: ArduinoCLIProgress) {
        switch progress {
        case .checking:
            phase = .checking
        case .downloading:
            phase = .downloading
        case .extracting:
            phase = .extracting
        case .startingDaemon:
            phase = .startingDaemon
        case .initializing(let message):
            phase = .initializing(message: message)
        case .ready(let session):
            daemonPort = session.port
            instance = session.instance
            arduinoCLIVersion = session.version
            phase = .ready(port: session.port)
            setupTask = nil
        }
    }
}
