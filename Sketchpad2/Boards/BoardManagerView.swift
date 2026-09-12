//
//  BoardManagerView.swift
//  Sketchpad2
//

import SwiftUI

/// Window for browsing the platforms the arduino-cli indexes offer and installing their boards.
struct BoardManagerView: View {
    @Environment(\.dismissSearch) private var dismissSearch
    @Environment(MainController.self) private var mainController
    @State private var query = ""
    @State private var selection: InstallablePlatform.ID?

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            sidebar
                .navigationSplitViewColumnWidth(min: 220,ideal:220)
                .searchable(text: $query, placement: .sidebar, prompt: "Search boards")
                .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.automatic)
        .frame(minWidth: 720, minHeight: 420)
        .task(id: mainController.isReady) {
            guard mainController.isReady else { return }
            await mainController.loadBoards()
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        switch mainController.boardCatalog {
        case .failed(let message):
            failure(message)
        case .idle where !mainController.isReady:
            ContentUnavailableView(
                "Waiting for arduino-cli",
                systemImage: "cpu",
                description: Text("The board catalog appears once setup finishes.")
            )
        default:
            platformList
        }
    }

    @ViewBuilder
    private var platformList: some View {
        if platforms.isEmpty {
            if mainController.boardCatalog == .loaded {
                emptyState
            } else {
                ProgressView("Loading boards…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            List(platforms, selection: $selection) { platform in
                PlatformSidebarRow(platform: platform)
            }
            .refreshable {
                await mainController.loadBoards()
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView(
                "No platforms found",
                systemImage: "cpu",
                description: Text("The platform indexes didn't report anything to install.")
            )
        } else {
            ContentUnavailableView.search(text: query)
        }
    }

    private func failure(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't load boards", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") {
                Task { await mainController.loadBoards() }
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let platform = selectedPlatform {
            PlatformDetail(platform: platform, install: mainController.platformInstall) {
                Task { await mainController.installPlatform(platform) }
            }
        } else {
            ContentUnavailableView(
                "Select a platform",
                systemImage: "cpu",
                description: Text("Pick a platform from the sidebar to see its boards and install it.")
            )
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

    /// The selected platform, resolved against the full catalog so a filtered-out row stays selected.
    private var selectedPlatform: InstallablePlatform? {
        guard let selection else { return nil }
        return mainController.installablePlatforms.first { $0.id == selection }
    }
}

/// One platform in the sidebar: its name and, when present, an installed marker.
private struct PlatformSidebarRow: View {
    let platform: InstallablePlatform

    var body: some View {
        HStack(spacing: 8) {
            Text(platform.name)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if platform.isInstalled {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help("Installed")
            }
        }
    }
}

/// The detail pane for a platform: its identity, version info, boards, and the install control.
private struct PlatformDetail: View {
    let platform: InstallablePlatform
    let install: MainController.PlatformInstall
    let onInstall: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if let status {
                    Text(status.text)
                        .font(.callout)
                        .foregroundStyle(status.isError ? Color.red : Color.secondary)
                }

                versionSection

                if !platform.boards.isEmpty {
                    boardsSection
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(platform.name)
                    .font(.largeTitle.bold())
                Text(platform.id)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            installControl
        }
    }

    private var versionSection: some View {
        GroupBox("Version") {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent(
                    "Installed",
                    value: platform.isInstalled ? platform.installedVersion : "Not installed"
                )
                LabeledContent(
                    "Latest",
                    value: platform.latestVersion.isEmpty ? "Unknown" : platform.latestVersion
                )
            }
            .padding(6)
        }
    }

    private var boardsSection: some View {
        GroupBox("Boards (\(platform.boards.count))") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(platform.boards) { board in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(board.name)
                        if !board.fqbn.isEmpty {
                            Text(board.fqbn)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
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
                    .foregroundStyle(.green)
            } else {
                Button(platform.isUpdateAvailable ? "Update" : "Install", action: onInstall)
                    .buttonStyle(.borderedProminent)
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
