//
//  ArduinoDaemonServiceBox.swift
//  Sketchpad2
//
//  Created by perr on 10/28/2569 BE.
//

import SwiftUI
import os
internal import System

@Observable
final class ArduinoDaemonServiceBox {
    static let sharedBox = ArduinoDaemonServiceBox()
    private let logger = Logger(subsystem: "com.perr.Sketchpad2", category: "ArduinoDaemonBox")
    
    var boxState : ArduinoDaemonBoxState = .empty {
        didSet {
            onChangeBoxState(oldState: oldValue, newState: boxState)
        }
    }
    
    var changeCoreBoxState: ((CoreBoxState) -> Void)?
    
    var isDaemonReady = false
    var isDaemonRunning = false {
        didSet {
            onChangeDaemonRunningStatus(
                oldStatus: oldValue,
                newStatus: isDaemonRunning
            )
        }
    }
    var daemonProcess : Process?
    
    private init() {
        
    }
    
    func startTask() {
        logger.debug("daemon box start")
        changeCoreBoxState?(.daemonBoxStart)
        let didExistingDaemonInstallationExist = checkExistingDaemonInstallation()
        if !didExistingDaemonInstallationExist {
            Task {
                let isSuccess = await startInstallingDaemon()
                if !isSuccess {
                    changeCoreBoxState?(.daemonBoxError)
                    return
                }
            }
        }
        
        if !isDaemonRunning {
            let isSuccess = startDaemonProcess()
        }
    }
    
    //MARK: Installation
    private func checkExistingDaemonInstallation() -> Bool {
        let supportDirectory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "com.perr.Sketchpad2", directoryHint: .isDirectory)
        let extractionFolderURL = supportDirectory.appendingPathComponent(
            "daemon",
            isDirectory: true
        )
        let binaryURL = extractionFolderURL.appending(
            path: "arduino-cli",
            directoryHint: .notDirectory
        )
        let isBinaryExistAtUrl = FileManager.default.fileExists(
            atPath: binaryURL.path
        )
        logger.debug("is binary exist at url result \(isBinaryExistAtUrl)")
        return isBinaryExistAtUrl
    }
    
    private func startInstallingDaemon() async -> Bool {
        do {
            let (tempDownloadURL,response) = try await URLSession.shared.download(from: URL(string:"https://downloads.arduino.cc/arduino-cli/arduino-cli_latest_macOS_ARM64.tar.gz")!)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                boxState = .failedToDownloadDaemonBadResponse
                return false
            }
            
            let supportDirectory = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appending(path: "com.perr.Sketchpad2", directoryHint: .isDirectory)
            let extractionFolderURL = supportDirectory.appendingPathComponent(
                "daemon",
                isDirectory: true
            )
            let fileMgr = FileManager.default
            let tempDir = fileMgr.temporaryDirectory
            let archiveTargetURL = tempDir.appendingPathComponent("daemonarchive.tar.gz")
            
            if !fileMgr.fileExists(atPath: extractionFolderURL.path) {
                try fileMgr
                    .createDirectory(
                        at: extractionFolderURL,
                        withIntermediateDirectories: true
                    )
            }
            
            if fileMgr.fileExists(atPath: archiveTargetURL.path) {
                try fileMgr.removeItem(at: archiveTargetURL)
            }
            
            try fileMgr.moveItem(at: tempDownloadURL, to: archiveTargetURL)
            
            try await Task.detached(priority: .userInitiated) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
                process.arguments = [
                    "-xzf",
                    archiveTargetURL.path(percentEncoded: false),
                    "-C",
                    extractionFolderURL.path(percentEncoded: false)
                ]
                
                let errorPipe = Pipe()
                process.standardError = errorPipe
                
                try process.run()
                process.waitUntilExit()
                
                if process.terminationStatus != 0 {
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown shell error"
                    throw NSError(domain: "ShellError", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errorString])
                }
            }.value
            
            try? fileMgr.removeItem(at: archiveTargetURL)
            logger.info("install daemon succ")
            boxState = .installDaemonSucc
            return true
        } catch {
            logger.fault("install daemon failed reason \(error.localizedDescription)")
            boxState = .failedToInstallDaemon
            return false
        }
    }
    
    //MARK: Daemon Process
    private func startDaemonProcess() -> Bool {
        let supportDirectory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "com.perr.Sketchpad2", directoryHint: .isDirectory)
        let extractionFolderURL = supportDirectory.appendingPathComponent(
            "daemon",
            isDirectory: true
        )
        let binaryURL = extractionFolderURL.appending(
            path: "arduino-cli",
            directoryHint: .notDirectory
        )
        
        let process = Process()
        process.executableURL = binaryURL
        process.arguments = ["daemon"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
                
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                self.logger.debug(
                    "daemon pipe out \(output.trimmingCharacters(in: .whitespacesAndNewlines))"
                )
            }
        }
        
        do {
            try process.run()
            daemonProcess = process
            boxState = .daemonStarted
            isDaemonRunning = true
            logger.debug("daemon started with pid \(process.processIdentifier)")
        } catch {
            boxState = .daemonFailedToStarted
            isDaemonRunning = false
            logger.fault("daemon failed to started with reason \(error)")
            return false
        }
        return false
    }
    
    func stopDaemonProcess() {
        if daemonProcess?.isRunning == true {
            daemonProcess?.terminate()
            logger.info("stopped daemon")
            isDaemonRunning = false
        }
    }
    
    private func onChangeBoxState(oldState: ArduinoDaemonBoxState,newState : ArduinoDaemonBoxState) {
        logger
            .debug(
                "arduino daemon box state changed from \(oldState.rawValue) to \(newState.rawValue)"
            )
    }
    
    private func onChangeDaemonRunningStatus(oldStatus: Bool,newStatus : Bool) {
        logger
            .debug(
                "arduino daemon running status changed to \(newStatus)"
            )
    }
}

enum ArduinoDaemonBoxState : String {
    case empty
    case checkExistingDaemonInstallation
    case startInstallingDaemon
    case failedToDownloadDaemonBadResponse
    case failedToInstallDaemon
    case installDaemonSucc
    case startDaemonProcess
    case daemonStarted
    case daemonFailedToStarted
    case unknownError
}
