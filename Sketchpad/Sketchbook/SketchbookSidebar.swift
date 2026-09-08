//
//  SketchbookSidebar.swift
//  Sketchpad
//
//  Created by perr on 9/8/2569 BE.
//

import SwiftUI
import UniformTypeIdentifiers
import os
import SwiftData

struct SketchbookSidebar : View {
    @Environment(ArduinoController.self) private var controller
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\SketchbookHistoryData.last_opened, order: .reverse)]) private var recentSketches: [SketchbookHistoryData]
    @State private var showNewSketchModal = false
    
    var body : some View {
        List {
            HStack {
                Text("Sketchbook").bold().foregroundStyle(.secondary)
                Spacer()
                Button {
                    showNewSketchModal = true
                } label: {
                    Label("New Sketch", systemImage: "plus")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
            }
            
            ForEach(recentSketches) { item in
                NavigationLink(value: item.sketch_dir) {
                    HStack {
                        Text(item.sketch_name)
                        Spacer()
                    }
                }
            }
        }
        .sheet(isPresented: $showNewSketchModal) {
            SketchbookNewModalView(
                showNewSketchModal: $showNewSketchModal
            )
            .environment(controller)
        }
    }
}

struct SketchbookNewModalView : View {
    @Environment(ArduinoController.self) private var controller
    @Environment(\.modelContext) private var modelContext
    @Binding var showNewSketchModal: Bool
    
    private let logger: Logger = Logger(subsystem: "com.perr.Sketchpad", category: "NewSketchModal")
    
    @State private var sketchName : String = ""
    @State private var selectedFolderURL: URL? = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    @State private var showFolderPicker: Bool = false
    
    @State private var createError : Bool = false
    
    private var previewPath: String? {
        let trimmedName = sketchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, let folderURL = selectedFolderURL else {
            return selectedFolderURL?.path(percentEncoded: false)
        }
        
        let fileName = trimmedName.hasSuffix(".ino") ? trimmedName : "\(trimmedName).ino"
        return folderURL
            .appendingPathComponent(sketchName)
            .appendingPathComponent(fileName)
            .path(percentEncoded: false)
    }
    
    var body : some View {
        Form {
            Text("Create New Sketch").bold().font(.title2)
            Spacer()
            Section("Sketch Name") {
                TextField("Sketch Name", text: $sketchName)
                    .autocorrectionDisabled()
                    .labelsHidden()
                    .controlSize(.extraLarge)
            }
                
            Section("Sketch Location") {
                HStack {
                    Text(previewPath ?? "Select a folder")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                                    
                    Spacer()
                                    
                    Button("Choose...") {
                        showFolderPicker = true
                    }
                }
            }
            
            if createError {
                Text("Sketch with this name already exists.").foregroundStyle(Color.red)
            }
                
        }.padding(16)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    showNewSketchModal = false
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .buttonBorderShape(.capsule)
            }
            
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    logger
                        .debug(
                            "Create New Sketch With name \(sketchName) and path \(selectedFolderURL?.path(percentEncoded: false).description ?? "nil")"
                        )
                    createSketch()
                }
                .disabled(sketchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .buttonBorderShape(.capsule)
            }
        }
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    // Gain security-scoped access if App Sandbox is enabled
                    _ = url.startAccessingSecurityScopedResource()
                    selectedFolderURL = url
                }
            case .failure(let error):
                print("Error selecting directory: \(error.localizedDescription)")
            }
        }
    }
    
    func createSketch() {
        Task {
            var rsp = await controller.createSketch(
                sketchName: sketchName,
                sketchDir: selectedFolderURL?.path(percentEncoded: false) ?? ""
            )
            logger.log("\(rsp.description)")
            
            let historyManager = SketchbookHistoryManager(modelContext: modelContext)

            if(rsp != "Unknown"){
                createError = false
                historyManager.recordAccess(
                    name: sketchName,
                    mainDir: rsp,
                    dir: selectedFolderURL?.path(percentEncoded: false) ?? ""
                )
                showNewSketchModal = false // Close modal after sketch creation succeeds
            }
            else {
                createError = true
            }
        }
    }

}
