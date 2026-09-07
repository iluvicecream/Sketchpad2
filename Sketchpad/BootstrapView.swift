//
//  ArduinoSetupView.swift
//  Bench
//
//  Created by perr on 9/5/2569 BE.
//

import SwiftUI

struct BootstrapView: View {
    @Environment(ArduinoController.self) private var controller

    var body: some View {
        switch controller.phase {
        case .failed:
            VStack(spacing: 24) {
                icon
                    .frame(width: 64, height: 64)
                VStack(spacing: 8) {
                    Text(title)
                        .font(.largeTitle.bold())
                    Text(description)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        default:
            VStack {
                ProgressView()
                    .controlSize(.extraLarge)
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch controller.phase {
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.orange)
        default:
            ProgressView()
                .controlSize(.extraLarge)
        }
    }

    private var title: String {
        switch controller.phase {
        case .failed: "Could not start Sketchpad"
        default: "you shouldn't see this"
        }
    }

    private var description: String {
        switch controller.phase {
        case .failed(let message): message
        default: "you shouldn't see this"
        }
    }
}
