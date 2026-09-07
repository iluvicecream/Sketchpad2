//
//  ProjectsView.swift
//  Sketchpad
//
//  Created by perr on 9/5/2569 BE.
//

import SwiftUI

struct MainView: View {
    @Environment(ArduinoController.self) private var controller
    
    @State private var version: String = ""
    @State private var selectedModule = 0
    
    var body: some View {
        NavigationSplitView {
            VStack {
                Picker("",selection: $selectedModule ) {
                    Label("Test 1",systemImage:"tray.and.arrow.down.fill").tag(0)
                    Label("Test 2",systemImage:"tray.and.arrow.down.fill").tag(1)
                    Label("Test 3",systemImage:"tray.and.arrow.down.fill").tag(2)
                }
                .pickerStyle(.tabs)
                .labelsHidden()
                .padding(.horizontal,16)
                .controlSize(.large).buttonSizing(.flexible)
                
                switch selectedModule {
                case 0 :
                    List {
                        NavigationLink {
                            Text("Item")
                        } label: {
                            Text("Item 1")
                        }
                        
                        NavigationLink {
                            Text("Boards Manager")
                        } label: {
                            Text("Item 2")
                        }
                    }
                case 1:
                    Text("bowowow")
                case 2:
                    Text("seg")
                default:
                    Text("the fuck")
                }
            }
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
    MainView()
}
