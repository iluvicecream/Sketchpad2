import SwiftUI

struct SketchEditorView: View {
    @Environment(ArduinoController.self) private var controller
    var mainDir: String
    
    @State private var loadedData: (sketch: Cc_Arduino_Cli_Commands_V1_Sketch, content: String)?
    @State private var errorMessage: String?
    
    var body: some View {
        Group {
            if let loadedData {
                SketchEditorRealView(
                    sketch: loadedData.sketch,
                    initialContent: loadedData.content
                )
                .id(loadedData.sketch.mainFile)
            } else if let errorMessage {
                ContentUnavailableView(
                    "Failed to Load Sketch",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                ProgressView("Loading sketch...")
            }
        }
        .task(id: mainDir) {
            await loadSketchAndContent()
        }
    }
    
    private func loadSketchAndContent() async {
        loadedData = nil
        errorMessage = nil
        
        do {
            let sketch = try await controller.loadSketch(mainDir: mainDir)
            let fileURL = URL(fileURLWithPath: sketch.mainFile)
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            
            self.loadedData = (sketch, content)
        } catch {
            self.errorMessage = error.localizedDescription
            print("Error loading sketch: \(error)")
        }
    }
}

struct SketchEditorRealView: View {
    @Environment(ArduinoController.self) private var controller
    let sketch: Cc_Arduino_Cli_Commands_V1_Sketch
    
    @State private var editorText: String
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    
    init(sketch: Cc_Arduino_Cli_Commands_V1_Sketch, initialContent: String) {
        self.sketch = sketch
        self._editorText = State(initialValue: initialContent)
    }
    
    var body: some View {
        VStack {
            MonacoEditorView(text: $editorText, language: "cpp")
        }
        .background {
            Button("Save") {
                saveSketchContent()
            }
            .keyboardShortcut("s", modifiers: .command)
            .hidden()
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
