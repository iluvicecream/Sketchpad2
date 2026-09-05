//
//  ArduinoCli.swift
//  Bench
//
//  Created by perr on 9/5/2569 BE.
//

import Foundation
import os

actor ArduinoCliDownloader {
    static let shared = ArduinoCliDownloader()
    
    private let installKey = "hasInstalledArduinoCli"
    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "com.perr.Bench", category: "ArduinoCliDownloader")
    
    var arduinoCliPath : URL {
        let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleId = Bundle.main.bundleIdentifier!
        return appSupportDir.appendingPathComponent(bundleId).appendingPathComponent("arduino-cli")
    }
    
    var isInstalled: Bool {
        let isFlag = UserDefaults.standard.bool(forKey: installKey)
        let isExists = fileManager.fileExists(atPath: arduinoCliPath.path)
        return isFlag && isExists
    }
    
    func ensureInstalled() async throws {
        guard !isInstalled else { return }
        
        try await downloadArduinoCli()
    }
    
    private func getArduinoCliURL() -> URL {
        #if arch(arm64)
        let arch = "ARM64"
        #else
        let arch = "64Bit"
        #endif
        return URL(
            string: "https://downloads.arduino.cc/arduino-cli/arduino-cli_latest_macOS_\(arch).tar.gz"
        )!
    }
    
    private func downloadArduinoCli() async throws {
        let url = getArduinoCliURL()
        logger.debug("getArduinoCliURL return \(url)")
        let (tempUrl,_) = try await URLSession.shared.download(from: url)
        logger.debug("tempUrl \(tempUrl)")
        try? fileManager.createDirectory(at: arduinoCliPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try extractTar(
            tar: tempUrl,
            to: arduinoCliPath.deletingLastPathComponent()
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: arduinoCliPath.path
        )
        UserDefaults.standard.set(true, forKey: installKey)
    }
    
    private func extractTar(tar: URL, to: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = [
            "-xzf",
            tar.path(percentEncoded: false),
            "-C",
            to.path(percentEncoded: false)
        ]
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "ArduinoCliDownloader",
                code: Int(process.terminationStatus)
            )
        }
    }
}
