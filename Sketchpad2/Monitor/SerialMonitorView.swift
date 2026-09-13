//
//  SerialMonitorView.swift
//  Sketchpad2
//

import SwiftUI

/// Window for watching what the board prints and for sending lines back to it.
struct SerialMonitorView: View {
    @Environment(MainController.self) private var mainController
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            output
            Divider()
            sendBar
        }
        .frame(minWidth: 460, minHeight: 280)
        .task(id: mainController.isReady) {
            guard mainController.isReady else { return }
            await mainController.loadMonitorSettings()
            await mainController.openSerialMonitor()
        }
        .onChange(of: mainController.selectedPortID) { _, _ in
            Task { await mainController.reconnectSerialMonitor() }
        }
        .onDisappear {
            mainController.closeSerialMonitor()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            statusIcon
            Text(status)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            baudRatePicker
            Button("Clear") {
                mainController.clearMonitorOutput()
            }
            .buttonStyle(.borderless)
            .help("Clear the monitor's output")
            connectButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch mainController.serialMonitor {
        case .closed:
            Image(systemName: "cable.connector.slash")
                .foregroundStyle(.secondary)
        case .opening:
            ProgressView()
                .controlSize(.small)
        case .open:
            Image(systemName: "cable.connector")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    /// The window's headline: the port the monitor is listening on, or why it isn't listening.
    private var status: String {
        switch mainController.serialMonitor {
        case .closed:
            if let port = mainController.selectedPort {
                "Not connected to \(port.id)"
            } else {
                "Pick a port in the editor"
            }
        case .opening:
            "Connecting…"
        case .open(let baudRate):
            "Connected at \(baudRate) baud"
        case .failed(let message):
            message
        }
    }

    private var baudRatePicker: some View {
        Picker("Baud rate", selection: baudRate) {
            ForEach(baudRates, id: \.self) { rate in
                Text(rate).tag(rate)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
        .help("The speed the port is opened at")
    }

    /// The speeds to offer, with the one in use kept on the menu even when the port's monitor
    /// doesn't list it.
    private var baudRates: [String] {
        let rates = mainController.monitorBaudRates
        guard !rates.contains(mainController.monitorBaudRate) else { return rates }
        return [mainController.monitorBaudRate] + rates
    }

    private var baudRate: Binding<String> {
        Binding(
            get: { mainController.monitorBaudRate },
            set: { mainController.monitorBaudRate = $0 }
        )
    }

    private var connectButton: some View {
        Button {
            mainController.toggleSerialMonitor()
        } label: {
            Image(systemName: isConnected ? "stop.circle" : "play.circle")
        }
        .buttonStyle(.borderless)
        .help(isConnected ? "Disconnect from the port" : "Connect to the port")
        .disabled(mainController.selectedPort == nil)
    }

    private var output: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if mainController.monitorLines.isEmpty {
                        Text(placeholder)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(mainController.monitorLines) { line in
                            row(line)
                        }
                    }
                }
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: mainController.monitorLines.count) { _, _ in
                scrollToLastLine(proxy)
            }
            .onChange(of: mainController.monitorLines.last?.text) { _, _ in
                scrollToLastLine(proxy)
            }
        }
    }

    private var placeholder: String {
        isConnected ? "Nothing received yet." : "Connect to see what the board prints."
    }

    /// One printed line, with the empty ones kept so the board's spacing comes through.
    private func row(_ line: MonitorOutputLine) -> some View {
        Text(line.text.isEmpty ? " " : line.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(line.id)
    }

    /// Keeps the line that's still arriving in view, which is where the board is writing.
    private func scrollToLastLine(_ proxy: ScrollViewProxy) {
        guard let last = mainController.monitorLines.last else { return }
        proxy.scrollTo(last.id, anchor: .bottom)
    }

    private var sendBar: some View {
        HStack(spacing: 8) {
            TextField("Send a message to the board", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit(send)
                .disabled(!isConnected)
            lineEndingPicker
            Button("Send", action: send)
                .disabled(!isConnected || draft.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var lineEndingPicker: some View {
        Picker("Line ending", selection: lineEnding) {
            ForEach(MonitorLineEnding.allCases) { ending in
                Text(ending.title).tag(ending)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
        .help("What the monitor appends to what you send")
    }

    private var lineEnding: Binding<MonitorLineEnding> {
        Binding(
            get: { mainController.monitorLineEnding },
            set: { mainController.monitorLineEnding = $0 }
        )
    }

    private var isConnected: Bool {
        mainController.serialMonitor.isOpen
    }

    private func send() {
        guard !draft.isEmpty else { return }
        mainController.sendMonitorLine(draft)
        draft = ""
    }
}

#Preview {
    SerialMonitorView()
        .environment(MainController())
}
