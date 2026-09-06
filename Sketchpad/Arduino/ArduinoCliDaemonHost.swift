//
//  ArduinoCliDaemonHost.swift
//  Sketchpad
//
//  Created by perr on 9/5/2569 BE.
//

import Foundation
import os
import GRPCNIOTransportHTTP2
import GRPCCore

actor ArduinoCliDaemonHost {
    static let shared = ArduinoCliDaemonHost()
    
    private var daemonProcess: Process?
    private(set) var isDaemonRunning: Bool = false
    private let logger = Logger(subsystem: "com.perr.Sketchpad", category: "ArduinoCliDaemonHost")
    
    private var stdinPipe: Pipe?

    //gRPC details
    let port: Int = 50052
    private(set) var isGRPCReady : Bool = false
    private var gRPCLifecycleTask : Task<Void,Never>?
    private var logReadingTask: Task<Void, Never>?
    
    //gRPC client
    private(set) var arduinoCoreClient : Cc_Arduino_Cli_Commands_V1_ArduinoCoreService.Client<HTTP2ClientTransport.Posix>?
    
    
    enum DaemonError: Error,LocalizedError {
        case clinotInstalled
        case daemonAlreadyRunning
        case daemonFailedToStart
        
        var errorDescription: String? {
            switch self {
            case .clinotInstalled : return "Arduino CLI not installed"
            case .daemonAlreadyRunning : return "Arduino daemon already running"
            case .daemonFailedToStart : return "Arduino daemon failed to start"
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
        
        let stdinPipe = Pipe()
        process.standardInput = stdinPipe
        self.stdinPipe = stdinPipe

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
        
        try await waitForDaemonReady(pipe: pipe)
        try await setupGRPC()
    }
    
    private func waitForDaemonReady(pipe : Pipe) async throws {
        logReadingTask?.cancel()
        
        return try await withCheckedThrowingContinuation { continuation in
            logReadingTask = Task {
                var isReady = false
                do {
                    for try await line in pipe.fileHandleForReading.bytes.lines {
                        self.logger.debug("Daemon: \(line)")
                        
                        if !isReady && line.contains("Daemon is now listening on") {
                            isReady = true
                            continuation.resume()
                        }
                    }
                
                } catch {
                    self.logger.error("Daemon not ready")
                    if !isReady {
                        continuation.resume(throwing: DaemonError.daemonFailedToStart)
                    }
                }
            }
        }
    }
    
    private func setupGRPC() async throws {
        gRPCLifecycleTask?.cancel()
        
        gRPCLifecycleTask = Task {
            do {
                try await withGRPCClient(
                    transport: .http2NIOPosix(
                        target: .dns(host: "127.0.0.1",port: port),
                        transportSecurity: .plaintext
                    )
                ) { rawClient in
                    self.isGRPCReady = true
                    
                    // createServiceClient
                    arduinoCoreClient = await Cc_Arduino_Cli_Commands_V1_ArduinoCoreService
                        .Client(wrapping: rawClient)
                    
                    self.logger.debug("gRPC ready")
                    
                    try await Task.sleep(nanoseconds: UInt64.max)
                }
            } catch {
                if !Task.isCancelled {
                    self.logger.error("Failed to start gRPC: \(error)")
                    self.cleanupGRPCState()
                }
            }
        }
    }
    
    private func cleanupGRPCState() {
        self.isGRPCReady = false
    }
    
    func stop() {
        daemonProcess?.terminate()
    }
    
    private func handleTermination() {
        logger.debug("Arduino daemon stopped")
        cleanupState()
    }
    
    private func cleanupState() {
            isDaemonRunning = false
            isGRPCReady = false
            daemonProcess = nil
            arduinoCoreClient = nil
        
            stdinPipe = nil
            
            gRPCLifecycleTask?.cancel()
            gRPCLifecycleTask = nil
            
            logReadingTask?.cancel()
            logReadingTask = nil
    }
}
