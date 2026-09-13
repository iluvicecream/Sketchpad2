//
//  CatalogScope.swift
//  Sketchpad2
//

import SwiftUI

/// The slice of a catalog the Board Manager and Library Manager list, mirroring the Arduino
/// IDE's board and library filters.
enum CatalogScope: String, CaseIterable, Identifiable {
    /// Everything the indexes offer.
    case all
    /// Only what's installed.
    case installed
    /// Only what has a newer version on offer.
    case updatable

    var id: Self { self }

    /// The text of the filter's tab.
    var title: String {
        switch self {
        case .all: "All"
        case .installed: "Installed"
        case .updatable: "Updatable"
        }
    }
}

/// The tab-style scope filter both managers pin above their lists.
struct CatalogScopePicker: View {
    @Binding var scope: CatalogScope

    var body: some View {
        Picker("Show", selection: $scope) {
            ForEach(CatalogScope.allCases) { scope in
                Text(scope.title).tag(scope)
            }
        }
        .pickerStyle(.tabs)
        .labelsHidden()
        .controlSize(.large)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}
