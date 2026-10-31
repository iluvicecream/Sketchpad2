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
            if selectedItem != nil {
                LibraryDetailView(
                    item: selectedItem!
                ).id(selectedItem?.id)
            } else {
                ContentUnavailableView("No Selection",
                                       systemImage: "book",
                                       description: Text("Please select a library from the sidebar."))
            }
        }.task {
            isSearchDone = false
            self.items = await libraryBox.loadPlatforms()
            if self.items != [] {
                isSearchDone = true
            }
        }
    }
}


struct LibraryDetailView : View {
    let item: LibraryItem
    
    @State private var selectedVersion: String = ""
    @State private var isDownloading: Bool = false
    @State private var isInstalled : Bool = false
    
    var rpcBox = ArduinoRPCServiceBox.sharedBox
    var libraryBox = LibraryServiceBox.sharedBox
    
    private let logger = Logger(subsystem: "com.perr.Sketchpad2", category: "LibraryDetail")
    
    var availableVersions: [String] {
        if !item.summary.releases.isEmpty {
            return Array(item.summary.releases.keys).sorted {
                $0.localizedStandardCompare($1) == .orderedDescending
            }
        } else if !item.summary.latest.version.isEmpty {
            return [item.summary.latest.version]
        }
        return []
    }
    
    var body : some View {
        VStack(alignment: .leading) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.readableName)
                        .font(.largeTitle.bold())
                    Text(
                        "By \(item.summary.latest.maintainer) <\(item.summary.latest.author)>"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    Text(item.summary.latest.sentence)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 12) {
                    Picker("Version", selection: $selectedVersion) {
                        ForEach(
                            availableVersions,
                            id: \.self
                        ) { version in
                            Text(version).tag(version)
                        }
                    }
                    .controlSize(.extraLarge)
                    .fixedSize()
                    Button {
                        Task {
                            isDownloading = true
                            defer { isDownloading = false }
                            let success = try await libraryBox.install(
                                item: item,
                                selectedVersion: selectedVersion
                            )
                            if success {
                                isInstalled = true
                                try await rpcBox.reloadInstance()
                            }
                        }
                    } label: {
                        if isDownloading {
                            ProgressView()
                        } else {
                            Text(isInstalled ? "Installed" : "Install")
                        }
                    }
                    .controlSize(.extraLarge)
                    .buttonStyle(.glassProminent)
                    .disabled(isDownloading || isInstalled || selectedVersion.isEmpty)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(16)
        .onAppear {
            selectedVersion = item.summary.latest.version
        }
        .onChange(of: item) { _, newItem in
            selectedVersion = newItem.summary.latest.version
            isInstalled = false
        }
        Spacer()
    }
}
