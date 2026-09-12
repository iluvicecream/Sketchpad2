//
//  MonacoEditorPage.swift
//  Sketchpad
//

import Foundation

/// Appearance options for the Monaco editor.
enum MonacoTheme: String {
    case light = "vs"
    case dark = "vs-dark"

    /// The page background color, used before Monaco has finished loading.
    var backgroundColorHex: String {
        switch self {
        case .light: "#fffffe"
        case .dark: "#1e1e1e"
        }
    }
}

/// Builds the HTML document that hosts a Monaco editor inside a `WKWebView`.
enum MonacoEditorPage {
    /// Pinned Monaco build loaded from jsDelivr.
    static let monacoVersion = "0.56.0"

    /// Base URL for a Monaco distribution. It also acts as the page's base URL
    /// so that the editor's web workers are same-origin with the document.
    static let baseURL = URL(string: "https://cdn.jsdelivr.net/npm/monaco-editor@\(monacoVersion)/min/")!

    static func html(text: String, language: String, fontSize: Int, theme: MonacoTheme) -> String {
        let vs = "\(baseURL.absoluteString)vs"
        let workerScript = "\(vs)/base/worker/workerMain.js"

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <style>
            html, body {
                margin: 0;
                padding: 0;
                height: 100%;
                overflow: hidden;
                background: \(theme.backgroundColorHex);
            }
            #editor {
                position: absolute;
                inset: 0;
            }
        </style>
        </head>
        <body>
        <div id="editor"></div>
        <script src="\(vs)/loader.js"></script>
        <script>
        (function () {
            "use strict";

            var handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(MonacoBridge.messageHandlerName);

            function post(message) {
                if (handler) { handler.postMessage(message); }
            }

            function fail(message) {
                post({ type: "error", message: String(message) });
            }

            window.onerror = function (message, source, line, column) {
                fail(message + " (" + source + ":" + line + ":" + column + ")");
            };

            var VS = "\(vs)";
            var ALLOWED_THEMES = ["vs", "vs-dark", "hc-black", "hc-light"];
            var LANGUAGE_ALIASES = { arduino: "cpp", ino: "cpp" };

            // Monaco runs its language services in web workers. The worker
            // script lives on a CDN, so it is bootstrapped through a blob that
            // is same-origin with this document.
            self.MonacoEnvironment = {
                getWorker: function (moduleId, label) {
                    var script = "importScripts(" + \(jsStringLiteral(workerScript)) + ");";
                    var blob = new Blob([script], { type: "text/javascript" });
                    return new Worker(URL.createObjectURL(blob), { name: label });
                }
            };

            function resolveLanguage(value) {
                var resolved = LANGUAGE_ALIASES[value] || value;
                var known = monaco.languages.getLanguages().map(function (item) { return item.id; });
                return known.indexOf(resolved) === -1 ? "plaintext" : resolved;
            }

            require.config({ paths: { vs: VS } });
            require.onError = function (error) {
                fail(error && error.message ? error.message : error);
            };

            require(["vs/editor/editor.main"], function () {
                var editor = monaco.editor.create(document.getElementById("editor"), {
                    value: \(jsStringLiteral(text)),
                    language: resolveLanguage(\(jsStringLiteral(language))),
                    theme: \(jsStringLiteral(theme.rawValue)),
                    fontSize: \(fontSize),
                    automaticLayout: true,
                    minimap: { enabled: false },
                    scrollBeyondLastLine: false,
                    tabSize: 2,
                    insertSpaces: true,
                    renderWhitespace: "selection",
                    scrollbar: { useShadows: false },
                    padding: { top: 8, bottom: 8 }
                });

                var suppressChange = false;
                var pendingChange = null;

                editor.onDidChangeModelContent(function () {
                    if (suppressChange) { return; }
                    if (pendingChange) { clearTimeout(pendingChange); }
                    pendingChange = setTimeout(function () {
                        pendingChange = null;
                        post({ type: "change", value: editor.getValue() });
                    }, 120);
                });

                window.monacoBridge = {
                    setValue: function (value) {
                        if (value === editor.getValue()) { return; }
                        suppressChange = true;
                        editor.setValue(value);
                        suppressChange = false;
                    },
                    setLanguage: function (value) {
                        var model = editor.getModel();
                        if (model) { monaco.editor.setModelLanguage(model, resolveLanguage(value)); }
                    },
                    setTheme: function (value) {
                        monaco.editor.setTheme(ALLOWED_THEMES.indexOf(value) === -1 ? "vs" : value);
                    },
                    setFontSize: function (value) {
                        editor.updateOptions({ fontSize: value });
                    },
                    focus: function () {
                        editor.focus();
                    }
                };

                post({ type: "ready" });
            });
        })();
        </script>
        </body>
        </html>
        """
    }

    /// Encodes a Swift string as a JavaScript string literal that is also safe
    /// to embed inside a `<script>` element.
    static func jsStringLiteral(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              var literal = String(data: data, encoding: .utf8),
              literal.count >= 2
        else {
            return "\"\""
        }

        literal.removeFirst()
        literal.removeLast()

        return literal
            .replacingOccurrences(of: "<", with: "\\u003C")
            .replacingOccurrences(of: ">", with: "\\u003E")
            .replacingOccurrences(of: "&", with: "\\u0026")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }
}
