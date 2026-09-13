//
//  LibraryCatalog.swift
//  Sketchpad2
//

import Foundation

/// A library offered by the arduino-cli indexes, shaped for the Library Manager.
///
/// The index reports the details of the newest release only, so every field but `versions`
/// describes that release.
struct InstallableLibrary: Identifiable, Equatable, Sendable {
    /// The library name, which the index uses as its identity.
    let name: String
    /// The version of the newest release the index offers.
    let latestVersion: String
    /// The installed version, or empty when the library isn't installed.
    let installedVersion: String
    /// Value of the `author` field in library.properties.
    let author: String
    /// Value of the `maintainer` field in library.properties.
    let maintainer: String
    /// Value of the `sentence` field in library.properties.
    let sentence: String
    /// Value of the `paragraph` field in library.properties.
    let paragraph: String
    /// Value of the `website` field in library.properties.
    let website: String
    /// Value of the `category` field in library.properties.
    let category: String
    /// Value of the `license` field in library.properties.
    let license: String
    /// Value of the `architectures` field in library.properties.
    let architectures: [String]
    /// The type categories the index lists, e.g. `Arduino` or `Contributed`.
    let types: [String]
    /// Every version the index offers, newest first.
    let versions: [String]

    var id: String { name }

    var isInstalled: Bool { !installedVersion.isEmpty }

    /// Whether the index offers a version newer than the installed one.
    var isUpdateAvailable: Bool {
        isInstalled && !latestVersion.isEmpty && VersionOrder.isNewer(latestVersion, than: installedVersion)
    }

    /// The version the release menu starts on: what's installed, else the newest on offer.
    var defaultVersion: String {
        hasVersion(installedVersion) ? installedVersion : latestVersion
    }

    /// Whether the index offers the given version.
    func hasVersion(_ version: String) -> Bool {
        versions.contains(version)
    }

    /// What installing the given version would do, or `nil` when it's already installed.
    func installAction(for version: String) -> InstallAction? {
        guard isInstalled else { return .install }
        if VersionOrder.isNewer(version, than: installedVersion) { return .update }
        if VersionOrder.isNewer(installedVersion, than: version) { return .downgrade }
        return nil
    }

    init(_ library: Cc_Arduino_Cli_Commands_V1_SearchedLibrary, installedVersion: String = "") {
        let release = library.latest

        self.name = library.name
        self.latestVersion = release.version
        self.installedVersion = installedVersion
        self.author = release.author
        self.maintainer = release.maintainer
        self.sentence = release.sentence
        self.paragraph = release.paragraph
        self.website = release.website
        self.category = release.category
        self.license = release.license
        self.architectures = release.architectures
        self.types = release.types
        self.versions = library.availableVersions
            .filter { !$0.isEmpty }
            .sorted { VersionOrder.isNewer($0, than: $1) }
    }

    /// A library that's installed but missing from the index, so only its name and version are
    /// known. Offering these keeps uninstall reachable for manually installed libraries.
    init(installedName: String, version: String) {
        self.name = installedName
        self.latestVersion = version
        self.installedVersion = version
        self.author = ""
        self.maintainer = ""
        self.sentence = ""
        self.paragraph = ""
        self.website = ""
        self.category = ""
        self.license = ""
        self.architectures = []
        self.types = []
        self.versions = []
    }
}

/// One library reported by `libraryList`, reduced to what the Library Manager tracks.
nonisolated struct InstalledLibrary: Identifiable, Equatable, Sendable {
    /// The library name, which the index uses as its identity.
    let name: String
    /// Value of the `version` field in library.properties.
    let version: String

    var id: String { name }

    init(_ library: Cc_Arduino_Cli_Commands_V1_InstalledLibrary) {
        self.name = library.library.name
        self.version = library.library.version
    }
}
