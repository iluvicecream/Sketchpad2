//
//  ArduinoSetupView.swift
//  Bench
//
//  Created by perr on 9/5/2569 BE.
//

import SwiftUI

struct ArduinoSetupView: View {
    private enum InstallState {
        case checking
        case installing
        case installed
        case failed(message: String)
    }

    @State private var state: InstallState = .checking

    var body: some View {
        VStack(spacing: 16) {
            switch state {
            case .checking:
                ProgressView("Checking Arduino CLI…")
            case .installing:
                ProgressView("Installing Arduino CLI…")
            case .installed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text("Arduino CLI is installed")
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                Text("Could not install Arduino CLI")
                    .font(.headline)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .task {
            await checkArduinoCLI()
        }
    }

    private func checkArduinoCLI() async {
        if await ArduinoCliDownloader.shared.isInstalled {
            state = .installed
            return
        }

        state = .installing
        do {
            try await ArduinoCliDownloader.shared.ensureInstalled()
            state = .installed
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }
}

#Preview {
    ArduinoSetupView()
}
