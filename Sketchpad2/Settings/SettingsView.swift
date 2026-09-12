//
//  SettingsView.swift
//  Sketchpad2
//

import SwiftUI

/// Settings window. Waits for the arduino-cli configuration before showing its panes.
struct SettingsView: View {
    @Environment(MainController.self) private var mainController

    var body: some View {
        Group {
            switch mainController.configurationLoad {
            case .loaded:
                tabs
            case .failed(let message):
                failure(message)
            case .idle, .loading:
                if case .failed(let error) = mainController.phase {
                    failure(error.errorDescription ?? "arduino-cli didn't start.")
                } else {
                    loading
                }
            }
        }
        .frame(width: 440)
        .task(id: mainController.isReady) {
            await mainController.loadConfiguration()
        }
    }

    private var tabs: some View {
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
    }

    private var loading: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text(mainController.isReady ? "Loading configuration…" : "Waiting for arduino-cli…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 320)
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Couldn't load the arduino-cli configuration.")
                .font(.callout)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await mainController.loadConfiguration() }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .frame(height: 320)
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
                            .disabled(isSaving)

                        Button {
                            rows.removeAll { $0.id == row.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .disabled(isSaving)
                        .accessibilityLabel("Remove board manager URL")
                    }
                }

                Button {
                    rows.append(BoardManagerURLRow(value: ""))
                } label: {
                    Label("Add URL", systemImage: "plus")
                }
                .disabled(isSaving)
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
        case .initializing:
            return "Initializing"
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
