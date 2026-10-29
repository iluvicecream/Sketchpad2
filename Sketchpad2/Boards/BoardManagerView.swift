//
//  BoardManagerView.swift
//  Sketchpad2
//

import SwiftUI
import SwiftProtobuf
import os

struct PlatformItem: Identifiable, Hashable {
    let id = UUID()
    let metadataId: String
    let summary : Cc_Arduino_Cli_Commands_V1_PlatformSummary
}

struct BoardManagerView: View {
    var rpcBox = ArduinoRPCServiceBox.sharedBox
    
    private let logger = Logger(subsystem: "com.perr.Sketchpad2", category: "BoardView")
    
    @State var items : [PlatformItem] = []
    @State private var selectedItem: PlatformItem?
    @State var isSearchDone = false
    
    var body: some View {
        NavigationSplitView {
            VStack {
                if isSearchDone {
                    List(items, selection: $selectedItem) { item in
                        NavigationLink(item.metadataId, value: item)
                    }
                }else {
                    ProgressView()
                }
            }
            .listStyle(.sidebar)
            .background(.ultraThinMaterial)
        } detail: {
            if let selectedItem {
                
            } else {
                ContentUnavailableView("No Selection",
                                       systemImage: "cpu",
                                       description: Text("Please select a board from the sidebar."))
            }
        }
        .navigationSplitViewStyle(.balanced)
        .task {
            do {
                let req = Cc_Arduino_Cli_Commands_V1_PlatformSearchRequest.with {
                    $0.instance = rpcBox.instance!
                    $0.searchArgs = "" // empty mean all
                }
                let resp = try await rpcBox.client?.platformSearch(req)
                resp?.searchOutput.forEach { summary in
                    var newItem = PlatformItem(
                        metadataId:summary.metadata.id,
                        summary: summary
                    )
                    items.append(newItem)
                }
                isSearchDone = true
                logger.debug("platform search result \(resp.debugDescription)")
            } catch {
                logger.debug("platform search error \(error)")
            }
        }
    }
}

