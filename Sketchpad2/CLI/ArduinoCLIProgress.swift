//
//  ArduinoCLIProgress.swift
//  Sketchpad2
//

import Foundation

/// The Arduino Core instance created on the daemon, as returned by the `Create` RPC.
typealias ArduinoCoreInstance = Cc_Arduino_Cli_Commands_V1_Instance

/// Everything the app keeps from a successful startup: the daemon port, its Arduino Core
/// instance, and the arduino-cli version the daemon reports.
struct ArduinoCLISession: Sendable, Equatable {
    let port: Int
    let instance: ArduinoCoreInstance
    let version: String
}

/// A step reported by `ArduinoCLIService` while it prepares the arduino-cli daemon.
enum ArduinoCLIProgress: Sendable, Equatable {
    case checking
    case downloading
    case extracting
    case startingDaemon
    case ready(ArduinoCLISession)
}

/// Failures surfaced while installing or launching arduino-cli.
enum ArduinoCLIError: LocalizedError, Sendable, Equatable {
    case downloadFailed(reason: String)
    case extractionFailed(output: String)
    case binaryNotRunnable(String)
    case daemonStartFailed(reason: String)
    case connectionFailed(reason: String)
    case instanceCreationFailed(reason: String)
    case versionRequestFailed(reason: String)
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
        case .connectionFailed(let reason):
            "Couldn't connect to the arduino-cli daemon. \(reason)"
        case .instanceCreationFailed(let reason):
            "Couldn't create an Arduino Core instance. \(reason)"
        case .versionRequestFailed(let reason):
            "Couldn't read the arduino-cli version. \(reason)"
        case .processLaunchFailed(let output):
            "Couldn't launch a helper process. \(output)"
        }
    }
}
