//
//  LibraryServiceBox.swift
//  Sketchpad2
//
//  Created by perr on 10/31/2569 BE.
//

import SwiftUI
import os
import SwiftProtobuf
import GRPCCore

struct LibraryItem: Identifiable, Hashable {
    var id: UUID
    var readableName: String
    var summary : Cc_Arduino_Cli_Commands_V1_SearchedLibrary
}

@Observable
final class LibraryServiceBox {
    static let sharedBox = LibraryServiceBox()
    private let logger = Logger(subsystem: "com.perr.Sketchpad2", category: "LibraryBox")
    
    var rpcBox = ArduinoRPCServiceBox.sharedBox
    
    func loadPlatforms() async -> [LibraryItem] {
          guard let instance = rpcBox.instance, let client = rpcBox.client else {
              logger.error("RPC client or instance is nil")
              return []
          }
          
          do {
              let req = Cc_Arduino_Cli_Commands_V1_LibrarySearchRequest.with {
                  $0.instance = instance
                  $0.searchArgs = ""
                  $0.omitReleasesDetails = true
              }
              
              // FIX: ticketed/1
              var options = CallOptions.defaults
              options.maxRequestMessageBytes = 100 * 1024 * 1024 // idk why but we need to set the req otherwise it just wouldn't work
              options.maxResponseMessageBytes = 100 * 1024 * 1024
              
              let resp = try await client.librarySearch(req, options: options)
              
              var loadedItems: [LibraryItem] = []
              for summary in resp.libraries {
                  let latestRelease = summary.releases[summary.latest.version]
                  let readableName = summary.name
                  let newItem = LibraryItem(
                      id: UUID(),
                      readableName: readableName,
                      summary: summary
                  )
                  loadedItems.append(newItem)
              }
              logger.debug("platform search result \(resp.debugDescription)")
              return loadedItems
          } catch {
              logger.error("platform search error: \(error.localizedDescription)")
              return []
          }
      }
   
    func install(item: LibraryItem, selectedVersion: String) async throws -> Bool {
        guard let instance = rpcBox.instance,
              let client = rpcBox.client else {
            logger.error("Missing RPC client/instance")
            return false
        }
        
        let req = Cc_Arduino_Cli_Commands_V1_LibraryInstallRequest.with {
            $0.instance = instance
            $0.name = item.summary.name
            $0.version = selectedVersion
        }
        
        var options = CallOptions.defaults
        options.maxRequestMessageBytes = 100 * 1024 * 1024
        options.maxResponseMessageBytes = 100 * 1024 * 1024
        
        return try await client.libraryInstall(req, options: options) { response in
            for try await msg in response.messages {
                switch msg.message {
                case .progress(let download):
                    self.logger.debug("library download progress: \(download.debugDescription)")
                case .taskProgress(let task):
                    self.logger.debug("library task progress: \(task.debugDescription)")
                    if task.completed {
                        try await self.rpcBox.reloadInstance()
                    }
                default:
                    break
                }
            }
            return true
        }
    }
}
