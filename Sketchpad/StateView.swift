//
//  StateView.swift
//  Sketchpad
//
//  Created by perr on 9/6/2569 BE.
//
import SwiftUI
import os

struct StateView : View {
    @Environment(ArduinoController.self) private var controller
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    private let logger: Logger = Logger(subsystem: "com.perr.Sketchpad", category: "StateView")
    
    var body : some View {
        EmptyView()
            .hidden()
            .task {
                if controller.isBootstrapped {
                    logger.debug("bootstrap true")
                    openWindow(id:"projects")
                    dismiss()
                    return
                }else {
                    logger.debug("hope this get logged")
                    openWindow(id:"bootstrap")
                    dismiss()
                    return
                }
            }
    }
}
