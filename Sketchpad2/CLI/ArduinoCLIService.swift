//
//  ArduinoCLIService.swift
//  Sketchpad2
//

import Darwin
import Foundation
import os

/// The work required to hand a running arduino-cli daemon to the rest of the app.
protocol ArduinoCLIServicing: Sendable {
    func ensureReady() -> AsyncThrowingStream<ArduinoCLIProgress, Error>
    var coreService: ArduinoCoreService? { get }
    /// The YAML configuration file the daemon reads at startup and the app writes when settings change.
    nonisolated var configurationFileURL: URL { get }
    func shutdown()
}

/// Owns everything about arduino-cli: the managed binary, the daemon process, and its port.
///
/// The service never touches SwiftUI state. It reports progress through the stream returned by
/// `ensureReady()` and lets `MainController` decide what that means for the UI.
nonisolated final class ArduinoCLIService: ArduinoCLIServicing {

    private nonisolated static let downloadURL = URL(
        string: "https://downloads.arduino.cc/arduino-cli/arduino-cli_latest_macOS_ARM64.tar.gz"
    )!

    private nonisolated static let daemonStartTimeout: Duration = .seconds(10)

    let binaryURL: URL

    /// arduino-cli's data directory, kept out of the shared `~/Library/Arduino15`.
    private let dataDirectory: URL
    private let scratchDirectory: URL
    private let runtime = ArduinoCLIRuntime()
    private let logger = Logger(subsystem: "com.perr.Sketchpad2", category: "ArduinoCLI")

    init() {
        let supportDirectory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "com.perr.Sketchpad2", directoryHint: .isDirectory)
        self.scratchDirectory = supportDirectory.appending(path: "scratch", directoryHint: .isDirectory)
        self.binaryURL = supportDirectory.appending(path: "bin/arduino-cli", directoryHint: .notDirectory)
        self.dataDirectory = supportDirectory.appending(path: "arduino15", directoryHint: .isDirectory)
    }

    func ensureReady() -> AsyncThrowingStream<ArduinoCLIProgress, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) { [self] in
                do {
                    let session = try await start(yield: { continuation.yield($0) })
                    continuation.yield(.ready(session))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func shutdown() {
        logger.log("Shutting down arduino-cli")
        let teardown = runtime.takeAll()

        if let coreService = teardown.coreService, let session = teardown.session {
            coreService.destroyInstance(session.instance)
        }

        teardown.coreService?.shutdown()
        if let process = teardown.process, process.isRunning {
            process.terminate()
        }
    }

    var coreService: ArduinoCoreService? {
        runtime.coreServiceInstance()
    }

    nonisolated var configurationFileURL: URL {
        dataDirectory.appending(path: "arduino-cli.yaml", directoryHint: .notDirectory)
    }

    // MARK: - Pipeline

    private func start(
        yield: @escaping @Sendable (ArduinoCLIProgress) -> Void
    ) async throws -> ArduinoCLISession {
        if let session = runtime.currentSession() {
            logger.log("Reusing the arduino-cli daemon on port \(session.port) with instance \(session.instance.id)")
            return session
        }

        let task = runtime.joinOrStart { [self] in
            try await runPipeline(yield: yield)
        }
        return try await task.value
    }

    private func runPipeline(yield: @escaping @Sendable (ArduinoCLIProgress) -> Void) async throws -> ArduinoCLISession {
        yield(.checking)
        let binary = try await ensureBinaryInstalled(yield: yield)

        let port: Int
        if let runningPort = runtime.runningPort() {
            port = runningPort
        } else {
            yield(.startingDaemon)
            port = try await launchDaemon(binary: binary)
        }

        let core: ArduinoCoreService
        do {
            core = try await sharedCoreService(port: port)
            runtime.record(coreService: core)
        } catch {
            runtime.shutdownDaemon()
            throw error
        }

        let instance: ArduinoCoreInstance
        do {
            instance = try await core.createInstance()
            logger.log("Created Arduino Core instance \(instance.id)")
        } catch {
            runtime.shutdownDaemon()
            throw ArduinoCLIError.instanceCreationFailed(reason: error.localizedDescription)
        }

        do {
            yield(.initializing(message: nil))
            try await core.initializeInstance(instance) { message in
                yield(.initializing(message: message))
            }
            logger.log("Initialized Arduino Core instance \(instance.id)")
        } catch {
            runtime.shutdownDaemon()
            throw error as? ArduinoCLIError
                ?? ArduinoCLIError.instanceInitializationFailed(reason: error.localizedDescription)
        }

        let version: String
        do {
            version = try await core.currentVersion()
            logger.log("arduino-cli version \(version, privacy: .public)")
        } catch {
            runtime.shutdownDaemon()
            throw ArduinoCLIError.versionRequestFailed(reason: error.localizedDescription)
        }

        let session = ArduinoCLISession(port: port, instance: instance, version: version)
        runtime.record(session: session)
        return session
    }

    // MARK: - Installation

    private func ensureBinaryInstalled(
        yield: @Sendable (ArduinoCLIProgress) -> Void
    ) async throws -> URL {
        let manager = FileManager.default
        if manager.isExecutableFile(atPath: binaryURL.path(percentEncoded: false)) {
            logger.log("Using the managed arduino-cli at \(self.binaryURL.path(percentEncoded: false), privacy: .public)")
            return binaryURL
        }

        try manager.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)

        yield(.downloading)
        let archiveURL = scratchDirectory.appending(path: "arduino-cli.tar.gz")
        try await download(to: archiveURL)

        yield(.extracting)
        let staging = scratchDirectory.appending(path: "staging", directoryHint: .isDirectory)
        try? manager.removeItem(at: staging)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer {
            try? manager.removeItem(at: staging)
            try? manager.removeItem(at: archiveURL)
        }

        let extract = try await ProcessRunner.run(
            executable: URL(filePath: "/usr/bin/tar"),
            arguments: [
                "-xzf",
                archiveURL.path(percentEncoded: false),
                "-C",
                staging.path(percentEncoded: false),
            ]
        )
        guard extract.status == 0 else {
            throw ArduinoCLIError.extractionFailed(output: extract.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let stagedBinary = staging.appending(path: "arduino-cli")
        guard manager.fileExists(atPath: stagedBinary.path(percentEncoded: false)) else {
            throw ArduinoCLIError.extractionFailed(output: "The archive didn't contain an arduino-cli binary.")
        }

        try? manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stagedBinary.path(percentEncoded: false))
        stagedBinary.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            _ = removexattr(path, "com.apple.quarantine", 0)
        }

        let validation = try await ProcessRunner.run(executable: stagedBinary, arguments: ["version"])
        guard validation.status == 0 else {
            throw ArduinoCLIError.binaryNotRunnable(
                String(validation.output.trimmingCharacters(in: .whitespacesAndNewlines).prefix(400))
            )
        }

        let binaryDirectory = binaryURL.deletingLastPathComponent()
        try manager.createDirectory(at: binaryDirectory, withIntermediateDirectories: true)
        try? manager.removeItem(at: binaryURL)
        try manager.moveItem(at: stagedBinary, to: binaryURL)

        logger.log("Installed arduino-cli at \(self.binaryURL.path(percentEncoded: false), privacy: .public)")
        return binaryURL
    }

    private func download(to destination: URL) async throws {
        do {
            let (temporaryURL, response) = try await URLSession.shared.download(from: Self.downloadURL)
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                throw ArduinoCLIError.downloadFailed(reason: "The server returned HTTP \(httpResponse.statusCode).")
            }

            let manager = FileManager.default
            try? manager.removeItem(at: destination)
            try manager.moveItem(at: temporaryURL, to: destination)
        } catch let error as ArduinoCLIError {
            throw error
        } catch {
            throw ArduinoCLIError.downloadFailed(reason: error.localizedDescription)
        }
    }

    // MARK: - Daemon

    private func launchDaemon(binary: URL) async throws -> Int {
        let port = try ProcessRunner.reserveEphemeralPort()
        logger.log("Starting arduino-cli daemon with data directory \(self.dataDirectory.path(percentEncoded: false), privacy: .public)")

        let process: Process
        do {
            process = try ProcessRunner.launchDaemon(
                executable: binary,
                arguments: [
                    "--config-dir",
                    dataDirectory.path(percentEncoded: false),
                    "--config-file",
                    configurationFileURL.path(percentEncoded: false),
                    "daemon",
                    "--port",
                    String(port),
                ]
            ) { [logger] line in
                guard !line.isEmpty else { return }
                logger.debug("daemon: \(line, privacy: .public)")
            }
        } catch {
            throw ArduinoCLIError.daemonStartFailed(reason: error.localizedDescription)
        }

        let deadline = ContinuousClock.now.advanced(by: Self.daemonStartTimeout)
        while ContinuousClock.now < deadline {
            if !process.isRunning {
                throw ArduinoCLIError.daemonStartFailed(
                    reason: "arduino-cli exited with status \(process.terminationStatus)."
                )
            }
            if ProcessRunner.canConnect(port: port) {
                runtime.record(process: process, port: port)
                logger.log("arduino-cli daemon listening on 127.0.0.1:\(port)")
                return port
            }
            try await Task.sleep(for: .milliseconds(100))
        }

        process.terminate()
        throw ArduinoCLIError.daemonStartFailed(
            reason: "Timed out waiting for the daemon to listen on 127.0.0.1:\(port)."
        )
    }

    // MARK: - Instance

    /// Opens the single gRPC connection every RPC shares.
    private func sharedCoreService(port: Int) async throws -> ArduinoCoreService {
        do {
            return try await MainActor.run {
                try ArduinoCoreService(port: port)
            }
        } catch {
            throw ArduinoCLIError.connectionFailed(reason: error.localizedDescription)
        }
    }
}

