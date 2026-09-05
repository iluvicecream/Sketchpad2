//
//  ArduinoCliDaemonHost.swift
//  Sketchpad
//
//  Created by perr on 9/5/2569 BE.
//

import Foundation
import os

actor ArduinoCliDaemonHost {
    static let shared = ArduinoCliDaemonHost()
    
    private var daemonProcess: Process?
    private(set) var isDaemonRunning: Bool = false
    private let logger = Logger(subsystem: "com.perr.Sketchpad", category: "ArduinoCliDaemonHost")
    
        //gRPC details
    let port: Int = 50051
    
    enum DaemonError: Error,LocalizedError {
        case clinotInstalled
        case daemonAlreadyRunning
        
        var errorDescription: String? {
            switch self {
            case .clinotInstalled : return "Arduino CLI not installed"
            case .daemonAlreadyRunning : return "Arduino daemon already running"
            }
        }
    }
    
    func start() async throws {
        guard !isDaemonRunning else { throw DaemonError.daemonAlreadyRunning }
        
        let arduinoCliURL = await ArduinoCliDownloader.shared.arduinoCliPath
        
        guard FileManager.default.fileExists(atPath: arduinoCliURL.path) else {
            throw DaemonError.clinotInstalled
        }
        
        let process = Process()
        process.executableURL = arduinoCliURL
        process.arguments = ["daemon","--port","\(port)"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        process.terminationHandler = { [weak self] _ in
            Task {
                await self?.handleTermination()
            }
        }
        
        try process.run()
        daemonProcess = process
        isDaemonRunning = true
        
        Task {
            do {
                for try await line in pipe.fileHandleForReading.bytes.lines {
                    logger.debug("ArduinoDaemonPipe : \(line)")
                }
            } catch {
                logger.error("Failed to read Arduino daemon pipe: \(error)")
            }
        }
    }
    
    func stop() {
        guard isDaemonRunning, let process = daemonProcess else { return }
        process.terminate()
        
        daemonProcess = nil
        isDaemonRunning = false
    }
    
    private func handleTermination() {
        isDaemonRunning = false
        daemonProcess = nil
        logger.debug("Arduino daemon stopped")
    }
}
