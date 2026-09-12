//
//  BoardCatalog.swift
//  Sketchpad2
//

import Foundation

/// A platform offered by the arduino-cli indexes, shaped for the Board Manager.
struct InstallablePlatform: Identifiable, Equatable, Sendable {
    /// The platform ID, e.g. `arduino:avr`.
    let id: String
    /// The human-readable name of the release, falling back to the ID.
    let name: String
    /// The newest version the indexes offer, or empty when nothing is installable.
    let latestVersion: String
    /// The installed version, or empty when the platform isn't installed.
    let installedVersion: String
    /// The boards the platform provides.
    let boards: [InstallableBoard]

    var isInstalled: Bool { !installedVersion.isEmpty }

    /// Whether the indexes offer a new version to install.
    var isUpdateAvailable: Bool {
        isInstalled && !latestVersion.isEmpty && latestVersion != installedVersion
    }

    init(_ summary: Cc_Arduino_Cli_Commands_V1_PlatformSummary) {
        self.id = summary.metadata.id
        self.latestVersion = summary.latestVersion
        self.installedVersion = summary.installedVersion

        // Prefer the release the button would install, then whatever is installed, then anything.
        let release = summary.releases[summary.latestVersion]
            ?? summary.releases[summary.installedVersion]
            ?? summary.releases.values.first
        let releaseName = release?.name ?? ""
        self.name = releaseName.isEmpty ? summary.metadata.id : releaseName
        self.boards = (release?.boards ?? []).map(InstallableBoard.init)
    }
}

/// A board offered by a platform, from `platformSearch`.
struct InstallableBoard: Identifiable, Equatable, Sendable {
    let name: String
    /// The fully qualified board name. Only installed platforms report one.
    let fqbn: String

    var id: String { fqbn.isEmpty ? name : fqbn }

    init(_ board: Cc_Arduino_Cli_Commands_V1_Board) {
        self.name = board.name
        self.fqbn = board.fqbn
    }
}
