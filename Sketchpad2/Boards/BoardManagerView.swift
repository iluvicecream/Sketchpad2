//
//  BoardManagerView.swift
//  Sketchpad2
//

import SwiftUI
import SwiftProtobuf
import os
import GRPCCore

struct BoardManagerView: View {
    var rpcBox = ArduinoRPCServiceBox.sharedBox
    var boardBox = BoardServiceBox.sharedBox
    
    private let logger = Logger(subsystem: "com.perr.Sketchpad2", category: "BoardView")
    
    @State var items : [PlatformItem] = []
    @State private var selectedItem: PlatformItem?
    @State var isSearchDone = false
    @State private var searchPlatform = ""
    
    var filteredItems: [PlatformItem] {
        if searchPlatform.isEmpty {
            items
        } else {
            items
                .filter {
                    $0.readableName
                        .localizedCaseInsensitiveContains(searchPlatform)
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
                text: $searchPlatform,
                placement: .sidebar,
                prompt: "Search platforms",
                
            )
            .background(.ultraThinMaterial)
            .navigationSplitViewColumnWidth(ideal: 300)
        } detail: {
            if selectedItem != nil {
                BoardDetailView(
                    item: selectedItem!
                ).id(selectedItem?.id)
            } else {
                ContentUnavailableView("No Selection",
                                       systemImage: "cpu",
                                       description: Text("Please select a board from the sidebar."))
            }
        }
        .task {
            self.items = await boardBox.loadPlatforms()
            if self.items != [] {
                isSearchDone = true
            }
        }
    }
}

struct BoardDetailView : View {
    let item: PlatformItem
    
    @State private var selectedVersion: String
    @State private var isDownloading: Bool = false
    @State private var isInstalled : Bool = false
    
    var rpcBox = ArduinoRPCServiceBox.sharedBox
    var boardBox = BoardServiceBox.sharedBox
    
    private let logger = Logger(subsystem: "com.perr.Sketchpad2", category: "BoardDetail")
    
    init(item: PlatformItem) {
        self.item = item
        self._selectedVersion = State(initialValue: item.summary.latestVersion)
        self._isInstalled = State(
            initialValue:(
                item.summary.installedVersion != "" || item.summary.installedVersion == self.selectedVersion
            )
        )
    }
    
    var body : some View {
        VStack(alignment: .leading) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if item.summary.metadata.deprecated {
                        TagView(
                            tagText: "Deprecated",
                            tagBgColor: .red,
                            tagTextColor: .white,
                        )
                    }
                    if isInstalled {
                        TagView(
                            tagText: "Installed",
                            tagBgColor: .green,
                            tagTextColor: .white,
                        )
                    }
                    Text(item.readableName)
                        .font(.largeTitle.bold())
                    Text(item.metadataId)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(
                        "Maintained by \(item.summary.metadata.maintainer) <\(item.summary.metadata.email)>"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 12) {
                    Picker("Version", selection: $selectedVersion) {
                        ForEach(
                            item.summary.releases.keys.sorted(),
                            id: \.self
                        ) { released in
                            Text(released).tag(released)
                        }
                    }
                    .fixedSize()
                    if isInstalled {
                        Button {
                        } label : {
                            Label("Installed", systemImage: "checkmark")
                        }
                        .buttonStyle(.glassProminent)
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }else {
                        Button {
                            Task {
                                logger.debug("button task run")
                                isDownloading = true
                                var ret = try await boardBox
                                    .install(
                                        item: item,
                                        selectedVersion: selectedVersion
                                    )
                                if ret {
                                    isDownloading = false
                                    isInstalled = true
                                }
                                try await rpcBox.reloadInstance()
                            }
                        } label : {
                            if isDownloading {
                                ProgressView()
                                    .disabled(true)
                            }else {
                                Label("Install", systemImage: "arrow.down")
                            }
                        }
                        .buttonStyle(.glassProminent)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(16)
        Spacer()
    }
}
