    //
    //  MonacoEditorView.swift
    //  Sketchpad
    //

    import SwiftUI
    import WebKit

    struct MonacoEditorView: View {
        @Binding var text: String
        var language: String = "cpp"
        @Environment(\.colorScheme) private var colorScheme
        
        var body: some View {
            MonacoWebView(text: $text, language: language, colorScheme: colorScheme)
        }
    }

    typealias PlatformViewRepresentable = NSViewRepresentable

    struct MonacoWebView: PlatformViewRepresentable {
        @Binding var text: String
        var language: String
        var colorScheme: ColorScheme

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
            let isDarkInit = colorScheme == .dark

            let html = #"""
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
                        // Register the Arduino language (a superset of C++)
                        monaco.languages.register({ id: 'arduino' });

                        monaco.languages.setLanguageConfiguration('arduino', {
                            comments: { lineComment: '//', blockComment: ['/*', '*/'] },
                            brackets: [['{','}'],['[',']'],['(',')']],
                            autoClosingPairs: [
                                { open: '{', close: '}' },
                                { open: '[', close: ']' },
                                { open: '(', close: ')' },
                                { open: '"', close: '"' },
                                { open: "'", close: "'" }
                            ],
                            surroundingPairs: [
                                { open: '{', close: '}' },
                                { open: '[', close: ']' },
                                { open: '(', close: ')' },
                                { open: '"', close: '"' },
                                { open: "'", close: "'" }
                            ]
                        });

                        var arduinoKeywords = [
                            'asm','auto','break','case','catch','class','const','continue','default','delete','do',
                            'else','enum','explicit','extern','final','for','friend','goto','if','inline','long',
                            'mutable','namespace','new','noexcept','operator','private','protected','public','register',
                            'return','short','signed','sizeof','static','struct','switch','template','this','throw',
                            'try','typedef','typename','union','unsigned','using','virtual','volatile','while',
                            'setup','loop','yield','main'
                        ];
                        var arduinoTypeKeywords = [
                            'bool','boolean','byte','char','double','float','int','int8_t','int16_t','int32_t','int64_t',
                            'long','short','size_t','uint8_t','uint16_t','uint32_t','uint64_t','unsigned','void',
                            'word','String','Stream','HardwareSerial','Print','File'
                        ];
                        var arduinoConstants = [
                            'HIGH','LOW','INPUT','OUTPUT','INPUT_PULLUP','LED_BUILTIN','LED_BUILTIN_RX','LED_BUILTIN_TX',
                            'RISING','FALLING','CHANGE','DEFAULT','EXTERNAL','INTERNAL',
                            'A0','A1','A2','A3','A4','A5','A6','A7','A8','A9','A10','A11','A12','A13','A14','A15',
                            'true','false','NULL','nullptr','PI','HALF_PI','TWO_PI','DEG_TO_RAD','RAD_TO_DEG'
                        ];
                        var arduinoBuiltins = [
                            'abs','acos','analogRead','analogReference','analogWrite','asin','atan','atan2','attachInterrupt',
                            'byte','ceil','constrain','cos','detachInterrupt','digitalPinToInterrupt','digitalRead','digitalWrite',
                            'delay','delayMicroseconds','exp','floor','hypot','interrupts','isAlpha','isAlphaNumeric',
                            'isAscii','isControl','isDigit','isGraph','isHexadecimalDigit','isLowerCase','isPrintable',
                            'isPunct','isSpace','isUpperCase','isWhitespace','log','log10','long','lowByte','map','max',
                            'micros','millis','min','noInterrupts','noTone','pinMode','pow','pulseIn','pulseInLong',
                            'random','randomSeed','round','shiftIn','shiftOut','sin','sq','sqrt','tan','tone','word'
                        ];

                        monaco.languages.setMonarchTokensProvider('arduino', {
                            defaultToken: '',
                            tokenPostfix: '',
                            keywords: arduinoKeywords,
                            typeKeywords: arduinoTypeKeywords,
                            constants: arduinoConstants,
                            builtinFunctions: arduinoBuiltins,
                            symbols: /[=><!~?:&|+\-*/^%]+/,
                            escapes: /\\(?:[abfnrtv\\"']|x[0-9A-Fa-f]{1,4}|u[0-9A-Fa-f]{4}|U[0-9A-Fa-f]{8})/,
                            tokenizer: {
                                root: [
                                    [/^[ \t]*#.*$/, 'preprocessor'],
                                    [/\/\/.*$/, 'comment'],
                                    [/\/\*/, 'comment', '@comment'],
                                    [/\s+/, 'white'],
                                    [/0[xX][0-9a-fA-F]+/, 'number.hex'],
                                    [/0[bB][01]+/, 'number.binary'],
                                    [/[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?/, 'number'],
                                    [/"(?:[^"\\]|\\.)*"/, 'string'],
                                    [/'(?:[^'\\]|\\.)*'/, 'string'],
                                    [/[{}()[\]]/, '@brackets'],
                                    [/[;,.]/, 'delimiter'],
                                    [/[=><!~?:&|+\-*/^%]+/, 'operator'],
                                    [/[a-zA-Z_]\w*/, { cases: {
                                        '@keywords': 'keyword',
                                        '@typeKeywords': 'type',
                                        '@constants': 'constant',
                                        '@builtinFunctions': 'predefined',
                                        '@default': 'identifier'
                                    }}]
                                ],
                                comment: [
                                    [/[^/*]+/, 'comment'],
                                    [/\*\//, 'comment', '@pop'],
                                    [/[/*]/, 'comment']
                                ]
                            }
                        });

                        // Code completion for Arduino sketches
                        monaco.languages.registerCompletionItemProvider('arduino', {
                            provideCompletionItems: function(model, position) {
                                var word = model.getWordUntilPosition(position);
                                var range = new monaco.Range(position.lineNumber, word.startColumn, position.lineNumber, word.endColumn);
                                var suggestions = [];
                                var seen = {};

                                function add(label, kind, insertText, extra) {
                                    if (seen[label]) return;
                                    seen[label] = true;
                                    var item = {
                                        label: label,
                                        kind: kind,
                                        insertText: insertText || label,
                                        range: range
                                    };
                                    if (extra) for (var key in extra) item[key] = extra[key];
                                    suggestions.push(item);
                                }

                                arduinoConstants.forEach(function(k) { add(k, monaco.languages.CompletionItemKind.Constant, k); });
                                arduinoTypeKeywords.forEach(function(k) { add(k, monaco.languages.CompletionItemKind.TypeParameter, k); });
                                arduinoKeywords.forEach(function(k) { add(k, monaco.languages.CompletionItemKind.Keyword, k); });
                                arduinoBuiltins.forEach(function(f) {
                                    add(f, monaco.languages.CompletionItemKind.Function, f + '($0)', {
                                        insertTextRules: monaco.languages.CompletionItemInsertTextRule.InsertAsSnippet
                                    });
                                });

                                // Suggest user-defined functions declared in the sketch
                                var text = model.getValue().replace(/\/\/.*$/gm, '').replace(/\/\*[\s\S]*?\*\//g, '');
                                var controlKeywords = ['if','for','while','switch','catch','do','else','return','sizeof'];
                                var fnRe = /[^\w.]([A-Za-z_]\w*)\s*(\([^)]*\))\s*\{/g;
                                var m;
                                while ((m = fnRe.exec(text)) !== null) {
                                    var name = m[1];
                                    if (controlKeywords.indexOf(name) !== -1) continue;
                                    var params = m[2].slice(1, -1);
                                    var paramNames = params ? params.split(',').map(function(p) {
                                        var parts = p.trim().split(/\s+/);
                                        return parts[parts.length - 1];
                                    }).filter(function(p) { return /^[A-Za-z_]\w*$/.test(p); }) : [];
                                    var snippet;
                                    if (paramNames.length === 0) {
                                        snippet = name + '()';
                                    } else {
                                        snippet = name + '(' + paramNames.map(function(p, i) {
                                            return '${' + (i + 1) + ':' + p + '}';
                                        }).join(', ') + ')$0';
                                    }
                                    add(name, monaco.languages.CompletionItemKind.Function, snippet, {
                                        insertTextRules: monaco.languages.CompletionItemInsertTextRule.InsertAsSnippet
                                    });
                                }

                                return { suggestions: suggestions };
                            }
                        });

                        // Themes that follow the app's light/dark appearance
                        monaco.editor.defineTheme('arduino-light', {
                            base: 'vs',
                            inherit: true,
                            rules: [
                                { token: 'keyword', foreground: '0000FF' },
                                { token: 'type', foreground: '267F99' },
                                { token: 'constant', foreground: 'A626A4' },
                                { token: 'predefined', foreground: '008000' },
                                { token: 'preprocessor', foreground: '795E26' },
                                { token: 'operator', foreground: '000000' },
                                { token: 'string', foreground: 'A31515' },
                                { token: 'number', foreground: '098658' },
                                { token: 'comment', foreground: '008000', fontStyle: 'italic' },
                                { token: 'delimiter', foreground: '000000' }
                            ],
                            colors: {}
                        });

                        monaco.editor.defineTheme('arduino-dark', {
                            base: 'vs-dark',
                            inherit: true,
                            rules: [
                                { token: 'keyword', foreground: '569CD6' },
                                { token: 'type', foreground: '4EC9B0' },
                                { token: 'constant', foreground: 'C586C0' },
                                { token: 'predefined', foreground: '4FC1FF' },
                                { token: 'preprocessor', foreground: 'C586C0' },
                                { token: 'operator', foreground: 'D4D4D4' },
                                { token: 'string', foreground: 'CE9178' },
                                { token: 'number', foreground: 'B5CEA8' },
                                { token: 'comment', foreground: '6A9955', fontStyle: 'italic' },
                                { token: 'delimiter', foreground: 'D4D4D4' }
                            ],
                            colors: {}
                        });

                        var isDarkInitial = \#(isDarkInit ? "true" : "false");

                        function applyTheme(dark) {
                            monaco.editor.setTheme(dark ? 'arduino-dark' : 'arduino-light');
                        }
                        window.applyTheme = applyTheme;

                        
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
                            language: '\#(language)',
                            theme: isDarkInitial ? 'arduino-dark' : 'arduino-light',
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
            """#

            webView.loadHTMLString(html, baseURL: nil)
            return webView
        }

        private func updateWebView(_ webView: WKWebView, context: Context) {
            let coordinator = context.coordinator
            let isDark = colorScheme == .dark

            if coordinator.isReady, coordinator.lastAppliedDark != isDark {
                coordinator.applyThemeToJS(isDark: isDark)
                coordinator.lastAppliedDark = isDark
            }
            
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
            var lastAppliedDark: Bool? = nil

            init(_ parent: MonacoWebView) {
                self.parent = parent
            }

            func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
                if message.name == "editorReady" {
                    isReady = true
                    let isDark = parent.colorScheme == .dark
                    applyThemeToJS(isDark: isDark)
                    lastAppliedDark = isDark
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

            func applyThemeToJS(isDark: Bool) {
                guard let webView = webView else { return }
                let value = isDark ? "true" : "false"
                let js = "window.applyTheme(" + value + ");"
                webView.evaluateJavaScript(js, completionHandler: nil)
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
