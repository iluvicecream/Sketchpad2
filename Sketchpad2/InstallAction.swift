//
//  InstallAction.swift
//  Sketchpad2
//

import SwiftUI

/// What installing a version would do, relative to what's already installed.
///
/// Both the Board Manager and the Library Manager move between versions the same way, so the
/// wording and colors live here instead of in each manager.
enum InstallAction: Equatable, Sendable {
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

    /// The button tint: the accent color for a first install, blue to upgrade, yellow to downgrade.
    var tint: Color? {
        switch self {
        case .install: nil
        case .update: .blue
        case .downgrade: .yellow
        }
    }

    /// Yellow needs dark text to stay readable; the accent and blue fills read fine on white.
    var labelColor: Color {
        switch self {
        case .downgrade: .black
        case .install, .update: .white
        }
    }
}
