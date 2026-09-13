//
//  LibraryManagerView.swift
//  Sketchpad2
//

import SwiftUI

/// Window for browsing and searching the libraries the arduino-cli indexes offer.
///
/// Installing and removing libraries lands here as the app grows; for now the window browses.
struct LibraryManagerView: View {
    @Environment(MainController.self) private var mainController
    @State private var query = ""
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
        if libraries.isEmpty {
            if mainController.libraryCatalog == .loaded {
                emptyState
            } else {
                ProgressView("Loading libraries…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            List(libraries, selection: $selection) { library in
                LibrarySidebarRow(library: library)
            }
            .refreshable {
                await mainController.loadLibraries()
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView(
                "No libraries found",
                systemImage: "book",
                description: Text("The library indexes didn't report anything to browse.")
            )
        } else {
            ContentUnavailableView.search(text: query)
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
            LibraryDetail(library: library)
        } else {
            ContentUnavailableView(
                "Select a library",
                systemImage: "book",
                description: Text("Pick a library from the sidebar to see what it does.")
            )
        }
    }

    /// The libraries matching the current search text, or all of them when the field is empty.
    private var libraries: [InstallableLibrary] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return mainController.installableLibraries }
        return mainController.installableLibraries.filter { library in
            library.name.localizedCaseInsensitiveContains(trimmed)
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

/// One library in the sidebar: its name and the version the index offers.
private struct LibrarySidebarRow: View {
    let library: InstallableLibrary

    var body: some View {
        HStack(spacing: 8) {
            Text(library.name)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            if !library.latestVersion.isEmpty {
                Text(library.latestVersion)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The detail pane for a library: what it does, who wrote it, and which versions it has.
private struct LibraryDetail: View {
    let library: InstallableLibrary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if !library.sentence.isEmpty || !library.paragraph.isEmpty {
                    aboutSection
                }

                if !details.isEmpty {
                    detailsSection
                }

                if !library.versions.isEmpty {
                    versionsSection
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(library.name)
                .font(.largeTitle.bold())
                .textSelection(.enabled)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
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

    private var versionsSection: some View {
        GroupBox("Versions (\(library.versions.count))") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(library.versions, id: \.self) { version in
                    Text(version)
                        .monospacedDigit()
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }
}

#Preview {
    LibraryManagerView()
        .environment(MainController())
}
