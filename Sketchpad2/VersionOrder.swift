//
//  VersionOrder.swift
//  Sketchpad2
//

import Foundation

/// Orders the version strings the board and library indexes report.
enum VersionOrder {
    /// Whether `lhs` is a newer release than `rhs`, comparing numbers numerically so `1.8.10`
    /// sorts above `1.8.6` and a pre-release sorts below its final release.
    static func isNewer(_ lhs: String, than rhs: String) -> Bool {
        lhs.compare(rhs, options: .numeric) == .orderedDescending
    }
}
