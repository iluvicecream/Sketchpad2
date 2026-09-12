//
//  ContentView.swift
//  Sketchpad2
//
//  Created by perr on 9/12/2569 BE.
//

import SwiftUI

struct ContentView: View {
    @Bindable var document: Sketchpad2Document
    @Environment(MainController.self) private var mainController

    var body: some View {
        CodeEditorView(text: $document.text)
            .ignoresSafeArea(.container, edges: .top)
            .task {
                mainController.start()
            }
            .sheet(isPresented: setupPresented) {
                ArduinoCLISetupView()
                    .interactiveDismissDisabled(true)
            }
    }

    private var setupPresented: Binding<Bool> {
        Binding(get: { !mainController.isReady }, set: { _ in })
    }
}

#Preview {
    ContentView(document: Sketchpad2Document())
        .environment(MainController())
}
