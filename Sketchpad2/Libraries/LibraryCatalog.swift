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

    init(_ library: Cc_Arduino_Cli_Commands_V1_SearchedLibrary) {
        let release = library.latest

        self.name = library.name
        self.latestVersion = release.version
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
}
