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
            controller.add(context.coordinator, name: "showContextMenu")
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
                    var lastMouseX = 0;
                    var lastMouseY = 0;

                    window.addEventListener('contextmenu', function(e) {
                        lastMouseX = e.clientX;
                        lastMouseY = e.clientY;
                    }, true);

                    require.config({ paths: { 'vs': 'https://cdnjs.cloudflare.com/ajax/libs/monaco-editor/0.45.0/min/vs' }});
                    require(['vs/editor/editor.main'], function() {
                        
                        // Override Monaco's internal context menu service to intercept menu requests
                        var nativeContextMenuService = {
                            showContextMenu: function(delegate) {
                                var actions = delegate.getActions();
                                window.currentContextMenuActions = {};
                                
                                function serializeAction(action, key) {
                                    if (!action) return { type: 'separator' };
                                    
                                    if (action.id === 'vs.actions.separator' || action.id === '-' || (!action.label && !action.actions)) {
                                        return { type: 'separator' };
                                    }
                                    
                                    window.currentContextMenuActions[key] = action;
                                    
                                    var item = {
                                        key: key,
                                        id: action.id || '',
                                        label: action.label || '',
                                        enabled: action.enabled !== false,
                                        checked: action.checked || false
                                    };
                                    
                                    if (action.actions && Array.isArray(action.actions)) {
                                        item.submenu = action.actions.map(function(sub, idx) {
                                            return serializeAction(sub, key + '_' + idx);
                                        });
                                    }
                                    
                                    return item;
                                }

                                var menuItems = [];
                                for (var i = 0; i < actions.length; i++) {
                                    menuItems.push(serializeAction(actions[i], 'act_' + i));
                                }

                                var x = lastMouseX;
                                var y = lastMouseY;

                                if (delegate.getAnchor) {
                                    var anchor = delegate.getAnchor();
                                    if (anchor) {
                                        if (typeof anchor.x === 'number' && typeof anchor.y === 'number') {
                                            x = anchor.x;
                                            y = anchor.y;
                                        } else if (anchor.getBoundingClientRect) {
                                            var rect = anchor.getBoundingClientRect();
                                            x = rect.left;
                                            y = rect.top;
                                        }
                                    }
                                }

                                window.currentContextMenuOnHide = delegate.onHide;

                                window.webkit.messageHandlers.showContextMenu.postMessage({
                                    x: x,
                                    y: y,
                                    items: menuItems
                                });
                            }
                        };

                        window.editor = monaco.editor.create(document.getElementById('container'), {
                            value: '',
                            language: '\(language)',
                            theme: 'vs-light',
                            automaticLayout: true,
                            fontSize: 13,
                            minimap: { enabled: false }
                        }, {
                            contextMenuService: nativeContextMenuService
                        });

                        window.editor.onDidChangeModelContent(function() {
                            window.webkit.messageHandlers.codeChanged.postMessage(window.editor.getValue());
                        });

                        window.webkit.messageHandlers.editorReady.postMessage({});
                    });

                    function setEditorText(val) {
                        if (window.editor && window.editor.getValue() !== val) {
                            window.editor.setValue(val);
                        }
                    }

                    function executeContextMenuAction(key) {
                        if (window.currentContextMenuActions && window.currentContextMenuActions[key]) {
                            var action = window.currentContextMenuActions[key];
                            if (typeof action.run === 'function') {
                                action.run();
                            }
                        }
                        dismissContextMenu();
                    }

                    function dismissContextMenu() {
                        if (typeof window.currentContextMenuOnHide === 'function') {
                            window.currentContextMenuOnHide();
                            window.currentContextMenuOnHide = null;
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

        class Coordinator: NSObject, WKScriptMessageHandler, NSMenuDelegate {
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
                } else if message.name == "showContextMenu", let dict = message.body as? [String: Any] {
                    presentNativeContextMenu(dict: dict)
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

            private func presentNativeContextMenu(dict: [String: Any]) {
                guard let webView = webView,
                      let items = dict["items"] as? [[String: Any]] else { return }

                let menu = NSMenu()
                menu.delegate = self
                
                populateMenu(menu, with: items)

                let x = dict["x"] as? CGFloat ?? 0
                let y = dict["y"] as? CGFloat ?? 0
                let point = NSPoint(x: x, y: y)
                
                menu.popUp(positioning: nil, at: point, in: webView)
            }

            private func populateMenu(_ menu: NSMenu, with items: [[String: Any]]) {
                for itemDict in items {
                    if let type = itemDict["type"] as? String, type == "separator" {
                        menu.addItem(NSMenuItem.separator())
                        continue
                    }

                    guard let label = itemDict["label"] as? String, !label.isEmpty else {
                        continue
                    }

                    let key = itemDict["key"] as? String ?? ""
                    let enabled = itemDict["enabled"] as? Bool ?? true
                    let checked = itemDict["checked"] as? Bool ?? false

                    let menuItem = NSMenuItem(title: label, action: #selector(menuItemClicked(_:)), keyEquivalent: "")
                    menuItem.target = self
                    menuItem.representedObject = key
                    menuItem.isEnabled = enabled
                    if checked {
                        menuItem.state = .on
                    }

                    if let submenuItems = itemDict["submenu"] as? [[String: Any]], !submenuItems.isEmpty {
                        let submenu = NSMenu(title: label)
                        populateMenu(submenu, with: submenuItems)
                        menuItem.submenu = submenu
                    }

                    menu.addItem(menuItem)
                }
            }

            @objc private func menuItemClicked(_ sender: NSMenuItem) {
                guard let key = sender.representedObject as? String, let webView = webView else { return }
                let js = "executeContextMenuAction('\(key)');"
                webView.evaluateJavaScript(js, completionHandler: nil)
            }

            func menuDidClose(_ menu: NSMenu) {
                webView?.evaluateJavaScript("dismissContextMenu();", completionHandler: nil)
            }
        }
    }
