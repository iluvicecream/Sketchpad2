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
    private var buildBox = BuildServiceBox.sharedBox
    
    // port
    @State var selectedPortAddress : String = ""
    @AppStorage("selectedBoardFqbn") var selectedBoardFqbn: String = ""

    
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
                VSplitView {
                    CodeEditorView(text: $document.text)
                        .ignoresSafeArea(.container, edges: .top)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if buildOutputPresented {
                        buildConsoleView
                    }
                }
            case .board:
                BoardManagerView()
            case .library:
                LibraryManagerView()
            }
        }
        .task {
            coreBox.startTask()
            
        }
        .task(id: coreBox.instance == nil) {
            do {
                guard coreBox.instance != nil else { return }
                try await buildBox.boardListAll()
                while !Task.isCancelled {
                    try await buildBox.boardList()
                    try? await Task.sleep(for: .seconds(2))
                }
            } catch {}
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Picker("Tab", selection: $selectedTab) {
                    Label("Editor", systemImage: "ellipsis.curlybraces").tag(TabValue.editor)
                    Label("Board Manager", systemImage: "cpu").tag(TabValue.board)
                    Label("Library Manager", systemImage: "book").tag(TabValue.library)
                 }
                .pickerStyle(.segmented)
                .labelStyle(.iconOnly)
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Port", selection: $selectedPortAddress) {
                    Text("Select Port").tag("")
                    ForEach(buildBox.detectedPorts, id: \.port.address) { detected in
                        Text(portTitle(detected)).tag(detected.port.address)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth:200)
                
                Picker("Board", selection: $selectedBoardFqbn) {
                    Text("Select Board").tag("")
                    ForEach(buildBox.boardLists, id: \.fqbn) { board in
                        Text(board.name).tag(board.fqbn)
                    }
                }
                .frame(maxWidth:250)
                
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
        return !selectedBoardFqbn.isEmpty && !buildBox.isBuilding && !buildBox.isUploading
    }

    private var canUpload: Bool {
        return canBuild && !selectedPortAddress.isEmpty
    }

    private var canEraseFlash: Bool {
        return canUpload
    }

    private func verify() {
        buildOutputPresented = true
        Task {
            await buildBox
                .compile(code: document.text, fqbn: selectedBoardFqbn)
        }
    }

    private func upload() {
        buildOutputPresented = true
        Task {
            await buildBox.upload(
                code: document.text,
                fqbn: selectedBoardFqbn,
                portAddress: selectedPortAddress
            )
        }
    }

    private func eraseFlash() {
        buildOutputPresented = true
        //Task { await mainController.eraseFlash() }
    }

    private func portTitle(_ detected: Cc_Arduino_Cli_Commands_V1_DetectedPort) -> String {
        let address = detected.port.address
        if let board = detected.matchingBoards.first {
            return "\(address) (\(board.name))"
        }
        return address
    }
    
    private var buildConsoleView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(
                    buildBox.isBuilding ? "Compiling..." : (
                        buildBox.isUploading
                        ? "Uploading..." : "Output")
                )
                .font(.caption.bold())
                if buildBox.isBuilding || buildBox.isUploading {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button {
                    buildOutputPresented = false
                } label : {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal,10)
            .padding(.vertical,6)
            Divider()
            ScrollView {
                Text(buildBox.consoleOutput)
                    .font(.system(.caption,design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(10)
            }
        }
        .frame(minHeight: 140, idealHeight: 200)
        .background(.background)
    }
}
