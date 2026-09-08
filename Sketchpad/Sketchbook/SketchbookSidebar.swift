//
//  SketchbookSidebar.swift
//  Sketchpad
//
//  Created by perr on 9/8/2569 BE.
//

import SwiftUI
import UniformTypeIdentifiers
import os

struct SketchbookSidebar : View {
    @Environment(ArduinoController.self) private var controller
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
            NavigationLink(value: "newmodal") {
                HStack {
                    Text("Sketch 08 Sep")
                    Spacer()
                    
                }
            }
        }
        .sheet(isPresented: $showNewSketchModal) {
            SketchbookNewModalView(showNewSketchModal: $showNewSketchModal).environment(controller)
        }
    }
}

struct SketchbookNewModalView : View {
    @Environment(ArduinoController.self) private var controller
    @Binding var showNewSketchModal: Bool
    
    private let logger: Logger = Logger(subsystem: "com.perr.Sketchpad", category: "NewSketchModal")
    
    @State private var sketchName : String = ""
    @State private var selectedFolderURL: URL? = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    @State private var showFolderPicker: Bool = false
    
    private var previewPath: String? {
        let trimmedName = sketchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, let folderURL = selectedFolderURL else {
            return selectedFolderURL?.path(percentEncoded: false)
        }
        
        let fileName = trimmedName.hasSuffix(".ino") ? trimmedName : "\(trimmedName).ino"
        return folderURL.appendingPathComponent(fileName).path(percentEncoded: false)
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
}
