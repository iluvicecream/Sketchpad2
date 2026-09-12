//
//  BoardManagerView.swift
//  Sketchpad2
//

import SwiftUI

/// Window for browsing the platforms the arduino-cli indexes offer and installing their boards.
struct BoardManagerView: View {
    @Environment(MainController.self) private var mainController
    @State private var query = ""

    var body: some View {
        content
            .frame(minWidth: 480, minHeight: 360)
            .searchable(text: $query, prompt: "Search boards")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await mainController.loadBoards() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(!mainController.isReady || mainController.boardCatalog == .loading)
                }
            }
            .task(id: mainController.isReady) {
                guard mainController.isReady else { return }
                await mainController.loadBoards()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch mainController.boardCatalog {
        case .idle:
            if mainController.isReady {
                catalog
            } else {
                ContentUnavailableView(
                    "Waiting for arduino-cli",
                    systemImage: "cpu",
                    description: Text("The board catalog appears once setup finishes.")
                )
            }
        case .loading:
            catalog
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't load boards", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    Task { await mainController.loadBoards() }
                }
            }
        case .loaded:
            catalog
        }
    }

    /// Keeps the current results on screen while a refresh is in flight.
    @ViewBuilder
    private var catalog: some View {
        if platforms.isEmpty {
            if mainController.boardCatalog == .loading {
                ProgressView("Loading boards…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView(
                    "No platforms found",
                    systemImage: "cpu",
                    description: Text("The platform indexes didn't report anything to install.")
                )
            } else {
                ContentUnavailableView.search(text: query)
            }
        } else {
            List(platforms) { platform in
                PlatformRow(platform: platform, install: mainController.platformInstall) {
                    Task { await mainController.installPlatform(platform) }
                }
            }
            .listStyle(.inset)
        }
    }

    /// The platforms matching the current search text, or all of them when the field is empty.
    private var platforms: [InstallablePlatform] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return mainController.installablePlatforms }
        return mainController.installablePlatforms.filter { platform in
            platform.name.localizedCaseInsensitiveContains(trimmed)
                || platform.id.localizedCaseInsensitiveContains(trimmed)
                || platform.boards.contains { $0.name.localizedCaseInsensitiveContains(trimmed) }
        }
    }
}

/// One platform in the catalog, with the boards it provides and its install control.
private struct PlatformRow: View {
    let platform: InstallablePlatform
    let install: MainController.PlatformInstall
    let onInstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(platform.name)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                installControl
            }

            if !platform.boards.isEmpty {
                Text(platform.boards.map(\.name).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let status {
                Text(status.text)
                    .font(.caption)
                    .foregroundStyle(status.isError ? Color.red : Color.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        if platform.isInstalled {
            return "\(platform.id) · installed \(platform.installedVersion)"
        }
        return platform.latestVersion.isEmpty
            ? platform.id
            : "\(platform.id) · latest \(platform.latestVersion)"
    }

    @ViewBuilder
    private var installControl: some View {
        switch install {
        case .installing(let platformID, _) where platformID == platform.id:
            ProgressView()
                .controlSize(.small)
        case .failed(let platformID, _) where platformID == platform.id:
            Button("Retry", action: onInstall)
                .disabled(platform.latestVersion.isEmpty)
        default:
            if platform.isInstalled, !platform.isUpdateAvailable {
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button(platform.isUpdateAvailable ? "Update" : "Install", action: onInstall)
                    .disabled(platform.latestVersion.isEmpty)
            }
        }
    }

    private var status: (text: String, isError: Bool)? {
        switch install {
        case .installing(let platformID, let message) where platformID == platform.id:
            return (message ?? "Installing…", false)
        case .failed(let platformID, let message) where platformID == platform.id:
            return (message, true)
        default:
            return nil
        }
    }
}

#Preview {
    BoardManagerView()
        .environment(MainController())
}
