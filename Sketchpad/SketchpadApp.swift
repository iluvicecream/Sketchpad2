//
//  SketchpadApp.swift
//  Sketchpad
//
//  Created by perr on 9/5/2569 BE.
//

import SwiftUI

@main
struct BenchApp: App {
    @State private var controller = ArduinoController()
    
    var body: some Scene {
        WindowGroup(){
            if controller.phase == .ready {
                ProjectsView()
                    .environment(controller)
            }else {
                BootstrapView()
                    .environment(controller)
                    .task {
                        await controller.bootstrap()
                    }
            }
        }
        .defaultSize(width:1000,height:700)
        .windowStyle(.hiddenTitleBar)
        .restorationBehavior(.disabled)
    }
}
