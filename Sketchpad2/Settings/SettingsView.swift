//
//  SettingsView.swift
//  Sketchpad2
//

import SwiftUI

/// Placeholder Settings window. Real panes land here as the app grows.
struct SettingsView: View {
    @Environment(MainController.self) private var mainController

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            ArduinoCLISettingsView()
                .tabItem {
                    Label("Arduino CLI", systemImage: "cpu")
                }
        }
        .frame(width: 440)
        .task(id: mainController.isReady) {
            await mainController.loadConfiguration()
        }
    }
}

/// One editable row in the board manager URL list.
private struct BoardManagerURLRow: Identifiable, Equatable {
    let id = UUID()
    var value: String
}

private struct GeneralSettingsView: View {
    @Environment(MainController.self) private var mainController

    @State private var rows: [BoardManagerURLRow] = []
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var indexWarning: String?

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        guard let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String else {
            return short
        }
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: version)
            }

            Section("Additional Boards Manager URLs") {
                if rows.isEmpty {
                    Text("No additional URLs.")
                        .foregroundStyle(.secondary)
                }

                ForEach($rows) { $row in
                    HStack(spacing: 8) {
                        TextField("https://example.com/package_index.json", text: $row.value)
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .disabled(isSaving || !mainController.isReady)

                        Button {
                            rows.removeAll { $0.id == row.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .disabled(isSaving || !mainController.isReady)
                        .accessibilityLabel("Remove board manager URL")
                    }
                }

                Button {
                    rows.append(BoardManagerURLRow(value: ""))
                } label: {
                    Label("Add URL", systemImage: "plus")
                }
                .disabled(isSaving || !mainController.isReady)

                if !mainController.isReady {
                    Text("Start arduino-cli before editing board manager URLs.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                } else if let indexWarning {
                    Text(indexWarning)
                        .font(.callout)
                        .foregroundStyle(.orange)
                } else if isUpdatingIndex {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(indexProgressText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Spacer()
                    Button("Revert") {
                        seedFromConfiguration()
                        errorMessage = nil
                        indexWarning = nil
                    }
                    .disabled(!isDirty || isSaving)

                    Button("Save") {
                        Task { await save() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isDirty || isSaving)
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 320)
        .task { seedFromConfiguration() }
        .onChange(of: savedURLs) { _, _ in
            guard !isDirty else { return }
            seedFromConfiguration()
        }
    }

    /// The additional URLs currently stored in the daemon configuration.
    private var savedURLs: [String] {
        mainController.boardManagerURLs
    }

    private var editedURLs: [String] {
        rows.map(\.value)
    }

    private var isDirty: Bool {
        editedURLs != savedURLs
    }

    private var isUpdatingIndex: Bool {
        if case .updating = mainController.boardIndexUpdate { return true }
        return false
    }

    private var indexProgressText: String {
        if case .updating(let message) = mainController.boardIndexUpdate, let message {
            return message
        }
        return "Updating board index…"
    }

    private func seedFromConfiguration() {
        rows = savedURLs.map { BoardManagerURLRow(value: $0) }
    }

    @MainActor
    private func save() async {
        isSaving = true
        errorMessage = nil
        indexWarning = nil
        defer { isSaving = false }

        do {
            try await mainController.saveBoardManagerURLs(editedURLs)
        } catch {
            errorMessage = message(for: error)
            return
        }

        seedFromConfiguration()

        do {
            try await mainController.refreshBoardIndex()
        } catch {
            indexWarning = message(for: error)
        }
    }

    private func message(for error: Error) -> String {
        (error as? ArduinoCLIError)?.errorDescription ?? error.localizedDescription
    }
}

private struct ArduinoCLISettingsView: View {
    @Environment(MainController.self) private var mainController

    var body: some View {
        Form {
            Section("arduino-cli") {
                LabeledContent("Status", value: statusText)
                LabeledContent("Version", value: mainController.arduinoCLIVersion ?? "—")
                LabeledContent("Daemon port", value: mainController.daemonPort.map(String.init) ?? "—")
                LabeledContent("Instance", value: instanceText)
            }
        }
        .formStyle(.grouped)
        .frame(height: 170)
    }

    private var statusText: String {
        switch mainController.phase {
        case .idle:
            return "Not started"
        case .checking:
            return "Checking installation"
        case .downloading:
            return "Downloading"
        case .extracting:
            return "Extracting"
        case .startingDaemon:
            return "Starting daemon"
        case .ready:
            return "Running"
        case .failed(let error):
            return error.errorDescription ?? "Failed"
        }
    }

    private var instanceText: String {
        guard let instance = mainController.instance else { return "—" }
        return "id \(instance.id)"
    }
}

#Preview {
    SettingsView()
        .environment(MainController())
}
