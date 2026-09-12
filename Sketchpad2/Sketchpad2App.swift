//
//  Sketchpad2App.swift
//  Sketchpad2
//
//  Created by perr on 9/12/2569 BE.
//

import SwiftUI

/// Identifiers for the app's auxiliary window scenes.
enum AppWindowID {
    static let boardManager = "board-manager"
    static let libraryManager = "library-manager"
}

@main
struct Sketchpad2App: App {
    @State private var mainController = MainController()

    var body: some Scene {
        DocumentGroup { document in
            ContentView(document: document)
                .environment(mainController)
        } makeDocument: { configuration, context in
            Sketchpad2Document()
        }
        .windowToolbarStyle(.unified)

        Window("Board Manager", id: AppWindowID.boardManager) {
            BoardManagerView()
                .environment(mainController)
        }
        .windowStyle(.hiddenTitleBar)

        Window("Library Manager", id: AppWindowID.libraryManager) {
            LibraryManagerView()
        }
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView()
                .environment(mainController)
        }
    }
}
