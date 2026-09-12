//
//  ContentView.swift
//  Sketchpad2
//
//  Created by perr on 9/12/2569 BE.
//

import SwiftUI

struct ContentView: View {
    @Bindable var document: Sketchpad2Document

    var body: some View {
        CodeEditorView(text: $document.text)
            // Let the editor run the full window height so its content can scroll under the
            // title bar, where AppKit applies the standard scroll edge treatment.
            .ignoresSafeArea(.container, edges: .top)
    }
}

#Preview {
    ContentView(document: Sketchpad2Document())
}
