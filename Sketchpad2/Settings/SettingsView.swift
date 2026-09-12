//
//  SettingsView.swift
//  Sketchpad2
//

import SwiftUI

/// Placeholder Settings window. Real panes land here as the app grows.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            ArduinoCLISettingsView()
                .tabItem {
                    Label("Arduino CLI", systemImage: "cpu")
                }
        }
        .frame(width: 440)
    }
}

private struct GeneralSettingsView: View {
    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        guard let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String else {
            return short
        }
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: version)
            }

            Section {
                Text("Editing, board, and appearance preferences will live here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 170)
    }
}

private struct ArduinoCLISettingsView: View {
    @Environment(MainController.self) private var mainController

    var body: some View {
        Form {
            Section("arduino-cli") {
                LabeledContent("Status", value: statusText)
                LabeledContent("Daemon port", value: mainController.daemonPort.map(String.init) ?? "—")
                LabeledContent("Instance", value: instanceText)
            }
        }
        .formStyle(.grouped)
        .frame(height: 170)
    }

    private var statusText: String {
        switch mainController.phase {
        case .idle:
            return "Not started"
        case .checking:
            return "Checking installation"
        case .downloading:
            return "Downloading"
        case .extracting:
            return "Extracting"
        case .startingDaemon:
            return "Starting daemon"
        case .ready:
            return "Running"
        case .failed(let error):
            return error.errorDescription ?? "Failed"
        }
    }

    private var instanceText: String {
        guard let instance = mainController.instance else { return "—" }
        return "id \(instance.id)"
    }
}

#Preview {
    SettingsView()
        .environment(MainController())
}
