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
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        CodeEditorView(text: $document.text)
            .ignoresSafeArea(.container, edges: .top)
            .task {
                mainController.start()
            }
            .toolbar {
                ToolbarItemGroup(placement: .principal) {
                    Button {
                        openWindow(id: AppWindowID.boardManager)
                    } label: {
                        Label("Board Manager", systemImage: "cpu")
                    }
                    .help("Board Manager")

                    Button {
                        openWindow(id: AppWindowID.libraryManager)
                    } label: {
                        Label("Library Manager", systemImage: "book")
                    }
                    .help("Library Manager")
                }
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
