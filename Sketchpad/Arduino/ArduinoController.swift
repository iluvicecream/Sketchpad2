//
//  ArduinoController.swift
//  Sketchpad
//
//  Created by perr on 9/5/2569 BE.
//

import Foundation
import os

@MainActor @Observable final class ArduinoController {
    enum Phase : Equatable {
        case checking,
             installing,
             startingDaemon,
             ready,
             stopped,
             failed(String)
    }
    
    private let logger: Logger = Logger(subsystem: "com.perr.Sketchpad", category: "ArduinoController")
    
    private(set)var phase: Phase = .checking
    private(set)var isDaemonRunning : Bool = false
    
    //Arduino Core
    private(set) var coreInstanceId: Int32?
    private var isCreatingInstance = false
    
    var isBootstrapped: Bool = false 
    
    func bootstrap() async {
        logger.debug(".bootstrap")
        let isArduinoCliInstalled = await ArduinoCliDownloader.shared.isInstalled
        if(!isArduinoCliInstalled){
            logger.error("Arduino CLI is not installed")
            do{
                phase = .installing
                try await ArduinoCliDownloader.shared.ensureInstalled()
                logger.info("EnsureInstalled completed")
                // Bootstrap again
                await bootstrap()
            } catch {
                phase = .failed(error.localizedDescription)
                logger.error("Arduino CLI installation failed: \(error)")
            }
            return
        }
        do {
            phase = .startingDaemon
            try await ArduinoCliDaemonHost.shared.start()
            if await (ArduinoCliDaemonHost.shared.isDaemonRunning){
                await createArduinoInstance()
            }
        } catch ArduinoCliDaemonHost.DaemonError.daemonAlreadyRunning {
            await createArduinoInstance()
            logger.debug("Arduino daemon already running, continuing")
        } catch {
            phase = .failed(error.localizedDescription)
            logger.error("Failed to start Arduino daemon: \(error)")
        }
    }
    
    //Arduino Core Call
    private func createArduinoInstance() async {
        if coreInstanceId != nil {
            phase = .ready
            return
        }
        guard !isCreatingInstance else { return }
        isCreatingInstance = true
        defer { isCreatingInstance = false }

        while await !ArduinoCliDaemonHost.shared.isGRPCReady {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        
        guard await ArduinoCliDaemonHost.shared.isGRPCReady,
              let client = await ArduinoCliDaemonHost.shared.arduinoCoreClient else {
            logger.error("gRPC client is nil or not ready.")
            phase = .failed("gRPC connection unavailable")
            return
        }
        
        do {
            let request = Cc_Arduino_Cli_Commands_V1_CreateRequest()
            let response = try await client.create(request)
            self.coreInstanceId = response.instance.id
            self.logger.info("Successfully created Arduino instance with ID: \(response.instance.id)")
            phase = .ready
            
            
        } catch {
            self.logger.error("Failed to create instance via gRPC: \(error)")
            phase = .failed(error.localizedDescription)
        }
    }
}
