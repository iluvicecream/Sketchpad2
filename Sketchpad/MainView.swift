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
    
    var body: some View {
        NavigationSplitView {
            VStack {
                switch selectedModule {
                case 0 :
                    SketchbookSidebar(selectedEditorMainView: $selectedEditorMainView).environment(controller).modelContainer(for: SketchbookHistoryData.self)
                case 1:
                    Text("bowowow")
                case 2:
                    Text("seg")
                case 3:
                    Text("love")
                default:
                    Text("the fuck")
                }
            }
            .toolbar{
                Picker("",selection: $selectedModule){
                    Label("folder",systemImage: "folder").tag(0)
                    Label("memorychip",systemImage:"memorychip").tag(1)
                    Label("books.vertical.fill",systemImage:"books.vertical").tag(2)
                    Label("magnifyingglass",systemImage:"magnifyingglass").tag(3)
                }.pickerStyle(.tabs).controlSize(.extraLarge).buttonSizing(.flexible)
            }
            .navigationSplitViewColumnWidth(min: 310, ideal: 310)
        } detail : {
            if(selectedEditorMainView.starts(with: "SketchEditor_")) {
                let mainDir = String(selectedEditorMainView.trimmingPrefix("SketchEditor_"))
                
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#Preview {
    MainView()
}
