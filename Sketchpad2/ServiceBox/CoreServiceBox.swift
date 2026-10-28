//
//  CoreServiceBox.swift
//  Sketchpad2
//
//  Created by perr on 10/28/2569 BE.
//

import SwiftUI
import os

@Observable
@MainActor
final class CoreServiceBox {
    static let sharedBox = CoreServiceBox()
    
    private let logger = Logger(subsystem: "com.perr.Sketchpad2", category: "CoreBox")
    
    // child box
    var daemonBox = ArduinoDaemonServiceBox.sharedBox
    var rpcBox = ArduinoRPCServiceBox.sharedBox
    
    var boxState : CoreBoxState = .empty {
        didSet {
            onChangeBoxState(oldState: oldValue, newState: boxState)
        }
    }
    
    // arduino
    var instance : Cc_Arduino_Cli_Commands_V1_Instance?
    
    private init() {
        daemonBox.changeCoreBoxState = { [weak self] newState in
            self?.boxState = newState
        }
        daemonBox.daemonRunningSignalToRpcBox = { [weak self] newState in
            self?.rpcBox.gotSignalFromDaemonBox(signalStatus: newState)
        }
        rpcBox.setInstance = { [weak self] newState in
            self?.instance = newState
        }
    }
    
    func startTask() {
        logger.debug("core box start")
        daemonBox.startTask()
    }
    
    private func onChangeBoxState(oldState: CoreBoxState,newState: CoreBoxState){
        logger
            .debug(
                "core box state changed from \(oldState.rawValue) to \(newState.rawValue)"
            )
    }
    
    isolated deinit {
        daemonBox.stopDaemonProcess()
    }
}

enum CoreBoxState: String {
    case empty
    case daemonBoxStart
    case daemonBoxWorking
    case daemonBoxEnd
    case daemonBoxError
}
