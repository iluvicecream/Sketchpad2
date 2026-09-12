//
//  MonacoEditorView.swift
//  Sketchpad
//

import AppKit
import os
import SwiftUI
import WebKit

/// Shared names used by the Swift <-> JavaScript bridge.
enum MonacoBridge {
    static let messageHandlerName = "monacoBridge"
}

/// A SwiftUI wrapper around a Monaco editor hosted in a `WKWebView`.
///
/// The text binding is two-way: edits made in the web view are posted back to
/// Swift, and external changes to the binding are pushed into the editor.
struct MonacoEditorView: View {
    @Binding var text: String
    var language: String = "cpp"
    var fontSize: Int = 13

    @Environment(\.colorScheme) private var colorScheme
    @State private var failure: String?
    @State private var reloadToken = UUID()

    var body: some View {
        ZStack {
            MonacoWebView(
                text: $text,
                language: language,
                fontSize: fontSize,
                theme: colorScheme == .dark ? .dark : .light,
                onReady: { failure = nil },
                onFailure: { failure = $0 }
            )
            .id(reloadToken)

            if let failure {
                ContentUnavailableView {
                    Label("Editor Unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(failure)
                } actions: {
                    Button("Try Again") { reloadToken = UUID() }
                }
                .background(.background)
            }
        }
    }
}

private struct MonacoWebView: NSViewRepresentable {
    @Binding var text: String
    let language: String
    let fontSize: Int
    let theme: MonacoTheme
    let onReady: () -> Void
    let onFailure: (String) -> Void

    func makeCoordinator() -> MonacoWebViewCoordinator {
        MonacoWebViewCoordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(
            context.coordinator,
            name: MonacoBridge.messageHandlerName
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsMagnification = false
        webView.underPageBackgroundColor = theme.backgroundColor
        #if DEBUG
        webView.isInspectable = true
        #endif

        context.coordinator.load(in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        webView.underPageBackgroundColor = theme.backgroundColor
        context.coordinator.pushState()
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: MonacoWebViewCoordinator) {
        webView.configuration.userContentController
            .removeScriptMessageHandler(forName: MonacoBridge.messageHandlerName)
        webView.navigationDelegate = nil
    }
}

@MainActor
private final class MonacoWebViewCoordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private static let logger = Logger(subsystem: "com.perr.Sketchpad", category: "MonacoEditor")

    var parent: MonacoWebView

    private weak var webView: WKWebView?
    private var isReady = false

    // Last values successfully handed to the editor, used to avoid redundant work.
    private var appliedText: String
    private var appliedLanguage: String
    private var appliedTheme: MonacoTheme
    private var appliedFontSize: Int

    init(_ parent: MonacoWebView) {
        self.parent = parent
        self.appliedText = parent.text
        self.appliedLanguage = parent.language
        self.appliedTheme = parent.theme
        self.appliedFontSize = parent.fontSize
        super.init()
    }

    func load(in webView: WKWebView) {
        self.webView = webView
        isReady = false
        let page = MonacoEditorPage.html(
            text: parent.text,
            language: parent.language,
            fontSize: parent.fontSize,
            theme: parent.theme
        )
        webView.loadHTMLString(page, baseURL: MonacoEditorPage.baseURL)
    }

    /// Pushes any state that changed since it was last sent to the editor.
    func pushState() {
        guard isReady else { return }

        if appliedText != parent.text {
            appliedText = parent.text
            evaluate("window.monacoBridge.setValue(\(MonacoEditorPage.jsStringLiteral(parent.text)))")
        }
        if appliedLanguage != parent.language {
            appliedLanguage = parent.language
            evaluate("window.monacoBridge.setLanguage(\(MonacoEditorPage.jsStringLiteral(parent.language)))")
        }
        if appliedTheme != parent.theme {
            appliedTheme = parent.theme
            evaluate("window.monacoBridge.setTheme(\(MonacoEditorPage.jsStringLiteral(parent.theme.rawValue)))")
        }
        if appliedFontSize != parent.fontSize {
            appliedFontSize = parent.fontSize
            evaluate("window.monacoBridge.setFontSize(\(parent.fontSize))")
        }
    }

    private func evaluate(_ script: String) {
        webView?.evaluateJavaScript(script) { _, error in
            guard let error else { return }
            Self.logger.error("Monaco bridge script failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func report(_ message: String) {
        Self.logger.error("Monaco editor failed: \(message, privacy: .public)")
        parent.onFailure(message)
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == MonacoBridge.messageHandlerName,
              let body = message.body as? [String: Any],
              let type = body["type"] as? String
        else { return }

        switch type {
        case "ready":
            isReady = true
            pushState()
            parent.onReady()
        case "change":
            guard let value = body["value"] as? String else { return }
            appliedText = value
            if parent.text != value {
                parent.text = value
            }
        case "error":
            report(body["message"] as? String ?? "Unknown JavaScript error.")
        default:
            break
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        // Keep the web view pinned to the editor page; don't follow links.
        decisionHandler(navigationAction.navigationType == .linkActivated ? .cancel : .allow)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        load(in: webView)
    }
}

private extension MonacoTheme {
    var backgroundColor: NSColor {
        switch self {
        case .light: NSColor(srgbRed: 1, green: 1, blue: 0.996, alpha: 1)
        case .dark: NSColor(srgbRed: 0.118, green: 0.118, blue: 0.118, alpha: 1)
        }
    }
}
