//
//  ProcessRunner.swift
//  Sketchpad2
//

import Darwin
import Foundation

/// Thin, non-isolated helpers for running helper executables and probing loopback sockets.
nonisolated enum ProcessRunner {

    /// Runs an executable to completion and returns its exit status with the combined output.
    nonisolated static func run(
        executable: URL,
        arguments: [String]
    ) async throws -> (status: Int32, output: String) {
        let context = ProcessContext()
        context.process.executableURL = executable
        context.process.arguments = arguments
        context.process.standardOutput = context.pipe
        context.process.standardError = context.pipe

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                context.process.terminationHandler = { process in
                    let data = context.pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(decoding: data, as: UTF8.self)
                    continuation.resume(returning: (process.terminationStatus, output))
                }

                do {
                    try context.process.run()
                } catch {
                    context.process.terminationHandler = nil
                    continuation.resume(
                        throwing: ArduinoCLIError.processLaunchFailed(
                            "\(executable.path(percentEncoded: false)): \(error.localizedDescription)"
                        )
                    )
                }
            }
        } onCancel: {
            if context.process.isRunning {
                context.process.terminate()
            }
        }
    }

    /// Launches a long-running daemon process, forwarding its output to `onOutput`.
    nonisolated static func launchDaemon(
        executable: URL,
        arguments: [String],
        onOutput: @escaping @Sendable (String) -> Void
    ) throws -> Process {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            for line in text.split(separator: "\n") {
                onOutput(String(line).trimmingCharacters(in: .whitespaces))
            }
        }

        try process.run()
        return process
    }

    /// Reserves a free loopback port by binding to port 0 and reading the assigned port back.
    nonisolated static func reserveEphemeralPort() throws -> Int {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw ArduinoCLIError.daemonStartFailed(reason: "Couldn't open a socket (errno \(errno)).")
        }
        defer { Darwin.close(descriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.bind(descriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw ArduinoCLIError.daemonStartFailed(reason: "Couldn't reserve a loopback port (errno \(errno)).")
        }

        var resolved = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &resolved) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                getsockname(descriptor, socketAddress, &length)
            }
        }
        guard nameResult == 0 else {
            throw ArduinoCLIError.daemonStartFailed(reason: "Couldn't read the loopback port (errno \(errno)).")
        }

        return Int(UInt16(bigEndian: resolved.sin_port))
    }

    /// Returns `true` when a TCP connection to the loopback port can be established.
    nonisolated static func canConnect(port: Int) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { Darwin.close(descriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.connect(descriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return connectResult == 0
    }
}

/// Holds the `Process`/`Pipe` pair so it can cross concurrency domains safely.
private nonisolated final class ProcessContext: @unchecked Sendable {
    let process = Process()
    let pipe = Pipe()
}
