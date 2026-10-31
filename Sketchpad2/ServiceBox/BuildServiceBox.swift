//
//  BuildServiceBox.swift
//  Sketchpad
//
//  Created by perr on 11/1/2569 BE.
//
import SwiftUI
import os
import SwiftProtobuf
import GRPCCore

@Observable
final class BuildServiceBox {
    static let sharedBox = BuildServiceBox()
    private let logger = Logger(subsystem: "com.perr.Sketchpad2", category: "BuildBox")
    
    var boardLists : [Cc_Arduino_Cli_Commands_V1_BoardListItem] = []
    var detectedPorts: [Cc_Arduino_Cli_Commands_V1_DetectedPort] = []
    var consoleOutput: String = ""
    var isBuilding: Bool = false
    var isUploading: Bool = false
    
    var rpcBox = ArduinoRPCServiceBox.sharedBox
    
    func boardList() async throws {
        guard let instance = rpcBox.instance, let client = rpcBox.client else {
            logger.error("RPC client or instance is nil")
            return
        }
        
        let req = Cc_Arduino_Cli_Commands_V1_BoardListRequest.with {
            $0.instance = rpcBox.instance!
        }
        
        let resp = try await rpcBox.client?.boardList(req)
            //logger.debug("board list \(resp.debugDescription)")
        let sortedPorts = resp!.ports.sorted(
            by: { $0.port.address < $1.port.address
            })
        detectedPorts = sortedPorts
        return
    }
    
    func boardListAll() async throws {
        logger.debug("board list all")
        guard let instance = rpcBox.instance, let client = rpcBox.client else {
            logger.error("RPC client or instance is nil")
            return
        }
        
        let req = Cc_Arduino_Cli_Commands_V1_BoardListAllRequest.with {
            $0.instance = rpcBox.instance!
            $0.includeHiddenBoards = false
        }
        
        var options = CallOptions.defaults
        options.maxRequestMessageBytes = 100 * 1024 * 1024
        options.maxResponseMessageBytes = 100 * 1024 * 1024
        
        let resp = try await rpcBox.client?.boardListAll(
            req,
            options: options
        )
        logger.debug("board list all \(resp.debugDescription)")
        let sortedPorts = resp!.boards.sorted(
            by: { $0.name < $1.name
            })
        boardLists = sortedPorts
        return
    }
    
    private func prepareSketchDirectory(code: String) throws -> String {
        let buildDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SketchpadBuild", isDirectory: true)
            .appendingPathComponent("Sketch", isDirectory: true)
        try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
        let inoURL = buildDir.appendingPathComponent("Sketch.ino")
        try code.write(to: inoURL, atomically: true, encoding: .utf8)
        return buildDir.path(percentEncoded: false)
    }
    
    @MainActor
    @discardableResult
    func compile(code: String, fqbn: String) async -> Bool {
        guard let instance = rpcBox.instance, let client = rpcBox.client else {
            consoleOutput = "Error: RPC client or instance is not ready.\n"
            return false
        }
        
        guard !fqbn.isEmpty else {
            consoleOutput = "Error: Please select a board first.\n"
            return false
        }
        
        isBuilding = true
        defer { isBuilding = false }
        consoleOutput = "Compiling for \(fqbn)...\n"
        
        do {
            let sketchPath = try prepareSketchDirectory(code: code)
            let req = Cc_Arduino_Cli_Commands_V1_CompileRequest.with {
                $0.instance = rpcBox.instance!
                $0.fqbn = fqbn
                $0.sketchPath = sketchPath
            }
            var options = CallOptions.defaults
            options.maxRequestMessageBytes = 100 * 1024 * 1024
            options.maxResponseMessageBytes = 100 * 1024 * 1024
            return try await client.compile(req,options: options) { response in
                for try await msg in response.messages {
                    switch msg.message {
                    case .outStream(let data), .errStream(let data):
                        let text = String(decoding:data,as:UTF8.self)
                        await MainActor.run {
                            self.consoleOutput += text
                        }
                    case .progress(let progress):
                        self.logger
                            .debug(
                                "compile progress : \(progress.debugDescription)"
                            )
                    case .result:
                        break
                    case .none :
                        break
                    }
                }
                await MainActor.run {self.consoleOutput += "\nDone compiling.\n"}
                return true
            }
        } catch {
            consoleOutput += "\nCompilation failed: \(error.localizedDescription)\n"
            logger.error("compile error: \(error)")
            return false
        }
    }
    
    @MainActor
    func upload(code: String, fqbn: String, portAddress: String) async {
        guard let instance = rpcBox.instance, let client = rpcBox.client else { return }
        guard let detected = detectedPorts.first(where: { $0.port.address == portAddress }) else {
            consoleOutput = "Error: Selected port \(portAddress) is no longer available.\n"
            return
        }
        
        let compiledOK = await compile(code: code, fqbn: fqbn)
        guard compiledOK else { return }
        
        isUploading = true
        defer { isUploading = false }
        consoleOutput += "\nUploading to \(portAddress)...\n"
        
        do {
            let sketchPath = try prepareSketchDirectory(code: code)
            let req = Cc_Arduino_Cli_Commands_V1_UploadRequest.with {
                $0.instance = rpcBox.instance!
                $0.fqbn = fqbn
                $0.sketchPath = sketchPath
                $0.port = detected.port
                $0.verify = true
            }
            var options = CallOptions.defaults
            options.maxRequestMessageBytes = 100 * 1024 * 1024
            options.maxResponseMessageBytes = 100 * 1024 * 1024
            try await client.upload(req,options: options) { response in
                for try await msg in response.messages {
                    switch msg.message {
                    case .outStream(let data), .errStream(let data):
                        let text = String(decoding: data, as: UTF8.self)
                        await MainActor.run {self.consoleOutput += text}
                    case .result(let res):
                        self.logger
                            .debug("upload result: \(res.debugDescription)")
                    case .none:
                        break
                    }
                }
            }
            consoleOutput += "\nDone uploading.\n"
        } catch {
            consoleOutput += "\nUpload Failed: \(error.localizedDescription)\n"
        }
    }
}
