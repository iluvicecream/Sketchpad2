//
//  LibraryManagerView.swift
//  Sketchpad2
//

import SwiftUI

/// Placeholder window for browsing and installing libraries. Real content lands here as the app grows.
struct LibraryManagerView: View {
    var body: some View {
        ContentUnavailableView(
            "Library Manager",
            systemImage: "book",
            description: Text("Browsing and installing libraries will live here.")
        )
        .frame(minWidth: 420, minHeight: 320)
    }
}

#Preview {
    LibraryManagerView()
}
