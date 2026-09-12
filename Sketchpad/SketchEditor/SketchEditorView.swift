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
            if (sketch != nil), (fileURL != nil) {
                VStack {
                    // Direct binding to document.fileContent
                    CoreEditorView(text: $document.fileContent)
                }
                .toolbar {
                    Button {
                        // Compile logic
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
