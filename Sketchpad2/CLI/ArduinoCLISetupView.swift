//
//  ArduinoCLISetupView.swift
//  Sketchpad2
//

import SwiftUI

/// Blocking sheet that reports arduino-cli setup progress and offers a retry after a failure.
struct ArduinoCLISetupView: View {
    @Environment(MainController.self) private var mainController

    var body: some View {
        VStack(spacing: 16) {
            switch mainController.phase {
            case .failed(let error):
                failureContent(error)
            default:
                progressContent
            }
        }
        .padding(28)
        .frame(width: 360)
    }

    private var progressContent: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text(stepLabel)
                .font(.headline)
        }
    }

    private func failureContent(_ error: ArduinoCLIError) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(error.errorDescription ?? "Unknown error.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                mainController.retry()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private var stepLabel: String {
        switch mainController.phase {
        case .idle, .checking:
            return "Checking arduino-cli"
        case .downloading:
            return "Downloading arduino-cli"
        case .extracting:
            return "Extracting arduino-cli"
        case .startingDaemon:
            return "Starting arduino-cli daemon"
        case .ready:
            return "Ready"
        case .failed:
            return ""
        }
    }
}

#Preview {
    ArduinoCLISetupView()
        .environment(MainController())
}
