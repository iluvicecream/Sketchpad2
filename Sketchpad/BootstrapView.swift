//
//  ArduinoSetupView.swift
//  Bench
//
//  Created by perr on 9/5/2569 BE.
//

import SwiftUI

struct BootstrapView: View {
    @Environment(ArduinoController.self) private var controller
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        BootstrapPhaseView(phase: controller.phase,coreId:controller.coreInstanceId)
            .task {
                await controller.bootstrap()
            }
            .onChange(of: controller.phase, initial: true) { _, newPhase in
                if case .ready = newPhase {
                    openWindow(id: "projects")
                    dismiss()
                    controller.isBootstrapped = true
                }
            }
            
    }
}

struct BootstrapPhaseView: View {
    let phase: ArduinoController.Phase
    let coreId: Int32?

    var body: some View {
        switch phase {
        case .installing,.failed:
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
        default:
            EmptyView()
                .hidden()
        }
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
