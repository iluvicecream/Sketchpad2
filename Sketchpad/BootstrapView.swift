//
//  ArduinoSetupView.swift
//  Bench
//
//  Created by perr on 9/5/2569 BE.
//

import SwiftUI

struct ArduinoSetupView: View {
    @Environment(ArduinoController.self) private var controller
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @State private var didOpenProjects = false
    
    var body: some View {
        ArduinoPhaseView(phase: controller.phase,coreId:controller.coreInstanceId)
            .task {
                await controller.bootstrap()
            }
            .onChange(of: controller.phase) { _, newPhase in
                guard newPhase == .ready, !didOpenProjects else { return }
                didOpenProjects = true
                openWindow(id: "projects")
                dismiss()
            }
    }
}

struct ArduinoPhaseView: View {
    let phase: ArduinoController.Phase
    let coreId: Int32?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            icon
                .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.largeTitle.bold())
                Text(description)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var icon: some View {
        switch phase {
        case .checking, .installing, .startingDaemon:
            ProgressView()
                .controlSize(.extraLarge)
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
        case .stopped:
            Image(systemName: "stop.circle")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.orange)
        }
    }

    private var title: String {
        switch phase {
        case .checking: "Checking Arduino CLI"
        case .installing: "Installing Arduino CLI"
        case .startingDaemon: "Starting Daemon"
        case .ready: "Daemon Started Successfully"
        case .stopped: "Daemon Stopped"
        case .failed: "Could not install Arduino CLI"
        }
    }

    private var description: String {
        switch phase {
        case .checking: "Verifying the Arduino CLI installation."
        case .installing: "Downloading and installing the Arduino CLI."
        case .startingDaemon: "Launching the Arduino daemon."
        case .ready: "The Arduino daemon is running and ready. With core id \(coreId?.description ?? "unknown")"
        case .stopped: "The Arduino daemon is not running."
        case .failed(let message): message
        }
    }
}

#Preview("Checking") {
    ArduinoPhaseView(phase: .checking, coreId: 0)
}

#Preview("Installing") {
    ArduinoPhaseView(phase: .installing, coreId: 0)
}

#Preview("Starting Daemon") {
    ArduinoPhaseView(phase: .startingDaemon,coreId: 0)
}

#Preview("Ready") {
    ArduinoPhaseView(phase: .ready, coreId: 0)
}

#Preview("Stopped") {
    ArduinoPhaseView(phase: .stopped, coreId: 0)
}

#Preview("Failed") {
    ArduinoPhaseView(phase: .failed("The Arduino CLI could not be downloaded."),coreId:0)
}
