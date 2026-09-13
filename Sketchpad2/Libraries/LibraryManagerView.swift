//
//  LibraryManagerView.swift
//  Sketchpad2
//

import SwiftUI

/// Window for browsing and searching the libraries the arduino-cli indexes offer, and for
/// downloading, upgrading, downgrading, and uninstalling them.
struct LibraryManagerView: View {
    @Environment(MainController.self) private var mainController
    @State private var query = ""
    @State private var scope: CatalogScope = .all
    @State private var selection: InstallableLibrary.ID?

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            sidebar
                .navigationSplitViewColumnWidth(min: 260, ideal: 260)
                .searchable(text: $query, placement: .sidebar, prompt: "Search libraries")
                .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.automatic)
        .frame(minWidth: 820, minHeight: 480)
        .task(id: mainController.isReady) {
            guard mainController.isReady else { return }
            await mainController.loadLibraries()
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        switch mainController.libraryCatalog {
        case .failed(let message):
            failure(message)
        case .idle where !mainController.isReady:
            ContentUnavailableView(
                "Waiting for arduino-cli",
                systemImage: "book",
                description: Text("The library catalog appears once setup finishes.")
            )
        default:
            libraryList
        }
    }

    @ViewBuilder
    private var libraryList: some View {
        if showsCatalog {
            VStack(spacing: 0) {
                filterPicker
                catalog
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            ProgressView("Loading libraries…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Whether there's a catalog to show or filter, as opposed to one still loading.
    private var showsCatalog: Bool {
        mainController.libraryCatalog == .loaded || !mainController.installableLibraries.isEmpty
    }

    @ViewBuilder
    private var catalog: some View {
        if libraries.isEmpty {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(libraries, selection: $selection) { library in
                LibrarySidebarRow(library: library)
            }
            .refreshable {
                await mainController.loadLibraries()
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
                    "No libraries found",
                    systemImage: "book",
                    description: Text("The library indexes didn't report anything to browse.")
                )
            case .installed:
                ContentUnavailableView(
                    "No libraries installed",
                    systemImage: "book",
                    description: Text("Libraries you install appear here.")
                )
            case .updatable:
                ContentUnavailableView(
                    "Everything is up to date",
                    systemImage: "checkmark.circle",
                    description: Text("No installed library has a newer version on offer.")
                )
            }
        }
    }

    private func failure(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't load libraries", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") {
                Task { await mainController.loadLibraries() }
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let library = selectedLibrary {
            LibraryDetail(
                library: library,
                operation: mainController.libraryOperation,
                onInstall: { version in
                    Task { await mainController.installLibrary(library, version: version) }
                },
                onUninstall: {
                    Task { await mainController.uninstallLibrary(library) }
                }
            )
            .id(library.id)
        } else {
            ContentUnavailableView(
                "Select a library",
                systemImage: "book",
                description: Text("Pick a library from the sidebar to see what it does.")
            )
        }
    }

    /// The libraries in the picked scope matching the current search text.
    private var libraries: [InstallableLibrary] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return mainController.installableLibraries.filter { library in
            guard scope.includes(library) else { return false }
            guard !trimmed.isEmpty else { return true }
            return library.name.localizedCaseInsensitiveContains(trimmed)
                || library.author.localizedCaseInsensitiveContains(trimmed)
                || library.sentence.localizedCaseInsensitiveContains(trimmed)
                || library.category.localizedCaseInsensitiveContains(trimmed)
        }
    }

    /// The selected library, resolved against the full catalog so a filtered-out row stays selected.
    private var selectedLibrary: InstallableLibrary? {
        guard let selection else { return nil }
        return mainController.installableLibraries.first { $0.id == selection }
    }
}

private extension CatalogScope {
    /// Whether a library belongs in this slice of the catalog.
    func includes(_ library: InstallableLibrary) -> Bool {
        switch self {
        case .all: true
        case .installed: library.isInstalled
        case .updatable: library.isUpdateAvailable
        }
    }
}

/// One library in the sidebar: its name, version, and installed marker.
private struct LibrarySidebarRow: View {
    let library: InstallableLibrary

    var body: some View {
        HStack(spacing: 8) {
            Text(library.name)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            if !version.isEmpty {
                Text(version)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if library.isUpdateAvailable {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(.blue)
                    .help("Update available")
            }
            if library.isInstalled {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help("Installed")
            }
        }
    }

    /// The installed version when there is one, otherwise the newest the index offers.
    private var version: String {
        library.isInstalled ? library.installedVersion : library.latestVersion
    }
}

/// The detail pane for a library: what it does, who wrote it, and version control for installing,
/// upgrading, downgrading, and uninstalling it.
private struct LibraryDetail: View {
    let library: InstallableLibrary
    let operation: MainController.LibraryOperation
    let onInstall: (String) -> Void
    let onUninstall: () -> Void

    /// The version the user picked from the release menu. Starts on the installed version, so
    /// upgrading and downgrading are both a menu pick away, like the Arduino IDE's version menu.
    @State private var pickedVersion: String

    init(
        library: InstallableLibrary,
        operation: MainController.LibraryOperation,
        onInstall: @escaping (String) -> Void,
        onUninstall: @escaping () -> Void
    ) {
        self.library = library
        self.operation = operation
        self.onInstall = onInstall
        self.onUninstall = onUninstall
        _pickedVersion = State(initialValue: library.defaultVersion)
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

                if !library.sentence.isEmpty || !library.paragraph.isEmpty {
                    aboutSection
                }

                if !details.isEmpty {
                    detailsSection
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(library.name)
                    .font(.largeTitle.bold())
                    .textSelection(.enabled)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            versionControl
        }
    }

    /// A `1.2.3 · Arduino · Alexander Entinger` style line, dropping whatever is missing.
    private var subtitle: String {
        [
            library.latestVersion.isEmpty ? nil : "v\(library.latestVersion)",
            library.types.first,
            library.author.isEmpty ? nil : library.author,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    // MARK: - Version control

    /// The one control for versions: the release menu, the action for the picked release, and the
    /// uninstall button once the library is installed.
    @ViewBuilder
    private var versionControl: some View {
        if isBusy {
            ProgressView()
                .controlSize(.small)
        } else if library.versions.isEmpty {
            // Nothing on offer to switch to, so the control is status only.
            if library.isInstalled {
                HStack(spacing: 8) {
                    installedLabel(includeVersion: true)
                    uninstallButton
                }
            }
        } else {
            HStack(spacing: 8) {
                releaseMenu
                actionSegment
                if library.isInstalled {
                    uninstallButton
                }
            }
        }
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

    private var uninstallButton: some View {
        Button(role: .destructive) {
            onUninstall()
        } label: {
            Label("Uninstall", systemImage: "trash")
        }
        .buttonStyle(.bordered)
        .help("Remove the installed library")
    }

    /// The green status chip for being on the newest release. The version is left out while the
    /// release menu already shows it.
    private func installedLabel(includeVersion: Bool) -> some View {
        Label(
            includeVersion ? "Installed \(library.installedVersion)" : "Installed",
            systemImage: "checkmark.circle.fill"
        )
        .foregroundStyle(.green)
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(Color.green.opacity(0.15), in: .rect(cornerRadius: 6))
    }

    private var releaseMenu: some View {
        Menu {
            ForEach(library.versions, id: \.self) { version in
                Button {
                    pickedVersion = version
                } label: {
                    Label {
                        Text(version)
                    } icon: {
                        releaseIcon(version)
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

    /// The marker beside a release: installed, newest, or plain.
    @ViewBuilder
    private func releaseIcon(_ version: String) -> some View {
        if version == library.installedVersion {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else if version == library.latestVersion {
            Image(systemName: "arrow.up.circle.fill")
                .foregroundStyle(.blue)
        } else {
            Image(systemName: "circle")
                .foregroundStyle(.tertiary)
        }
    }

    /// The picked version, falling back to the library's default when a catalog refresh no longer
    /// lists it, so the menu never holds a value that isn't on offer.
    private var version: String {
        library.hasVersion(pickedVersion) ? pickedVersion : library.defaultVersion
    }

    /// What the action button installs: the picked release, or the newest release when the
    /// installed one is picked and a newer release is on offer, which keeps upgrading a single click.
    private var pending: (version: String, action: InstallAction)? {
        if let action = library.installAction(for: version) {
            return (version, action)
        }
        guard library.isUpdateAvailable else { return nil }
        return (library.latestVersion, .update)
    }

    /// Whether this library's own install or uninstall is in flight.
    private var isBusy: Bool {
        if case .installing(let name, _) = operation, name == library.name { return true }
        if case .uninstalling(let name, _) = operation, name == library.name { return true }
        return false
    }

    private var status: (text: String, isError: Bool)? {
        switch operation {
        case .installing(let name, let message) where name == library.name:
            return (message ?? "Installing…", false)
        case .uninstalling(let name, let message) where name == library.name:
            return (message ?? "Uninstalling…", false)
        case .failed(let name, let message) where name == library.name:
            return (message, true)
        default:
            return nil
        }
    }

    // MARK: - Sections

    private var aboutSection: some View {
        GroupBox("About") {
            VStack(alignment: .leading, spacing: 8) {
                if !library.sentence.isEmpty {
                    Text(library.sentence)
                        .font(.headline)
                        .textSelection(.enabled)
                }
                if !library.paragraph.isEmpty {
                    Text(library.paragraph)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    /// The index fields worth showing, skipping the ones this library leaves empty.
    private var details: [(label: String, value: String)] {
        [
            ("Author", library.author),
            ("Maintainer", library.maintainer),
            ("Category", library.category),
            ("License", library.license),
            ("Architectures", library.architectures.joined(separator: ", ")),
            ("Types", library.types.joined(separator: ", ")),
        ]
        .filter { !$0.value.isEmpty }
    }

    private var detailsSection: some View {
        GroupBox("Details") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(details, id: \.label) { detail in
                    LabeledContent(detail.label, value: detail.value)
                }
                if let website = URL(string: library.website), !library.website.isEmpty {
                    LabeledContent("Website") {
                        Link(library.website, destination: website)
                    }
                }
            }
            .padding(6)
        }
    }
}

#Preview {
    LibraryManagerView()
        .environment(MainController())
}
