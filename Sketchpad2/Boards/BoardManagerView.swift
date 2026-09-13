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
    @State private var scope: CatalogScope = .all
    @State private var selection: InstallablePlatform.ID?

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            sidebar
                .navigationSplitViewColumnWidth(min: 260, ideal: 260)
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
        if showsCatalog {
            VStack(spacing: 0) {
                filterPicker
                catalog
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            ProgressView("Loading boards…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Whether there's a catalog to show or filter, as opposed to one still loading.
    private var showsCatalog: Bool {
        mainController.boardCatalog == .loaded || !mainController.installablePlatforms.isEmpty
    }

    @ViewBuilder
    private var catalog: some View {
        if platforms.isEmpty {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(platforms, selection: $selection) { platform in
                PlatformSidebarRow(platform: platform)
            }
            .refreshable {
                await mainController.loadBoards()
            }
        }
    }

    private var filterPicker: some View {
        CatalogScopePicker(scope: $scope)
    }

    @ViewBuilder
    private var emptyState: some View {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            switch scope {
            case .all:
                ContentUnavailableView(
                    "No platforms found",
                    systemImage: "cpu",
                    description: Text("The platform indexes didn't report anything to install.")
                )
            case .installed:
                ContentUnavailableView(
                    "No platforms installed",
                    systemImage: "cpu",
                    description: Text("Platforms you install appear here.")
                )
            case .updatable:
                ContentUnavailableView(
                    "Everything is up to date",
                    systemImage: "cpu",
                    description: Text("No installed platform has a newer version on offer.")
                )
            }
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
            PlatformDetail(
                platform: platform,
                operation: mainController.platformOperation,
                onInstall: { version in
                    Task { await mainController.installPlatform(platform, version: version) }
                },
                onUninstall: {
                    Task { await mainController.uninstallPlatform(platform) }
                }
            )
            .id(platform.id)
        } else {
            ContentUnavailableView(
                "Select a platform",
                systemImage: "cpu",
                description: Text("Pick a platform from the sidebar to see its boards and install it.")
            )
        }
    }

    /// The platforms in the picked scope matching the current search text.
    private var platforms: [InstallablePlatform] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return mainController.installablePlatforms.filter { platform in
            guard scope.includes(platform) else { return false }
            guard !trimmed.isEmpty else { return true }
            return platform.name.localizedCaseInsensitiveContains(trimmed)
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

private extension CatalogScope {
    /// Whether a platform belongs in this slice of the catalog.
    func includes(_ platform: InstallablePlatform) -> Bool {
        switch self {
        case .all: true
        case .installed: platform.isInstalled
        case .updatable: platform.isUpdateAvailable
        }
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
            if platform.isUpdateAvailable {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(.blue)
                    .help("Update available")
            }
            if platform.isInstalled {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help("Installed")
            }
        }
    }
}

/// The detail pane for a platform: its identity, version control, boards, and install progress.
private struct PlatformDetail: View {
    let platform: InstallablePlatform
    let operation: MainController.PlatformOperation
    let onInstall: (String) -> Void
    let onUninstall: () -> Void

    /// The version the user picked from the release menu. Starts on the installed version, so
    /// upgrading and downgrading are both a menu pick away, like the Arduino IDE's version menu.
    @State private var pickedVersion: String

    init(
        platform: InstallablePlatform,
        operation: MainController.PlatformOperation,
        onInstall: @escaping (String) -> Void,
        onUninstall: @escaping () -> Void
    ) {
        self.platform = platform
        self.operation = operation
        self.onInstall = onInstall
        self.onUninstall = onUninstall
        _pickedVersion = State(initialValue: platform.defaultVersion)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if let status {
                    Text(status.text)
                        .font(.callout)
                        .foregroundStyle(status.isError ? Color.red : Color.secondary)
                }

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
            versionControl
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

    // MARK: - Version control

    /// The one control for versions: the release menu, the action for the picked release, and the
    /// uninstall button once a platform is installed.
    @ViewBuilder
    private var versionControl: some View {
        if isBusy {
            ProgressView()
                .controlSize(.small)
        } else if platform.versions.isEmpty {
            // Nothing on offer to switch to, so the control is status only.
            if platform.isInstalled {
                HStack(spacing: 8) {
                    installedLabel(includeVersion: true)
                    uninstallButton
                }
            }
        } else {
            HStack(spacing: 8) {
                releaseMenu
                actionSegment
                if platform.isInstalled {
                    uninstallButton
                }
            }
        }
    }

    private var uninstallButton: some View {
        Button(role: .destructive) {
            onUninstall()
        } label: {
            Label("Uninstall", systemImage: "trash")
        }
        .buttonStyle(.bordered)
        .help("Remove the installed platform")
    }

    @ViewBuilder
    private var actionSegment: some View {
        if let pending {
            Button {
                onInstall(pending.version)
            } label: {
                Label(pending.action.label(for: pending.version), systemImage: pending.action.symbol)
                    .foregroundStyle(pending.action.labelColor)
            }
            .buttonStyle(.borderedProminent)
            .tint(pending.action.tint)
        } else {
            installedLabel(includeVersion: false)
        }
    }

    /// The green status chip for being on the newest release. The version is left out while the
    /// release menu already shows it.
    private func installedLabel(includeVersion: Bool) -> some View {
        Label(
            includeVersion ? "Installed \(platform.installedVersion)" : "Installed",
            systemImage: "checkmark.circle.fill"
        )
        .foregroundStyle(.green)
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(Color.green.opacity(0.15), in: .rect(cornerRadius: 6))
    }

    private var releaseMenu: some View {
        Menu {
            ForEach(platform.versions) { release in
                Button {
                    pickedVersion = release.version
                } label: {
                    Label {
                        Text(release.version)
                    } icon: {
                        releaseIcon(release)
                    }
                }
            }
        } label: {
            Text(version)
                .monospacedDigit()
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .fixedSize()
        .help("Choose a version to install")
    }

    /// The marker beside a release: installed, newest, deprecated, or plain.
    @ViewBuilder
    private func releaseIcon(_ release: InstallablePlatformVersion) -> some View {
        if release.version == platform.installedVersion {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else if release.version == platform.latestVersion {
            Image(systemName: "arrow.up.circle.fill")
                .foregroundStyle(.blue)
        } else if release.isDeprecated {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        } else {
            Image(systemName: "circle")
                .foregroundStyle(.tertiary)
        }
    }

    /// The picked version, falling back to the platform's default when a catalog refresh no
    /// longer lists it, so the menu never holds a value that isn't on offer.
    private var version: String {
        platform.version(pickedVersion) != nil ? pickedVersion : platform.defaultVersion
    }

    /// What the left segment installs: the picked release, or the newest release when the installed
    /// one is picked and a newer release is on offer, which keeps upgrading a single click.
    private var pending: (version: String, action: InstallAction)? {
        if let action = platform.installAction(for: version) {
            return (version, action)
        }
        guard platform.isUpdateAvailable else { return nil }
        return (platform.latestVersion, .update)
    }

    /// Whether this platform's own install or uninstall is in flight.
    private var isBusy: Bool {
        if case .installing(let platformID, _) = operation, platformID == platform.id { return true }
        if case .uninstalling(let platformID, _) = operation, platformID == platform.id { return true }
        return false
    }

    private var status: (text: String, isError: Bool)? {
        switch operation {
        case .installing(let platformID, let message) where platformID == platform.id:
            return (message ?? "Installing…", false)
        case .uninstalling(let platformID, let message) where platformID == platform.id:
            return (message ?? "Uninstalling…", false)
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
