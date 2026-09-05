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
    
    func bootstrap() async {
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
                phase = .ready
            }
        } catch ArduinoCliDaemonHost.DaemonError.daemonAlreadyRunning {
            phase = .ready
            logger.debug("Arduino daemon already running, continuing")
        } catch {
            phase = .failed(error.localizedDescription)
            logger.error("Failed to start Arduino daemon: \(error)")
        }
    }
}
