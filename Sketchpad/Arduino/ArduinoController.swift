//
//  ArduinoController.swift
//  Sketchpad
//
//  Created by perr on 9/5/2569 BE.
//

import Foundation
import os
import SwiftProtobuf

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
    var arduinoInstance : Cc_Arduino_Cli_Commands_V1_Instance = Cc_Arduino_Cli_Commands_V1_Instance()
    private var isCreatingInstance = false
    
    var isBootstrapped: Bool = false
    var shouldBootstrapViewBeShown : Bool = false
    
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
 
    private func createArduinoInstance() async {
        if arduinoInstance.id != 0 {
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
            self.arduinoInstance = response.instance
            self.logger.info("Successfully created Arduino instance with ID: \(response.instance.id)")
            phase = .ready
            
            
        } catch {
            self.logger.error("Failed to create instance via gRPC: \(error)")
            phase = .failed(error.localizedDescription)
        }
    }
    
    func getVersion() async -> String {
        guard await ArduinoCliDaemonHost.shared.isGRPCReady,
            let client = await ArduinoCliDaemonHost.shared.arduinoCoreClient else {
            logger.error("gRPC client is nil or not ready.")
            phase = .failed("gRPC connection unavailable")
            return "Unknown"
        }
        do {
            let request = Cc_Arduino_Cli_Commands_V1_VersionRequest()
            let response = try await client.version(request)
            logger.debug("VersionResponse version: \(response.version)")
            return response.version
            
        } catch {
            self.logger.error("Failed to request version")
            return "Unknown"
        }
    }
    
    func createSketch(sketchName : String,sketchDir: String,override: Bool = false) async -> String {
        guard await ArduinoCliDaemonHost.shared.isGRPCReady,
            let client = await ArduinoCliDaemonHost.shared.arduinoCoreClient else {
            logger.error("gRPC client is nil or not ready.")
            phase = .failed("gRPC connection unavailable")
            return "Unknown"
        }
        do {
            var request = Cc_Arduino_Cli_Commands_V1_NewSketchRequest()
            request.overwrite = override
            request.sketchDir = sketchDir
            request.sketchName = sketchName
            let response = try await client.newSketch(request)
            logger.debug("NewSketchResponse mainFile: \(response.mainFile)")
            return response.mainFile
            
        } catch {
            self.logger.error("Failed to request version")
            return "Unknown"
        }
    }
    
    func loadSketch(mainDir: String) async throws -> Cc_Arduino_Cli_Commands_V1_Sketch {
        guard await ArduinoCliDaemonHost.shared.isGRPCReady,
            let client = await ArduinoCliDaemonHost.shared.arduinoCoreClient else {
            logger.error("gRPC client is nil or not ready.")
            phase = .failed("gRPC connection unavailable")
            throw NSError(domain: "AppError", code: 500, userInfo: [NSLocalizedDescriptionKey: "Something went wrong."])
        }
        do {
            var request = Cc_Arduino_Cli_Commands_V1_LoadSketchRequest()
            request.sketchPath = mainDir
            let response = try await client.loadSketch(request)
            logger.debug("NewSketchResponse sketch: \(response.sketch.debugDescription)")
            return response.sketch
            
        } catch {
            self.logger.error("Failed to request version")
            throw NSError(domain: "AppError", code: 500, userInfo: [NSLocalizedDescriptionKey: "Something went wrong."])
        }
    }
}
