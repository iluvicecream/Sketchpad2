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
    @Environment(\.documentConfiguration) private var documentConfiguration
    @State private var portsPresented = false
    @State private var boardPortPickerPresented = false
    @State private var buildOutputPresented = false

    var body: some View {
        VStack(spacing: 0) {
            CodeEditorView(text: $document.text)
                .ignoresSafeArea(.container, edges: .top)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if buildOutputPresented {
                Divider()
                BuildOutputView { buildOutputPresented = false }
                    .frame(height: 190)
            }
        }
        .task {
            mainController.start()
        }
        .task(id: mainController.isReady) {
            guard mainController.isReady else { return }
            await mainController.refreshConnectedBoards()
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

                portPicker
            }
        }
        .sheet(isPresented: setupPresented) {
            ArduinoCLISetupView()
                .interactiveDismissDisabled(true)
        }
        .sheet(isPresented: $boardPortPickerPresented) {
            BoardPortPickerView()
        }
    }

    private var setupPresented: Binding<Bool> {
        Binding(get: { !mainController.isReady }, set: { _ in })
    }

    /// The sketch the toolbar builds: the editor's text, named after the document's file.
    private var sketch: SketchSource {
        let name = documentConfiguration?.fileURL?.deletingPathExtension().lastPathComponent
        return SketchSource(name: name ?? "Sketch", text: document.text)
    }

    /// Whether the editor knows enough to build: a board to build for, and no build already going.
    private var canBuild: Bool {
        mainController.isReady
            && mainController.selectedBoardFQBN != nil
            && !mainController.sketchOperation.isRunning
    }

    /// Uploading also needs the port the sketch goes out on.
    private var canUpload: Bool {
        canBuild && mainController.selectedPortID != nil
    }

    /// Compiles the editor's sketch, showing the pane the toolchain writes to.
    private func verify() {
        buildOutputPresented = true
        let sketch = sketch
        Task { await mainController.verify(sketch) }
    }

    /// Compiles the editor's sketch and sends it to the board, showing the pane as it goes.
    private func upload() {
        buildOutputPresented = true
        let sketch = sketch
        Task { await mainController.upload(sketch) }
    }

    /// The dropdown listing the connected ports, so the sketch knows where to upload.
    ///
    /// A popover rather than a `Menu` because the list refreshes by pulling down, which a menu
    /// can't do. The list also refreshes each time the dropdown opens.
    private var portPicker: some View {
        Button {
            portsPresented = true
        } label: {
            HStack(spacing: 4) {
                Text(portPickerTitle)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .help("Select the port to use")
        .popover(isPresented: $portsPresented, arrowEdge: .top) {
            portList
        }
    }

    private var portList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Ports")
                    .font(.headline)
                Spacer()
                Button("Refresh") {
                    Task { await mainController.refreshConnectedBoards() }
                }
                .buttonStyle(.borderless)
                .help("Look for connected boards again")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            List {
                if mainController.connectedPorts.isEmpty {
                    Text("No ports detected")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(mainController.connectedPorts) { port in
                        Button {
                            choose(port)
                        } label: {
                            portRow(port)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .refreshable {
                await mainController.refreshConnectedBoards()
            }

            Divider()

            Button {
                openBoardPortPicker()
            } label: {
                Text("Select Other Board and Port…")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 300, height: 300)
        .background(.regularMaterial)
        .task {
            await mainController.refreshConnectedBoards()
        }
    }

    /// One port in the dropdown, like the Arduino IDE's: the board the daemon matched on top, the
    /// port underneath, and a checkmark when picked. Unmatched ports read `Unknown`.
    private func portRow(_ port: ConnectedPort) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "cable.connector")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(port.boardNames.first ?? "Unknown")
                    .lineLimit(1)
                Text(port.id)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if port.id == mainController.selectedPortID {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(.rect)
    }

    /// Closes the dropdown and opens the board and port dialog.
    ///
    /// The pause lets the popover finish dismissing first: presenting the sheet in the same tick
    /// makes AppKit drop one of the two, since both want to be the window's presented content.
    private func openBoardPortPicker() {
        portsPresented = false
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            boardPortPickerPresented = true
        }
    }

    /// Picks a port from the dropdown and, when the daemon couldn't tell which board is on it,
    /// opens the board and port dialog so the board can be named as part of the same choice.
    private func choose(_ port: ConnectedPort) {
        mainController.select(port: port)
        if port.board == nil {
            openBoardPortPicker()
        } else {
            portsPresented = false
        }
    }

    /// The dropdown's button text: the board and port in play, else what still needs picking.
    private var portPickerTitle: String {
        switch (mainController.selectedBoard, mainController.selectedPort) {
        case let (board?, port?):
            "\(board.name) at \(port.id)"
        case let (board?, nil):
            board.name
        case let (nil, port?):
            port.displayName
        case (nil, nil):
            "Select Port"
        }
    }
}

#Preview {
    ContentView(document: Sketchpad2Document())
        .environment(MainController())
}
