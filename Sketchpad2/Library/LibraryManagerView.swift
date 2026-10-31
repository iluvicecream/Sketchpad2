//
//  LibraryManagerView.swift
//  Sketchpad2
//
//  Created by perr on 10/31/2569 BE.
//
import SwiftUI
import os
import SwiftProtobuf

struct LibraryManagerView: View {
    var rpcBox = ArduinoRPCServiceBox.sharedBox
    var libraryBox = LibraryServiceBox.sharedBox
    
    private let logger = Logger(subsystem: "com.perr.Sketchpad2", category: "LibraryView")
    @State var isSearchDone = false
    
    @State var items : [LibraryItem] = []
    @State private var selectedItem: LibraryItem?
    @State private var searchLibrary = ""
    
    var filteredItems: [LibraryItem] {
        if searchLibrary.isEmpty {
            items
        } else {
            items
                .filter {
                    $0.readableName
                        .localizedCaseInsensitiveContains(searchLibrary)
                }
        }
    }

    
    var body: some View {
        NavigationSplitView {
            VStack {
                if isSearchDone {
                    List(filteredItems, selection: $selectedItem) { item in
                        NavigationLink(item.readableName, value: item)
                    }
                }else {
                    ProgressView()
                }
            }
            .listStyle(.sidebar)
            .searchable(
                text: $searchLibrary,
                placement: .sidebar,
                prompt: "Search library",
                
            )
            .background(.ultraThinMaterial)
            .navigationSplitViewColumnWidth(ideal: 300)
        } detail: {
            
        }.task {
            isSearchDone = false
            self.items = await libraryBox.loadPlatforms()
            if self.items != [] {
                isSearchDone = true
            }
        }
    }
}
