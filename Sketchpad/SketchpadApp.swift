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
            StateView()
                .environment(controller)
        }
        .restorationBehavior(.disabled)
        
        WindowGroup(id:"bootstrap"){
            BootstrapView()
                .environment(controller)
                .opacity(controller.shouldBootstrapViewBeShown ? 1 : 0)
        }
        .windowStyle(.hiddenTitleBar)
        .restorationBehavior(.disabled)
        
        WindowGroup(id:"projects") {
            ProjectsView()
                .environment(controller)
        }
        .defaultSize(width: 900, height: 600)
        .restorationBehavior(.disabled)
    }
}
