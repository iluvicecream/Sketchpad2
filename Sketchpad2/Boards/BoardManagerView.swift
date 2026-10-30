//
//  BoardManagerView.swift
//  Sketchpad2
//

import SwiftUI
import SwiftProtobuf
import os
import GRPCCore

struct PlatformItem: Identifiable, Hashable {
    var id: String { metadataId }
    var metadataId: String
    var readableName: String
    var summary : Cc_Arduino_Cli_Commands_V1_PlatformSummary
}

struct BoardManagerView: View {
    var rpcBox = ArduinoRPCServiceBox.sharedBox
    
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
            await loadPlatforms()
        }
    }
    
    @MainActor
    private func loadPlatforms() async {
          guard let instance = rpcBox.instance, let client = rpcBox.client else {
              logger.error("RPC client or instance is nil")
              isSearchDone = true
              return
          }
          
          do {
              let req = Cc_Arduino_Cli_Commands_V1_PlatformSearchRequest.with {
                  $0.instance = instance
                  $0.searchArgs = ""
              }
              let resp = try await client.platformSearch(req)
              
              var loadedItems: [PlatformItem] = []
              for summary in resp.searchOutput {
                  let latestRelease = summary.releases[summary.latestVersion]
                  let readableName = latestRelease?.name.isEmpty == false
                      ? latestRelease!.name
                      : summary.metadata.id
                  
                  let newItem = PlatformItem(
                      metadataId: summary.metadata.id,
                      readableName: readableName,
                      summary: summary
                  )
                  loadedItems.append(newItem)
              }
              
              self.items = loadedItems
              self.isSearchDone = true
              logger.debug("platform search result \(resp.debugDescription)")
          } catch {
              self.isSearchDone = true
              logger.error("platform search error: \(error.localizedDescription)")
          }
      }
}

struct BoardDetailView : View {
    let item: PlatformItem
    
    @State private var selectedVersion: String
    @State private var isDownloading: Bool = false
    @State private var isInstalled : Bool = false
    
    var rpcBox = ArduinoRPCServiceBox.sharedBox
    
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
                                try await install()
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
        HStack(alignment: .top) {
            Text(selectedVersion)
        }
        Spacer()
    }
    
    @MainActor
    private func install() async throws -> Bool {
        let parts = item.metadataId.split(separator: ":").map(String.init)
        
        guard parts.count >= 2,
              let instance = rpcBox.instance,
              let client = rpcBox.client else {
            logger.error("Invalid metadataId or missing RPC client/instance")
            return false
        }
    
        
        let req = Cc_Arduino_Cli_Commands_V1_PlatformInstallRequest.with {
            $0.instance = rpcBox.instance!
            $0.platformPackage = parts[0]
            $0.architecture = parts[1]
            $0.version = selectedVersion
        }
        isDownloading = true
        defer { isDownloading = false }
        
        return try await client.platformInstall(req) { response in
            for try await msg in response.messages {
                switch msg.message {
                case .progress(let download):
                    logger.debug("download progress: \(download.debugDescription)")
                case .taskProgress(let task):
                    logger.debug("task progress: \(task.debugDescription)")
                    if task.completed {
                        try await rpcBox.reloadInstance()
                        isInstalled = true
                    }
                default:
                    break
                }
            }
            return true
        }
    }
}
