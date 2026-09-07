//
//  ProjectsView.swift
//  Sketchpad
//
//  Created by perr on 9/5/2569 BE.
//

import SwiftUI

struct EditorView: View {
    @Environment(ArduinoController.self) private var controller
    
    @State private var version: String = ""
    
    var body: some View {
        NavigationSplitView {
            Text("Wow")
            Text("What")
        } detail : {
            Text(controller.arduinoInstance.id.description)
            Text(version).task {
                version = await controller.getVersion()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#Preview {
    EditorView()
}
