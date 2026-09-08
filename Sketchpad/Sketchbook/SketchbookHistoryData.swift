//
//  SketchbookHistoryData.swift
//  Sketchpad
//
//  Created by perr on 9/8/2569 BE.
//

import Foundation
import SwiftData

@Model
final class SketchbookHistoryData {
    @Attribute(.unique) var id: UUID
    var sketch_name: String
    var sketch_main_dir: String
    var sketch_dir: String
    var last_opened: Date

    init(
        sketch_name: String,
        sketch_main_dir: String,
        sketch_dir: String,
        last_opened: Date = Date(),
    ) {
        self.id = UUID()
        self.sketch_name = sketch_name
        self.sketch_main_dir = sketch_main_dir
        self.sketch_dir = sketch_dir
        self.last_opened = last_opened
    }
}

@MainActor
final class SketchbookHistoryManager {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func recordAccess(name: String, mainDir: String, dir: String) {
        var descriptor = FetchDescriptor<SketchbookHistoryData>(
            predicate: #Predicate { $0.sketch_name == name }
        )
        descriptor.fetchLimit = 1

        if let existing = try? modelContext.fetch(descriptor).first {
            existing.sketch_name = name
            existing.sketch_main_dir = mainDir
            existing.last_opened = Date()
        } else {
            let newEntry = SketchbookHistoryData(
                sketch_name: name,
                sketch_main_dir: mainDir,
                sketch_dir: dir,
                last_opened: Date()
            )
            modelContext.insert(newEntry)
        }
        try? modelContext.save()
    }

    func fetchAll() -> [SketchbookHistoryData] {
        let descriptor = FetchDescriptor<SketchbookHistoryData>(
            sortBy: [SortDescriptor(\.last_opened, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func delete(_ item: SketchbookHistoryData) {
        modelContext.delete(item)
        try? modelContext.save()
    }
}
