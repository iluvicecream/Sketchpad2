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

    private let scratchDirectory: URL
    private let runtime = ArduinoCLIRuntime()
    private let logger = Logger(subsystem: "com.perr.Sketchpad2", category: "ArduinoCLI")

    init() {
        let supportDirectory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "com.perr.Sketchpad2", directoryHint: .isDirectory)
        self.scratchDirectory = supportDirectory.appending(path: "scratch", directoryHint: .isDirectory)
        self.binaryURL = supportDirectory.appending(path: "bin/arduino-cli", directoryHint: .notDirectory)
    }

    func ensureReady() -> AsyncThrowingStream<ArduinoCLIProgress, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) { [self] in
                do {
                    let port = try await start(yield: { continuation.yield($0) })
                    continuation.yield(.ready(port: port))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func shutdown() {
        guard let process = runtime.takeProcess(), process.isRunning else { return }
        logger.log("Stopping arduino-cli daemon")
        process.terminate()
    }

    // MARK: - Pipeline

    private func start(yield: @escaping @Sendable (ArduinoCLIProgress) -> Void) async throws -> Int {
        if let port = runtime.currentPort(), runtime.isDaemonRunning() {
            logger.log("Reusing the running arduino-cli daemon on port \(port)")
            return port
        }

        let task = runtime.joinOrStart { [self] in
            try await runPipeline(yield: yield)
        }
        return try await task.value
    }

    private func runPipeline(yield: @Sendable (ArduinoCLIProgress) -> Void) async throws -> Int {
        yield(.checking)
        let binary = try await ensureBinaryInstalled(yield: yield)
        yield(.startingDaemon)
        return try await launchDaemon(binary: binary)
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

        let process: Process
        do {
            process = try ProcessRunner.launchDaemon(
                executable: binary,
                arguments: ["daemon", "--port", String(port)]
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
}

/// Serializes access to the shared pipeline and daemon so concurrent callers cannot double-start.
private nonisolated final class ArduinoCLIRuntime: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var port: Int?
    private var startupTask: Task<Int, Error>?

    func currentPort() -> Int? {
        lock.withLock { port }
    }

    func isDaemonRunning() -> Bool {
        lock.withLock { process?.isRunning == true }
    }

    func record(process: Process, port: Int) {
        lock.withLock {
            self.process = process
            self.port = port
        }
    }

    func takeProcess() -> Process? {
        lock.withLock {
            let existing = process
            process = nil
            port = nil
            return existing
        }
    }

    func joinOrStart(_ body: @escaping @Sendable () async throws -> Int) -> Task<Int, Error> {
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
