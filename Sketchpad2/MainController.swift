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

    private(set) var phase: Phase = .idle
    private(set) var daemonPort: Int?
    /// The Arduino Core instance created on the daemon via the `Create` RPC.
    private(set) var instance: ArduinoCoreInstance?

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
        phase = .idle
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
        case .ready(let port, let instance):
            daemonPort = port
            self.instance = instance
            phase = .ready(port: port)
            setupTask = nil
        }
    }
}
