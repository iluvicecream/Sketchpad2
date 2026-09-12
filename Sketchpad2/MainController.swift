//
//  MainController.swift
//  Sketchpad2
//

import AppKit
import Foundation
import Observation

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
        case ready(port: Int)
        case failed(ArduinoCLIError)
    }

    /// Where the app is in the board index refresh flow.
    enum BoardIndexUpdate: Equatable {
        case idle
        case updating(message: String?)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var daemonPort: Int?
    /// The Arduino Core instance created on the daemon via the `Create` RPC.
    private(set) var instance: ArduinoCoreInstance?

    /// The arduino-cli version reported by the daemon at startup.
    private(set) var arduinoCLIVersion: String?

    /// The daemon configuration, fetched when the Settings window opens.
    private(set) var configuration: ArduinoConfiguration?

    /// The board index refresh triggered after board manager URLs are saved.
    private(set) var boardIndexUpdate: BoardIndexUpdate = .idle

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
        boardIndexUpdate = .idle
        phase = .idle
    }

    /// Fetches the daemon configuration so it can be inspected. Safe to call whenever Settings opens.
    func loadConfiguration() async {
        guard let coreService else { return }

        do {
            configuration = try await coreService.configuration()
        } catch {
            // `ArduinoCoreService` logs failures alongside the rest of the daemon traffic.
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
            try await coreService.configurationSave(settingsFormat: "yaml")
        } catch {
            throw ArduinoCLIError.configurationSaveFailed(reason: error.localizedDescription)
        }

        await loadConfiguration()
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
        case .ready(let session):
            daemonPort = session.port
            instance = session.instance
            arduinoCLIVersion = session.version
            phase = .ready(port: session.port)
            setupTask = nil
        }
    }
}
