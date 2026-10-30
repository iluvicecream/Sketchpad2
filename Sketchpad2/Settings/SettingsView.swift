//
//  SettingsView.swift
//  Sketchpad2
//

import SwiftUI

/// Settings window. Waits for the arduino-cli configuration before showing its panes.
struct SettingsView: View {
    @AppStorage("app_theme") private var selectedTheme: AppTheme = .system

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Appearance")) {
                    Picker("Theme", selection: $selectedTheme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.rawValue)
                                .tag(theme)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .frame(width:500)
        }
    }
}
