//
//  MainEditorContentView.swift
//  Sketchpad2
//
//  Created by perr on 9/12/2569 BE.
//

import SwiftUI

enum TabValue: Hashable {
    case editor,board,library
}

struct ContentView: View {
    @Bindable var document: Sketchpad2Document
    @Environment(\.documentConfiguration) private var documentConfiguration
    @State private var portsPresented = false
    @State private var buildOutputPresented = false
    
    private var coreBox = CoreServiceBox.sharedBox
    private var daemonBox = ArduinoDaemonServiceBox.sharedBox
    
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    @State private var selectedTab: TabValue = .editor

    var body: some View {
        NavigationSplitView(
            columnVisibility: $columnVisibility,
        ) {
            Text("")
                .toolbar(removing:.sidebarToggle)
        } detail : {
            switch selectedTab {
            case .editor:
                CodeEditorView(text: $document.text)
                    .ignoresSafeArea(.container, edges: .top)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .board:
                BoardManagerView()
            case .library:
                LibraryManagerView()
            }
        }
        .task {
            coreBox.startTask()
        }
        .toolbar {
            ToolbarItemGroup(placement: .principal) {
                Picker("Tab", selection: $selectedTab) {
                    Label("Editor", systemImage: "ellipsis.curlybraces").tag(TabValue.editor)
                    Label("Board Manager", systemImage: "cpu").tag(TabValue.board)
                    Label("Library Manager", systemImage: "book").tag(TabValue.library)
                 }
                .pickerStyle(.segmented)
                .labelStyle(.iconOnly)
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    verify()
                } label: {
                    Label("Verify", systemImage: "checkmark.circle")
                }
                .help("Verify the sketch")
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!canBuild)

                Button {
                    upload()
                } label: {
                    Label("Upload", systemImage: "arrow.up.circle")
                }
                .help("Upload the sketch to the board")
                .keyboardShortcut("u", modifiers: .command)
                .disabled(!canUpload)

                Button {
                    eraseFlash()
                } label: {
                    Label("Erase Flash", systemImage: "eraser")
                }
                .help("Erase the board's flash memory")
                .disabled(!canEraseFlash)
            }
        }
        .sheet(isPresented: setupPresented) {
            SetupSheetView()
                .interactiveDismissDisabled(true)
        }
    }

    private var setupPresented: Binding<Bool> {
        Binding(get: { (coreBox.instance == nil) }, set: { _ in })
    }

    private var canBuild: Bool {
        return true
    }

    private var canUpload: Bool {
        return true
    }

    private var canEraseFlash: Bool {
        return true
    }

    private func verify() {
        buildOutputPresented = true
        //Task { await mainController.verify(sketch) }
    }

    private func upload() {
        buildOutputPresented = true
        //Task { await mainController.upload(sketch) }
    }

    private func eraseFlash() {
        buildOutputPresented = true
        //Task { await mainController.eraseFlash() }
    }

}
