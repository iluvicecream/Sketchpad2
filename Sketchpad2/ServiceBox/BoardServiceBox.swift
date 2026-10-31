//
//  BoardServiceBox.swift
//  Sketchpad2
//
//  Created by perr on 10/31/2569 BE.
//

import SwiftUI
import os
import SwiftProtobuf
import GRPCCore

@Observable
final class BoardServiceBox {
    static let sharedBox = BoardServiceBox()
    private let logger = Logger(subsystem: "com.perr.Sketchpad2", category: "BoardBox")
    
    var rpcBox = ArduinoRPCServiceBox.sharedBox
    
    func loadPlatforms() async -> [PlatformItem] {
          guard let instance = rpcBox.instance, let client = rpcBox.client else {
              logger.error("RPC client or instance is nil")
              return []
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
              logger.debug("platform search result \(resp.debugDescription)")
              return loadedItems
          } catch {
              logger.error("platform search error: \(error.localizedDescription)")
              return []
          }
      }
    
    func install(item:PlatformItem,selectedVersion: String) async throws -> Bool {
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
        return try await client.platformInstall(req) { response in
            for try await msg in response.messages {
                switch msg.message {
                case .progress(let download):
                    self.logger
                        .debug(
                            "download progress: \(download.debugDescription)"
                        )
                case .taskProgress(let task):
                    self.logger.debug("task progress: \(task.debugDescription)")
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

struct PlatformItem: Identifiable, Hashable {
    var id: String { metadataId }
    var metadataId: String
    var readableName: String
    var summary : Cc_Arduino_Cli_Commands_V1_PlatformSummary
}
