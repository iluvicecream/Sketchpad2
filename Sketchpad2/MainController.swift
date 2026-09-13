//
//  MainController.swift
//  Sketchpad2
//

import AppKit
import Foundation
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

    /// The platform installation in flight, if any.
    enum PlatformInstall: Equatable {
        case idle
        case installing(platformID: String, message: String?)
        case failed(platformID: String, message: String)
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

    /// The platform installation currently in flight, if any.
    private(set) var platformInstall: PlatformInstall = .idle

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
        platformInstall = .idle
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

    /// Loads the platforms the indexes offer, so the Board Manager can browse and install them.
    /// Safe to call whenever the Board Manager window opens.
    func loadBoards() async {
        guard let coreService, let instance else { return }

        boardCatalog = .loading
        if case .failed = platformInstall {
            platformInstall = .idle
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

        platformInstall = .installing(platformID: platform.id, message: nil)
        do {
            try await coreService.platformInstall(
                instance: instance,
                platformID: platform.id,
                version: version
            ) { [weak self] message in
                Task { @MainActor in
                    guard let self, case .installing(let id, _) = self.platformInstall, id == platform.id else { return }
                    self.platformInstall = .installing(platformID: id, message: message)
                }
            }
            platformInstall = .idle
            await loadBoards()
        } catch {
            let failure = error as? ArduinoCLIError ?? .platformInstallFailed(reason: error.localizedDescription)
            platformInstall = .failed(
                platformID: platform.id,
                message: failure.errorDescription ?? "Couldn't install the platform."
            )
        }
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
