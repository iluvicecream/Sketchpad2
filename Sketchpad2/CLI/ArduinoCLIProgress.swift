//
//  ArduinoCLIProgress.swift
//  Sketchpad2
//

import Foundation

/// A step reported by `ArduinoCLIService` while it prepares the arduino-cli daemon.
enum ArduinoCLIProgress: Sendable, Equatable {
    case checking
    case downloading
    case extracting
    case startingDaemon
    case ready(port: Int)
}

/// Failures surfaced while installing or launching arduino-cli.
enum ArduinoCLIError: LocalizedError, Sendable, Equatable {
    case downloadFailed(reason: String)
    case extractionFailed(output: String)
    case binaryNotRunnable(String)
    case daemonStartFailed(reason: String)
    case processLaunchFailed(String)

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let reason):
            "Couldn't download arduino-cli. \(reason)"
        case .extractionFailed(let output):
            "Couldn't extract arduino-cli. \(output)"
        case .binaryNotRunnable(let output):
            "The downloaded arduino-cli binary couldn't be run. \(output)"
        case .daemonStartFailed(let reason):
            "Couldn't start the arduino-cli daemon. \(reason)"
        case .processLaunchFailed(let output):
            "Couldn't launch a helper process. \(output)"
        }
    }
}
