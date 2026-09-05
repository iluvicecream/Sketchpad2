//
//  SketchpadApp.swift
//  Sketchpad
//
//  Created by perr on 9/5/2569 BE.
//

import SwiftUI

@main
struct BenchApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 500, height: 600)
        .windowResizability(.contentSize)
    }
}
