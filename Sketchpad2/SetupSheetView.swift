//
//  SetupSheetView.swift
//  Sketchpad2
//

import SwiftUI

struct SetupSheetView: View {
    var coreBox = CoreServiceBox.sharedBox

    var body: some View {
        VStack(spacing: 16) {
            switch coreBox.boxState {
            case .daemonBoxError:
                failureContent(coreBox.boxState)
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
            Text(stateLabel)
                .font(.headline)
        }
    }

    private func failureContent(_ errorState: CoreBoxState) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(errorLabel)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                coreBox.startTask()
            }
            .keyboardShortcut(.defaultAction)
        }
    }
    
    private var errorLabel: String {
        switch coreBox.boxState {
        case .daemonBoxError:
            switch coreBox.daemonBox.boxState {
            case .failedToDownloadDaemonBadResponse:
                return "Failed To Download Daemon Binary (BAD_RESPONSE_CODE)"
            default:
                return "Unknown Error"
            }
        default:
            return "Unknown Error"
        }
    }

    private var stateLabel: String {
        switch coreBox.boxState {
        default:
            return "Setting Up Your Environment"
        }
    }
}
