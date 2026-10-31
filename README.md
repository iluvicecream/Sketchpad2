# Sketchpad

A native macOS IDE for Arduino development built with SwiftUI powered by `arduino-cli`

[![Download Latest Release](https://img.shields.io/badge/Download-Latest_Release_(.dmg/.zip)-blue?style=for-the-badge&logo=apple)](https://github.com/iluvicecream/Sketchpad2/releases/latest)

> **[Download Sketchpad for macOS (Apple Silicon) →](https://github.com/iluvicecream/Sketchpad2/releases/latest)**

![Sketchpad Screenshot](quicklook.png)

<details>
<summary>More Screenshots (Board Manager & Library Manager)</summary>

| Code Editor & Build Output | Board Manager | Library Manager |
| :---: | :---: | :---: |
| ![Editor](docs/screenshots/editor.png) | ![Board Manager](docs/screenshots/board-manager.png) | ![Library Manager](docs/screenshots/library-manager.png) |

</details>

---

## Platform Support

| Platform | Architecture | Status | Notes |
| :--- | :--- | :--- | :--- |
| **macOS** | Apple Silicon (`arm64`) | ✅ Supported | Pre-built `.dmg` / `.app` available in [Releases](https://github.com/iluvicecream/Sketchpad2/releases/latest) |
| **macOS** | Intel (`x86_64`) | ⚠️ Source Build | Requires updating the `arduino-cli` archive URL to `macOS_64bit` |
| **Windows** | `x86_64` / `arm64` | ❌ Not Supported | Uses native macOS `SwiftUI` and `AppKit` APIs |
| **Linux** | `x86_64` / `arm64` | ❌ Not Supported | Uses native macOS `SwiftUI` and `AppKit` APIs |

---

## Quick Start & Installation

### Install on macOS (Pre-built Binary)

1. Download the latest `.dmg` (or `.app.zip`) from [**GitHub Releases**](https://github.com/iluvicecream/Sketchpad2/releases/latest).
2. Drag **Sketchpad2.app** into your `/Applications` folder and launch it.
3. On first launch, Sketchpad automatically downloads and configures its own isolated `arduino-cli` daemon in the background—no manual CLI setup or config files required.

### Launching on macOS Without Gatekeeper Warnings

Because Sketchpad is distributed outside the Mac App Store without an Apple Developer ID notarization certificate, macOS Gatekeeper may show an **"unidentified developer"** or **"Sketchpad2 is damaged / Not Opened"** prompt on first launch.

To open the app, use either method below:

- **Option A (Terminal — fastest):** Run the following command to clear the macOS quarantine attribute, then open the app normally:
  ```bash
  xattr -cr /Applications/Sketchpad2.app
  ```
- **Option B (Finder & System Settings):**
  1. **Control-click** (or right-click) `Sketchpad2.app` in `/Applications` and select **Open**.
  2. If macOS still blocks the launch, open **System Settings → Privacy & Security**, scroll down to the **Security** section, and click **Open Anyway** next to `Sketchpad2.app`.

---

## Features

- **Zero-Config Onboarding:** Automatically downloads, extracts, and manages `arduino-cli` in `~/Library/Application Support/com.perr.Sketchpad2/daemon` on first launch and updates board and library indexes automatically.
- **Native C++ & Arduino Code Editor:** Built on AppKit's `NSTextView` (TextKit 2) with a custom line-number gutter (`GutterRulerView`), current-line highlighting, smart block auto-indentation, bracket/quote auto-pairing, and `⌘/` line comment toggling.
- **Arduino-Aware Syntax Highlighting:** Custom single-pass UTF-16 C++ tokenizer (`CppTokenizer`) that highlights C/C++ keywords, preprocessor directives, numbers, strings, and built-in Arduino functions (`setup`, `loop`, `pinMode`, `digitalWrite`, `Serial`, etc.) and constants (`HIGH`, `LOW`, `INPUT_PULLUP`, `LED_BUILTIN`).
- **Live Serial Port & Board Detection:** Polls connected USB serial ports every 2 seconds and automatically matches connected hardware against installed board definitions (FQBNs).
- **One-Click Verify (`⌘R`) & Upload (`⌘U`):** Compiles `.ino` sketches and flashes connected boards over gRPC with real-time streaming compiler and uploader output in a collapsible bottom console.
- **Integrated Board & Library Managers:** Browse, search, select versions, and install official Arduino cores (e.g., AVR, ESP32, RP2040) and third-party libraries directly inside the app without touching the terminal.
- **Native Document Workflow & Themes:** Full macOS `DocumentGroup` support for opening, editing, and saving `.ino` files, complete with System, Light, and Dark appearance modes (`⌘,`).

---

## Building & Running Locally

If you want to build Sketchpad from source instead of using the pre-built release:

### Prerequisites

- **macOS** on Apple Silicon (`arm64`)
- **Xcode 26+** with **Swift 6.0** toolchain
- An active internet connection on first run (so Xcode can resolve Swift Package Manager dependencies and Sketchpad can fetch `arduino-cli` on first launch)

### Build Steps

1. Clone the repository:
   ```bash
   git clone https://github.com/iluvicecream/Sketchpad2.git
   cd Sketchpad2
   ```
2. Open the project in Xcode:
   ```bash
   open Sketchpad2.xcodeproj
   ```
3. Wait for Xcode to finish resolving Swift Package Manager dependencies (`grpc-swift-2`, `grpc-swift-nio-transport`, `grpc-swift-protobuf`), select the **Sketchpad2** scheme (`My Mac`), and press **`⌘R`** to build and run.

*(Alternatively, build from the command line via `xcodebuild -project Sketchpad2.xcodeproj -scheme Sketchpad2 -configuration Release build`.)*

---

## How It Works

### Persistent gRPC Daemon vs. CLI Subprocesses

Most lightweight Arduino wrappers spawn a new `arduino-cli` shell process for every verify, upload, or port check. Because `arduino-cli` has to parse the entire hardware package and library index on startup, spawning processes per command introduces noticeable latency and makes streaming progress brittle.

Instead, Sketchpad's `ArduinoDaemonServiceBox` spawns `arduino-cli daemon` once as a managed background child process listening on `127.0.0.1:50051`. `ArduinoRPCServiceBox` connects over plaintext HTTP/2 using `grpc-swift-2` (`GRPCNIOTransportHTTP2`) and communicates via generated Protobuf types (`cc.arduino.cli.commands.v1.ArduinoCoreService`). Operations like index updates, core/library installation, compilation (`CompileRequest`), and flashing (`UploadRequest`) stream structured progress and `stdout`/`stderr` chunks directly back to the `@Observable` `BuildServiceBox` on the main actor.

### Custom AppKit TextKit 2 Editor Bridge

SwiftUI's built-in `TextEditor` lacks fine-grained control over key-event interception, horizontal scrolling, and gutter rendering required for code editing. Sketchpad bridges a custom `NSTextView` subclass (`EditorTextView`) into SwiftUI via `NSViewRepresentable` (`CodeEditorView`), paired with a custom `NSRulerView` (`GutterRulerView`) that draws aligned line numbers and tracks the active caret line. Syntax highlighting runs synchronously on text storage changes using `CppTokenizer`, a zero-regex, single-pass UTF-16 scanner that classifies C++ tokens and looks up Arduino symbols in `O(1)` sets (`ArduinoSymbols`), keeping typing latency flat even on larger sketches.

---

## Credits & Acknowledgements

- [**Arduino CLI**](https://github.com/arduino/arduino-cli) — Powers board/library management, sketch compilation, port discovery, flashing, and the gRPC `.proto` service definitions.
- [**gRPC Swift 2**](https://github.com/grpc/grpc-swift-2) & [**gRPC Swift NIO Transport**](https://github.com/grpc/grpc-swift-nio-transport) — High-performance native Swift concurrency gRPC client and HTTP/2 POSIX transport.
- [**SwiftProtobuf**](https://github.com/apple/swift-protobuf) — Protocol Buffers runtime for Swift used by the generated Arduino RPC bindings.
