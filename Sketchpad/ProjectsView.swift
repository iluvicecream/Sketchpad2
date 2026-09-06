//
//  ProjectsView.swift
//  Sketchpad
//
//  Created by perr on 9/5/2569 BE.
//

import SwiftUI

struct ProjectsView: View {
    @Environment(ArduinoController.self) private var controller
    
    @State private var version: String = ""
    
    var body: some View {
        if controller.phase != .ready {
            StateView()
                .environment(controller)
        }else {
            Text("arduino core id = \(controller.coreInstanceId?.description ?? "nvm arduino never got create")")
            Text(version)
                .task {
                    version = await controller.getVersion()
                }
        }
    }
}

#Preview {
    ProjectsView()
}
