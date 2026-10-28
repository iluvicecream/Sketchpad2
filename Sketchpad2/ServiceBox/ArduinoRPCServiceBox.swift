//
//  ArduinoRPCServiceBox.swift
//  Sketchpad2
//
//  Created by perr on 10/28/2569 BE.
//

import SwiftUI
import os
import GRPCNIOTransportHTTP2
import GRPCCore
import SwiftProtobuf

@Observable
@MainActor
final class ArduinoRPCServiceBox {
    static let sharedBox = ArduinoRPCServiceBox()
    
    private let logger = Logger(subsystem: "com.perr.Sketchpad2", category: "ArduinoRPCBox")
    
    private var transport: HTTP2ClientTransport.Posix?
    private var client: Cc_Arduino_Cli_Commands_V1_ArduinoCoreService.Client<HTTP2ClientTransport.Posix>?
    
    var setInstance: ((Cc_Arduino_Cli_Commands_V1_Instance) -> Void)?
    
    var boxState : ArduinoRPCBoxState = .empty {
        didSet {
            onChangeBoxState(oldState: oldValue, newState: boxState)
        }
    }
    
    private init() {

    }
    
    func gotSignalFromDaemonBox(signalStatus : Bool) {
        logger.debug("got signal \(signalStatus)")
        if signalStatus {
            startTask()
        }
    }
    
    func startTask() {
        logger.debug("arduino rpc box start")
        do {
            transport = try HTTP2ClientTransport.Posix(
                target: .ipv4(address: "127.0.0.1", port: 50051),
                transportSecurity: .plaintext
            )
            
            let baseClient = GRPCClient(transport: transport!)
            client = Cc_Arduino_Cli_Commands_V1_ArduinoCoreService
                .Client(wrapping: baseClient)
            
            Task.detached {
                do {
                    try await baseClient.runConnections()
                } catch {
                    self.logger.error("RPC client transport failed \(error)")
                }
            }
        } catch {
            boxState = .unknownError
            logger.error("rpc setup failed reason \(error)")
            return
        }
        
        // create instance
        Task {
            do {
                let rsp = try await create()
                logger.debug("create rsp \(rsp.debugDescription)")
                setInstance!(rsp.instance)
            } catch {
                logger.error("failed to setup rpc instance \(error)")
                return
            }
        }
    }
    
    //MARK: RPC Bolierplate
    public func create() async throws -> Cc_Arduino_Cli_Commands_V1_CreateResponse {
         guard let client = self.client else {
             throw NSError(domain: "ArduinoRPCBox", code: 1, userInfo: [NSLocalizedDescriptionKey: "cannot get client"])
         }
        
        var options = CallOptions.defaults
        options.waitForReady = true

        var request = Cc_Arduino_Cli_Commands_V1_CreateRequest()
         
        let response = try await client.create(request,options: options)
        return response
     }
    
    private func onChangeBoxState(oldState: ArduinoRPCBoxState,newState: ArduinoRPCBoxState){
        logger
            .debug(
                "arduino rpc box state changed from \(oldState.rawValue) to \(newState.rawValue)"
            )
    }
}

enum ArduinoRPCBoxState: String {
    case empty
    case unknownError
}
