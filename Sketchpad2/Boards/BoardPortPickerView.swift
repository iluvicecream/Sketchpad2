//
//  BoardPortPickerView.swift
//  Sketchpad2
//

import SwiftUI

/// The Arduino IDE's "Select Other Board and Port" dialog: name the board yourself for a port the
/// daemon couldn't identify, and say which port to upload through.
///
/// The picks apply on OK, so Cancel leaves the editor on whatever it was already using.
///
/// Picking a port here doesn't pull in the board the daemon matched to it, unlike picking one in
/// the dropdown: this dialog exists to pair a board with a port by hand, so both stay as chosen.
struct BoardPortPickerView: View {
    @Environment(MainController.self) private var mainController
    @Environment(\.dismiss) private var dismiss

    /// The board the dialog would apply, seeded from the editor and applied on OK.
    @State private var boardID: KnownBoard.ID?
    /// The port the dialog would apply, seeded from the editor and applied on OK.
    @State private var portID: ConnectedPort.ID?
    /// The board search text, matched against the board, FQBN, and platform names.
    @State private var query = ""
    /// Whether ports the daemon couldn't identify are listed too.
    @State private var showsAllPorts = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            introduction
            columns
            footer
        }
        .padding(20)
        .frame(width: 720, height: 520, alignment: .topLeading)
        .task {
            seedSelection()
            await mainController.refreshKnownBoards()
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Select Other Board and Port")
                .font(.title2.weight(.semibold))
            Text(
                """
                Select both a Board and a Port if you want to upload a sketch. \
                If you only select a Board you will be able to compile, but not to upload your sketch.
                """
            )
            .foregroundStyle(.secondary)
        }
    }

    private var columns: some View {
        HStack(alignment: .top, spacing: 16) {
            boardColumn
            portColumn
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Boards

    private var boardColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            columnTitle("Boards")
            TextField("Search board", text: $query)
                .textFieldStyle(.roundedBorder)
            boardList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var boardList: some View {
        if boards.isEmpty {
            boardPlaceholder
        } else {
            List(boards, selection: $boardID) { board in
                VStack(alignment: .leading, spacing: 1) {
                    Text(board.name)
                        .lineLimit(1)
                    if !board.platformName.isEmpty {
                        Text(board.platformName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    /// What the board list shows while it has no rows: the fetch's progress, its failure, or the
    /// search coming up empty.
    @ViewBuilder
    private var boardPlaceholder: some View {
        if case .failed(let message) = mainController.knownBoardCatalog {
            ContentUnavailableView(
                "Couldn't load boards",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        } else if mainController.knownBoards.isEmpty {
            if mainController.knownBoardCatalog == .loaded {
                ContentUnavailableView(
                    "No boards installed",
                    systemImage: "cpu",
                    description: Text("Install a platform in the Board Manager to name its boards here.")
                )
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ContentUnavailableView.search(text: query)
        }
    }

    /// The boards to offer: what the installed platforms provide, narrowed by the search text.
    private var boards: [KnownBoard] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return mainController.knownBoards }
        return mainController.knownBoards.filter {
            $0.name.localizedCaseInsensitiveContains(text)
                || $0.fqbn.localizedCaseInsensitiveContains(text)
                || $0.platformName.localizedCaseInsensitiveContains(text)
        }
    }

    // MARK: - Ports

    private var portColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            columnTitle("Ports")
            portList
            Toggle("Show all ports", isOn: $showsAllPorts)
                .toggleStyle(.checkbox)
                .help("List the ports the daemon couldn't match to a board as well")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var portList: some View {
        if ports.isEmpty {
            ContentUnavailableView(
                "No ports detected",
                systemImage: "cable.connector",
                description: Text("Plug a board in and open this dialog again.")
            )
        } else {
            List(ports, selection: $portID) { port in
                portRow(port)
            }
            .listStyle(.inset)
        }
    }

    /// One port: its address, the protocol the daemon reported, and a checkmark when it's picked.
    private func portRow(_ port: ConnectedPort) -> some View {
        HStack(spacing: 8) {
            Text(port.id)
                .lineLimit(1)
            if !port.protocolLabel.isEmpty {
                Text(port.protocolLabel)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if port.id == portID {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
    }

    /// The ports to offer: everything the daemon detects, less the ones it couldn't identify when
    /// the user asks to hide them. The picked port stays listed either way, so narrowing the list
    /// never contradicts the selection.
    private var ports: [ConnectedPort] {
        mainController.connectedPorts.filter { port in
            showsAllPorts || port.board != nil || port.id == portID
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(hint)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("OK") { apply() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(board == nil)
        }
    }

    /// What the dialog says it still needs, the way the IDE nudges for a board.
    private var hint: String {
        if board == nil {
            "Please pick a board connected to the port you have selected."
        } else if portID == nil {
            "Pick a port too if you want to upload a sketch."
        } else {
            "Ready to compile and upload with this board and port."
        }
    }

    // MARK: - Selection

    /// The board the dialog would apply, whether it came from the installed platforms or from what
    /// the daemon matched to the port the editor is on.
    private var board: KnownBoard? {
        guard let boardID else { return nil }
        return mainController.knownBoards.first { $0.id == boardID }
            ?? mainController.selectedPort?.boards.first { $0.id == boardID }
    }

    /// Starts the dialog on whatever the editor already has, so OK alone keeps the status quo.
    private func seedSelection() {
        boardID = mainController.selectedBoard?.id
        portID = mainController.selectedPortID
    }

    private func apply() {
        mainController.select(board: board, port: portID)
        dismiss()
    }

    private func columnTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}
