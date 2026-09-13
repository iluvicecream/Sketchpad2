//
//  BuildOutputLine.swift
//  Sketchpad2
//

import Foundation

/// One line the toolchain printed while verifying or uploading, as the build output pane shows it.
nonisolated struct BuildOutputLine: Identifiable, Equatable, Sendable {
    /// Where the line sits in the pane's list, which is also what identity means here.
    let id: Int
    /// Whether the toolchain printed the line on its error stream, which the pane tints.
    let isError: Bool
    let text: String
}
