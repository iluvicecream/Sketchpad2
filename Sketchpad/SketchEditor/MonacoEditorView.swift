    //
    //  MonacoEditorView.swift
    //  Sketchpad
    //

    import SwiftUI
    import WebKit

    struct MonacoEditorView: View {
        @Binding var text: String
        var language: String = "cpp"
        
        var body: some View {
            MonacoWebView(text: $text, language: language)
        }
    }

    typealias PlatformViewRepresentable = NSViewRepresentable

    struct MonacoWebView: PlatformViewRepresentable {
        @Binding var text: String
        var language: String

        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }

        func makeNSView(context: Context) -> WKWebView { makeWebView(context: context) }
        func updateNSView(_ nsView: WKWebView, context: Context) { updateWebView(nsView, context: context) }

        private func makeWebView(context: Context) -> WKWebView {
            let config = WKWebViewConfiguration()
            let controller = WKUserContentController()
            
            controller.add(context.coordinator, name: "codeChanged")
            controller.add(context.coordinator, name: "editorReady")
            config.userContentController = controller

            let webView = WKWebView(frame: .zero, configuration: config)
            context.coordinator.webView = webView

            let html = """
            <!DOCTYPE html>
            <html>
            <head>
                <meta charset="utf-8">
                <style>
                    html, body, #container {
                        width: 100%; height: 100%; margin: 0; padding: 0; overflow: hidden;
                        background-color: transparent;
                    }
                </style>
                <script src="https://cdnjs.cloudflare.com/ajax/libs/monaco-editor/0.45.0/min/vs/loader.min.js"></script>
            </head>
            <body>
                <div id="container"></div>
                <script>
                    require.config({ paths: { 'vs': 'https://cdnjs.cloudflare.com/ajax/libs/monaco-editor/0.45.0/min/vs' }});
                    require(['vs/editor/editor.main'], function() {
                        window.editor = monaco.editor.create(document.getElementById('container'), {
                            value: '',
                            language: '\(language)',
                            theme: 'vs-light',
                            automaticLayout: true,
                            fontSize: 13,
                            minimap: { enabled: false }
                        });

                        window.editor.onDidChangeModelContent(function() {
                            window.webkit.messageHandlers.codeChanged.postMessage(window.editor.getValue());
                        });

                        // Notify Swift that Monaco is loaded and ready to accept text
                        window.webkit.messageHandlers.editorReady.postMessage({});
                    });

                    function setEditorText(val) {
                        if (window.editor && window.editor.getValue() !== val) {
                            window.editor.setValue(val);
                        }
                    }
                </script>
            </body>
            </html>
            """

            webView.loadHTMLString(html, baseURL: nil)
            return webView
        }

        private func updateWebView(_ webView: WKWebView, context: Context) {
            let coordinator = context.coordinator
            
            guard coordinator.lastValueFromJS != text else { return }
            
            if coordinator.isReady {
                coordinator.applyTextToJS(text)
            } else {
                coordinator.pendingText = text
            }
        }

        class Coordinator: NSObject, WKScriptMessageHandler {
            var parent: MonacoWebView
            weak var webView: WKWebView?
            var lastValueFromJS: String = ""
            var isReady: Bool = false
            var pendingText: String?

            init(_ parent: MonacoWebView) {
                self.parent = parent
            }

            func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
                if message.name == "editorReady" {
                    isReady = true
                    let initialText = pendingText ?? parent.text
                    applyTextToJS(initialText)
                    pendingText = nil
                } else if message.name == "codeChanged", let code = message.body as? String {
                    lastValueFromJS = code
                    parent.text = code
                }
            }

            func applyTextToJS(_ newText: String) {
                guard let webView = webView else { return }
                lastValueFromJS = newText
            
                if let data = try? JSONSerialization.data(withJSONObject: newText, options: [.fragmentsAllowed]),
                   let jsonString = String(data: data, encoding: .utf8) {
                    let js = "setEditorText(\(jsonString));"
                    webView.evaluateJavaScript(js, completionHandler: nil)
                }
            }
        }
    }
