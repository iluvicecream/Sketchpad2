import SwiftUI
import CodeEditorView
import LanguageSupport

struct SketchEditorView: View {
    @Environment(ArduinoController.self) private var controller
    var mainDir: String
    
    @State private var sketch: Cc_Arduino_Cli_Commands_V1_Sketch?
    
    var body: some View {
        Group {
            if let sketch {
                SketchEditorRealView(sketch: sketch)
            } else {
                ProgressView("Loading sketch...")
            }
        }
        .task(id: mainDir) {
            sketch = try? await controller.loadSketch(mainDir: mainDir)
        }
    }
}

struct SketchEditorRealView: View {
    @Environment(ArduinoController.self) private var controller
    let sketch: Cc_Arduino_Cli_Commands_V1_Sketch
    
    @State private var editorText: String = ""
    @State private var position: CodeEditor.Position       = CodeEditor.Position()
    @State private var messages: Set<TextLocated<Message>> = Set()
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    
    var body: some View {
        VStack {
            CodeEditor(
                text: $editorText,
                position: $position,
                messages: $messages,
                language: .swift()
            )
            .environment(\.codeEditorTheme,
                         colorScheme == .dark ? Theme.defaultDark : Theme.defaultLight)
        }
        .task(id: sketch.mainFile) {
            loadSketchContent()
        }
        .background {
            Button("Save") {
                saveSketchContent()
            }
            .keyboardShortcut("s", modifiers: .command)
            .hidden()
        }
    }
    
    private func loadSketchContent() {
        let fileURL = URL(fileURLWithPath: sketch.mainFile)
        do {
            editorText = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            print("Failed to load file at \(sketch.mainFile): \(error)")
        }
    }
    
    private func saveSketchContent() {
        let fileURL = URL(fileURLWithPath: sketch.mainFile)
        do {
            try editorText.write(to: fileURL, atomically: true, encoding: .utf8)
            print("Saved successfully to \(sketch.mainFile)")
        } catch {
            print("Failed to save file at \(sketch.mainFile): \(error)")
        }
    }
}
