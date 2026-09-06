//
//  ProjectsView.swift
//  Sketchpad
//
//  Created by perr on 9/5/2569 BE.
//

import SwiftUI

struct ProjectsView: View {
    @Environment(ArduinoController.self) private var controller
    
    var body: some View {
        Text("placeholder")
        Text(controller.coreInstanceId?.description ?? "no controller")
    }
}

#Preview {
    ProjectsView()
}
