//
//  BoardManagerView.swift
//  Sketchpad2
//

import SwiftUI

/// Placeholder window for browsing and installing boards. Real content lands here as the app grows.
struct BoardManagerView: View {
    var body: some View {
        ContentUnavailableView(
            "Board Manager",
            systemImage: "cpu",
            description: Text("Browsing and installing boards will live here.")
        )
        .frame(minWidth: 420, minHeight: 320)
    }
}

#Preview {
    BoardManagerView()
}
