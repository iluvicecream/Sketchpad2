import SwiftUI

struct SketchEditorView: View {
    @Environment(ArduinoController.self) private var controller
    
    @Binding var document: SketchDocument
    @Environment(\.documentConfiguration) private var docConfig
    var fileURL: URL? {
        docConfig?.fileURL
    }
    
    @State private var sketch: Cc_Arduino_Cli_Commands_V1_Sketch?
    @State private var errorMessage: String?
    
    var body: some View {
        Group {
            if let sketch, let fileURL {
                SketchEditorRealView(
                    document: $document,
                    sketch: sketch,
                    fileURL: fileURL
                )
                .toolbar {
                    Button {
                    } label: {
                        Text("compile")
                    }
                }
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
        .task(id: fileURL) {
            await loadSketchMetadata()
        }
    }

    private func loadSketchMetadata() async {
        guard let path = fileURL?.path else { return }
        do {
            self.sketch = try await controller.loadSketch(mainDir: path)
            self.errorMessage = nil
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}

struct SketchEditorRealView: View {
    @Binding var document: SketchDocument
    let sketch: Cc_Arduino_Cli_Commands_V1_Sketch
    let fileURL: URL

    var body: some View {
        MonacoEditorView(text: $document.mainCode, language: monacoLanguage)
    }

    private var monacoLanguage: String {
        switch fileURL.pathExtension.lowercased() {
        case "ino":
            return "arduino"
        case "c", "cc", "cpp", "h", "hh", "hpp":
            return "cpp"
        default:
            return "cpp"
        }
    }
}
