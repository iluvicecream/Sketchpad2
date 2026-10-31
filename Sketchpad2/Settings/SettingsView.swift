//
//  SettingsView.swift
//  Sketchpad2
//

import SwiftUI

enum SettingsTabValue: Hashable {
    case appearance
}

struct SettingsView: View {
    @AppStorage("app_theme") private var selectedTheme: AppTheme = .system
    @State var selectedTab: SettingsTabValue = .appearance

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                NavigationLink(value: SettingsTabValue.appearance) {
                    Label("Appearance",systemImage: "interface.window").tag(SettingsTabValue.appearance)
                }
            }
            .navigationTitle("Sidebar")
            .toolbar(removing: .sidebarToggle)
        } detail: {
            switch selectedTab {
            case .appearance:
                VStack(alignment:.leading) {
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
                }
            }
        }
    }
}
