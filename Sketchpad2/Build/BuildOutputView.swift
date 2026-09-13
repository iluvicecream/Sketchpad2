//
//  BuildOutputView.swift
//  Sketchpad2
//

import SwiftUI

/// The pane under the editor that shows what the toolchain printed while verifying or uploading,
/// and how the last build ended.
struct BuildOutputView: View {
    @Environment(MainController.self) private var mainController
    /// Hides the pane. The output stays put, so the next build can show it again.
    let onHide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            output
        }
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 8) {
            statusIcon
            Text(status)
                .font(.callout)
                .lineLimit(2)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            Button("Clear") {
                mainController.clearBuildOutput()
            }
            .buttonStyle(.borderless)
            .help("Clear the output")
            Button {
                onHide()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Hide the build output")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch mainController.sketchOperation {
        case .verifying, .uploading:
            ProgressView()
                .controlSize(.small)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case .finished:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .idle:
            Image(systemName: "terminal")
                .foregroundStyle(.secondary)
        }
    }

    /// The pane's headline: what the editor is doing, or how it went.
    private var status: String {
        switch mainController.sketchOperation {
        case .idle:
            "Build output"
        case .verifying(let message):
            message.map { "Verifying… \($0)" } ?? "Verifying…"
        case .uploading(let message):
            message.map { "Uploading… \($0)" } ?? "Uploading…"
        case .failed(let message):
            message
        case .finished(let message):
            message
        }
    }

    private var output: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if mainController.buildOutput.isEmpty {
                        Text("Nothing printed yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(mainController.buildOutput) { line in
                            row(line)
                        }
                    }
                }
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: mainController.buildOutput.count) { _, _ in
                guard let last = mainController.buildOutput.last else { return }
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    /// One printed line, with the empty ones kept so the output's spacing matches the toolchain's.
    private func row(_ line: BuildOutputLine) -> some View {
        Text(line.text.isEmpty ? " " : line.text)
            .foregroundStyle(line.isError ? Color.red : Color.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(line.id)
    }
}
