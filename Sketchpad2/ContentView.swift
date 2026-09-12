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
            .ignoresSafeArea(.container, edges: .top)
    }
}

#Preview {
    ContentView(document: Sketchpad2Document())
}
