//
//  Sketchpad2Document.swift
//  Sketchpad2
//
//  Created by perr on 9/12/2569 BE.
//

import SwiftUI
import UniformTypeIdentifiers

@Observable
final class Sketchpad2Document: Document {

    static let readableContentTypes: [UTType] = [.inoSketch]

    var text: String

    init(text: String = "void setup() {\n\n}\n\nvoid loop() {\n\n}") {
        self.text = text
    }

    nonisolated func reader(
        configuration: sending ReadConfiguration
    ) -> sending FileWrapperDocumentReader<String> {
        FileWrapperDocumentReader(configuration) { fileWrapper in
            guard let data = fileWrapper.regularFileContents else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return String(decoding: data, as: UTF8.self)
        }
    }

    nonisolated func writer(
        configuration: sending WriteConfiguration
    ) -> sending FileWrapperDocumentWriter<String> {
        FileWrapperDocumentWriter(configuration) { snapshot, _ in
            FileWrapper(regularFileWithContents: Data(snapshot.utf8))
        }
    }

    @MainActor
    func snapshot(contentType: UTType) async throws -> sending String {
        text
    }

    @MainActor
    func apply(snapshot: sending String, previous: sending String?) async throws {
        text = snapshot
    }
}

extension UTType {
    static var inoSketch: UTType {
        UTType(importedAs: "com.perr.ino")
    }
}
