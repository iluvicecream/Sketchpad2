//
//  Sketchpad2App.swift
//  Sketchpad2
//
//  Created by perr on 9/12/2569 BE.
//

import SwiftUI

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
    }
}