/// Serializes access to the shared pipeline and daemon so concurrent callers cannot double-start.
private nonisolated final class ArduinoCLIRuntime: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var port: Int?
    private var session: ArduinoCLISession?
    private var coreService: ArduinoCoreService?
    private var startupTask: Task<ArduinoCLISession, Error>?

    func currentSession() -> ArduinoCLISession? {
        lock.withLock { session }
    }

    func runningPort() -> Int? {
        lock.withLock {
            guard process?.isRunning == true else { return nil }
            return port
        }
    }

    func record(process: Process, port: Int) {
        lock.withLock {
            self.process = process
            self.port = port
        }
    }

    func record(session: ArduinoCLISession) {
        lock.withLock { self.session = session }
    }

    func record(coreService: ArduinoCoreService) {
        lock.withLock { self.coreService = coreService }
    }

    func coreServiceInstance() -> ArduinoCoreService? {
        lock.withLock { coreService }
    }

    func shutdownDaemon() {
        let teardown = takeAll()

        teardown.coreService?.shutdown()
        if let process = teardown.process, process.isRunning {
            process.terminate()
        }
    }

    /// Removes and returns everything the runtime is holding.
    func takeAll() -> (
        process: Process?,
        coreService: ArduinoCoreService?,
        session: ArduinoCLISession?
    ) {
        lock.withLock {
            let teardown = (process, coreService, session)
            process = nil
            port = nil
            session = nil
            coreService = nil
            return teardown
        }
    }

    func joinOrStart(
        _ body: @escaping @Sendable () async throws -> ArduinoCLISession
    ) -> Task<ArduinoCLISession, Error> {
        lock.withLock {
            if let existing = startupTask {
                return existing
            }
            let task = Task.detached(priority: .userInitiated) { [self] in
                defer { clearStartupTask() }
                return try await body()
            }
            startupTask = task
            return task
        }
    }

    private func clearStartupTask() {
        lock.withLock { startupTask = nil }
    }
}
