//
//  SketchSource.swift
//  Sketchpad2
//

import Foundation

/// The sketch a build acts on: the editor's text, named after the document it came from.
///
/// The builder wants a sketch *folder* holding `<name>.ino`, which is neither where a document
/// happens to live nor something an untitled document has, so the text is staged into a folder of
/// its own first. That folder is kept between builds so the board's core is compiled once instead
/// of on every verify.
nonisolated struct SketchSource: Equatable, Sendable {
    /// The sketch's name, e.g. `test1232`. It names the folder and the sketch file inside it.
    let name: String
    /// The editor's text, which is what gets built.
    let text: String

    init(name: String, text: String) {
        self.name = Self.validName(name)
        self.text = text
    }

    /// Writes the text into the sketch's staged folder and returns it, so the build sees the
    /// editor's current text — unsaved edits included — rather than the last file on disk.
    func stage() throws -> URL {
        let manager = FileManager.default
        let folder = try Self.stagingRoot().appending(path: name, directoryHint: .isDirectory)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        try text.write(to: folder.appending(path: "\(name).ino"), atomically: true, encoding: .utf8)
        return folder
    }

    /// Where staged sketches live. The build directory the compiler keeps inside each sketch makes
    /// this cache-like data rather than anything worth backing up.
    private static func stagingRoot() throws -> URL {
        let caches = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "com.perr.Sketchpad2/Sketch", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        return caches
    }

    /// A name the builder accepts, since it becomes a folder and a C file: ASCII letters, digits,
    /// dashes and underscores, and never nothing at all.
    private static func validName(_ raw: String) -> String {
        let cleaned = raw.map { character -> Character in
            let keep = character.isASCII && (character.isLetter || character.isNumber)
            return keep || character == "-" || character == "_" ? character : "_"
        }

        let name = String(cleaned).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return name.isEmpty ? "Sketch" : name
    }
}
