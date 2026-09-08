//
//  SketchEditorView.swift
//  Sketchpad
//
//  Created by perr on 9/8/2569 BE.
//

import SwiftUI
import SwiftProtobuf

struct SketchEditorView: View {
    @Environment(ArduinoController.self) private var controller
    var mainDir: String
    
    @State private var sketch: Cc_Arduino_Cli_Commands_V1_Sketch?
    
    var body: some View {
        Group {
            Text(mainDir)
            if let sketch {
                SketchEditorRealView(sketch: sketch)
            } else {
                ProgressView("Loading sketch...")
            }
        }
        .task(id: mainDir) {
            sketch = try? await controller.loadSketch(mainDir: mainDir)
        }
    }
}

struct SketchEditorRealView: View {
    @Environment(ArduinoController.self) private var controller
    let sketch: Cc_Arduino_Cli_Commands_V1_Sketch
    
    var body: some View {
        VStack {
            Text("Editing: \(sketch.debugDescription)")
            // Build editor controls here
        }
    }
}
