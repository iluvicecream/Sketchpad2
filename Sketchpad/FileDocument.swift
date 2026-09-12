//
//  FileDocument.swift
//  Sketchpad
//
//  Created by perr on 9/12/2569 BE.
//

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static var inoSketch: UTType {
        UTType(exportedAs: "com.perr.Sketchpad.ino")
    }
}

struct SketchDocument: FileDocument {
    var mainCode: String
    
    static var readableContentTypes: [UTType] { [.inoSketch, .plainText] }

    init(mainCode: String = "void setup() {\n\n}\n\nvoid loop() {\n\n}") {
        self.mainCode = mainCode
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.mainCode = string
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(mainCode.utf8)
        return .init(regularFileWithContents: data)
    }
}
