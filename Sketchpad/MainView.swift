//
//  ProjectsView.swift
//  Sketchpad
//
//  Created by perr on 9/5/2569 BE.
//

import SwiftUI
import SwiftData

struct MainView: View {
    @Environment(ArduinoController.self) private var controller
    
    @State private var version: String = ""
    @State private var selectedModule = 0
    
    @State private var selectedEditorMainView : String = ""
    
    @Binding var sketch: SketchDocument
    
    @Environment(\.documentConfiguration) private var docConfig

    var fileURL: URL? {
        docConfig?.fileURL
    }
    
    var body: some View {
        VStack {
            if controller.phase == .ready {
                SketchEditorView(document: $sketch)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
