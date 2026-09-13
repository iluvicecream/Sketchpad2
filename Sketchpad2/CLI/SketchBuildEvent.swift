//
//  SketchBuildEvent.swift
//  Sketchpad2
//

import Foundation

/// One message from a build or upload running on the daemon.
///
/// The toolchain reports as it works, so the editor can show what it prints rather than waiting for
/// the whole build to finish.
nonisolated enum SketchBuildEvent: Sendable {
    /// Bytes the toolchain printed, tagged with the stream they came from. Chunks aren't aligned to
    /// lines, so the reader has to join them back up.
    case output(Data, isError: Bool)
    /// How far along the daemon says the build is, e.g. `Compiling libraries...`.
    case progress(String)
}
