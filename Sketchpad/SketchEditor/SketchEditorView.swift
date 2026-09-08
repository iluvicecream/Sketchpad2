import SwiftUI
import SwiftProtobuf

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
    
    var body: some View {
        VStack {
            Text("Editing: \(sketch.mainFile)")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            TextEditor(text: $editorText)
                .font(.system(.body, design: .monospaced))
                .padding()
        }
        .task(id: sketch.mainFile) {
            loadSketchContent()
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
}
