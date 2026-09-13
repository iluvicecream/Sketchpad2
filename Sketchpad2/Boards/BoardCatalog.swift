//
//  BoardCatalog.swift
//  Sketchpad2
//

import Foundation

/// What installing a platform version would do, relative to what's already installed.
enum PlatformInstallAction: Equatable, Sendable {
    /// Nothing is installed yet.
    case install
    /// The chosen version is newer than the installed one.
    case update
    /// The chosen version is older than the installed one.
    case downgrade

    /// The install button's text for a version, e.g. `Update to 1.8.7`.
    func label(for version: String) -> String {
        switch self {
        case .install: "Install \(version)"
        case .update: "Update to \(version)"
        case .downgrade: "Downgrade to \(version)"
        }
    }

    /// The symbol shown beside the install button's text, pointing the way the version moves.
    var symbol: String {
        switch self {
        case .install, .downgrade: "arrow.down.circle.fill"
        case .update: "arrow.up.circle.fill"
        }
    }
}

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
    /// Every release the indexes offer, newest first.
    let versions: [InstallablePlatformVersion]

    var isInstalled: Bool { !installedVersion.isEmpty }

    /// Whether the indexes offer a version newer than the installed one.
    var isUpdateAvailable: Bool {
        isInstalled && !latestVersion.isEmpty && Self.isNewer(latestVersion, than: installedVersion)
    }

    /// The version the release menu starts on: what's installed, else the newest on offer.
    var defaultVersion: String {
        self.version(installedVersion) != nil ? installedVersion : latestVersion
    }

    /// The boards of the release the release menu starts on.
    var boards: [InstallableBoard] {
        boards(for: defaultVersion)
    }

    /// The boards of the release with the given version, or none when the indexes don't offer it.
    func boards(for version: String) -> [InstallableBoard] {
        self.version(version)?.boards ?? []
    }

    /// The release with the given version, if the indexes offer it.
    func version(_ version: String) -> InstallablePlatformVersion? {
        versions.first { $0.version == version }
    }

    /// What installing the given version would do, or `nil` when it's already installed.
    func installAction(for version: String) -> PlatformInstallAction? {
        guard isInstalled else { return .install }
        if Self.isNewer(version, than: installedVersion) { return .update }
        if Self.isNewer(installedVersion, than: version) { return .downgrade }
        return nil
    }

    /// Whether `lhs` is a newer release than `rhs`, comparing numbers numerically so `1.8.10`
    /// sorts above `1.8.6` and a pre-release sorts below its final release.
    static func isNewer(_ lhs: String, than rhs: String) -> Bool {
        lhs.compare(rhs, options: .numeric) == .orderedDescending
    }

    init(_ summary: Cc_Arduino_Cli_Commands_V1_PlatformSummary) {
        self.id = summary.metadata.id
        self.latestVersion = summary.latestVersion
        self.installedVersion = summary.installedVersion
        self.versions = summary.releases
            .filter { !$0.key.isEmpty }
            .map { InstallablePlatformVersion(version: $0.key, release: $0.value) }
            .sorted { Self.isNewer($0.version, than: $1.version) }

        // Prefer the release the install button would act on, then whatever is installed,
        // then anything the indexes offer.
        let release = summary.releases[summary.latestVersion]
            ?? summary.releases[summary.installedVersion]
            ?? summary.releases.values.first
        let releaseName = release?.name ?? ""
        self.name = releaseName.isEmpty ? summary.metadata.id : releaseName
    }
}

/// One release of a platform offered by the indexes.
struct InstallablePlatformVersion: Identifiable, Equatable, Sendable {
    /// The version string, e.g. `1.8.6`.
    let version: String
    /// Whether the indexes mark this release as deprecated.
    let isDeprecated: Bool
    /// The boards the release provides.
    let boards: [InstallableBoard]

    var id: String { version }

    init(version: String, release: Cc_Arduino_Cli_Commands_V1_PlatformRelease) {
        self.version = version
        self.isDeprecated = release.deprecated
        self.boards = release.boards.map(InstallableBoard.init)
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
