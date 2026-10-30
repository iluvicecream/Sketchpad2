//
//  Sketchpad2App.swift
//  Sketchpad2
//
//  Created by perr on 9/12/2569 BE.
//

import SwiftUI

@main
struct Sketchpad2App: App {
    @AppStorage("app_theme") private var selectedTheme: AppTheme = .system

    var body: some Scene {
        DocumentGroup { document in
            ContentView(document: document)
                .preferredColorScheme(selectedTheme.colorScheme)
        } makeDocument: { configuration, context in
            Sketchpad2Document()
        }
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView()
                .preferredColorScheme(selectedTheme.colorScheme)
        }
    }
}
