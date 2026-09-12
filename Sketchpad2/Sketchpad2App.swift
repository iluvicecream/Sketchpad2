//
//  Sketchpad2App.swift
//  Sketchpad2
//
//  Created by perr on 9/12/2569 BE.
//

import SwiftUI

@main
struct Sketchpad2App: App {
    var body: some Scene {
        DocumentGroup { document in
            ContentView(document: document)
        } makeDocument: { configuration, context in
            Sketchpad2Document()
        }
    }
}
