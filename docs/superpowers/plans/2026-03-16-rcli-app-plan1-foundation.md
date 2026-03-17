# RCLI macOS App — Plan 1: Foundation

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish the build pipeline and project scaffold so a SwiftUI app can link the C++ engine, show a menu bar icon, and initialize the engine successfully.

**Architecture:** CMake builds the C++ engine as a static library. A shell script merges all static libs into an xcframework. An Xcode project links the xcframework and displays a bare MenuBarExtra. New C API functions and C bridge wrappers are added to support the Swift app.

**Tech Stack:** C++17, CMake, Swift/SwiftUI (macOS 14+), Xcode, xcframework, Obj-C++ bridge

**Spec:** `docs/superpowers/specs/2026-03-16-rcli-macos-app-design.md`

---

## Chunk 1: New C API Functions

### Task 1: Add `rcli_deregister_all_callbacks`

**Files:**
- Modify: `src/api/rcli_api.h`
- Modify: `src/api/rcli_api.cpp`

- [ ] **Step 1: Add declaration to header**

In `src/api/rcli_api.h`, before the closing `#ifdef __cplusplus` / `}`, add:

```c
// Deregister all callbacks under engine mutex, wait for any in-flight
// callback to complete. Must be called before rcli_destroy().
void rcli_deregister_all_callbacks(RCLIHandle handle);
```

- [ ] **Step 2: Add implementation**

In `src/api/rcli_api.cpp`, add before the closing `}` of `extern "C"`:

```cpp
void rcli_deregister_all_callbacks(RCLIHandle handle) {
    if (!handle) return;
    auto* engine = static_cast<RCLIEngine*>(handle);
    std::lock_guard<std::mutex> lock(engine->mutex);
    engine->transcript_cb = nullptr;
    engine->transcript_ud = nullptr;
    engine->state_cb = nullptr;
    engine->state_ud = nullptr;
    engine->action_cb = nullptr;
    engine->action_ud = nullptr;
    engine->tool_trace_cb = nullptr;
    engine->tool_trace_ud = nullptr;
    engine->pipeline.set_transcript_callback(nullptr);
    engine->pipeline.set_response_callback(nullptr);
    engine->pipeline.set_state_callback(nullptr);
}
```

- [ ] **Step 3: Build and verify**

Run: `cd /Users/rchoi/Personal/rcli-dictate/build && cmake --build . -j$(sysctl -n hw.ncpu) 2>&1 | tail -5`

Expected: Build succeeds with no errors.

- [ ] **Step 4: Commit**

```bash
git add src/api/rcli_api.h src/api/rcli_api.cpp
git commit -m "feat(api): add rcli_deregister_all_callbacks for safe Swift cleanup"
```

### Task 2: Add `rcli_list_available_models`

**Files:**
- Modify: `src/api/rcli_api.h`
- Modify: `src/api/rcli_api.cpp`

- [ ] **Step 1: Add declaration to header**

In `src/api/rcli_api.h`, add near the Model Hot-Swap section:

```c
// List available models in the registry as JSON array.
// Each entry: {id, name, size_bytes, type ("llm"|"tts"|"stt"), is_downloaded}
// Caller must free() the returned string. Returns NULL on failure.
char* rcli_list_available_models(RCLIHandle handle);
```

- [ ] **Step 2: Add implementation**

This needs to read from the existing model registries. In `src/api/rcli_api.cpp`:

```cpp
char* rcli_list_available_models(RCLIHandle handle) {
    if (!handle) return nullptr;
    auto* engine = static_cast<RCLIEngine*>(handle);

    std::string json = "[";
    bool first = true;

    // LLM models
    for (const auto& m : rastack::ModelRegistry::all_models()) {
        if (!first) json += ",";
        first = false;
        // Check if model file exists
        std::string path = engine->models_dir + "/" + m.filename;
        bool downloaded = (access(path.c_str(), F_OK) == 0);
        json += "{\"id\":\"" + m.id + "\","
                "\"name\":\"" + m.name + "\","
                "\"size_bytes\":" + std::to_string(m.size_bytes) + ","
                "\"type\":\"llm\","
                "\"is_downloaded\":" + (downloaded ? "true" : "false") + "}";
    }

    // TTS models
    for (const auto& m : rastack::TtsModelRegistry::all_models()) {
        if (!first) json += ",";
        first = false;
        std::string path = engine->models_dir + "/" + m.filename;
        bool downloaded = (access(path.c_str(), F_OK) == 0);
        json += "{\"id\":\"" + m.id + "\","
                "\"name\":\"" + m.name + "\","
                "\"size_bytes\":" + std::to_string(m.size_bytes) + ","
                "\"type\":\"tts\","
                "\"is_downloaded\":" + (downloaded ? "true" : "false") + "}";
    }

    // STT models
    for (const auto& m : rastack::SttModelRegistry::all_models()) {
        if (!first) json += ",";
        first = false;
        std::string path = engine->models_dir + "/" + m.filename;
        bool downloaded = (access(path.c_str(), F_OK) == 0);
        json += "{\"id\":\"" + m.id + "\","
                "\"name\":\"" + m.name + "\","
                "\"size_bytes\":" + std::to_string(m.size_bytes) + ","
                "\"type\":\"stt\","
                "\"is_downloaded\":" + (downloaded ? "true" : "false") + "}";
    }

    json += "]";
    return strdup(json.c_str());
}
```

Note: Check the actual model registry API — the field names (`id`, `name`, `filename`, `size_bytes`) may differ. Read `src/models/model_registry.h`, `src/models/tts_model_registry.h`, and `src/models/stt_model_registry.h` to verify the struct fields and adjust accordingly.

- [ ] **Step 3: Build and verify**

Run: `cd /Users/rchoi/Personal/rcli-dictate/build && cmake --build . -j$(sysctl -n hw.ncpu) 2>&1 | tail -5`

Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add src/api/rcli_api.h src/api/rcli_api.cpp
git commit -m "feat(api): add rcli_list_available_models for model registry queries"
```

### Task 3: Add `rcli_switch_tts` and `rcli_switch_stt`

**Files:**
- Modify: `src/api/rcli_api.h`
- Modify: `src/api/rcli_api.cpp`

- [ ] **Step 1: Add declarations to header**

In `src/api/rcli_api.h`, add near `rcli_switch_llm`:

```c
// Switch TTS voice at runtime. Returns 0 on success, -1 on failure.
int rcli_switch_tts(RCLIHandle handle, const char* model_id);

// Switch STT model at runtime. Returns 0 on success, -1 on failure.
int rcli_switch_stt(RCLIHandle handle, const char* model_id);
```

- [ ] **Step 2: Add implementations**

In `src/api/rcli_api.cpp`. These need to look up the model in the registry and reconfigure the engine. Read `src/models/tts_model_registry.h` and `src/models/stt_model_registry.h` for the registry lookup pattern. The implementation should follow the same pattern as `rcli_switch_llm`:

```cpp
int rcli_switch_tts(RCLIHandle handle, const char* model_id) {
    if (!handle || !model_id) return -1;
    auto* engine = static_cast<RCLIEngine*>(handle);

    auto model = rastack::TtsModelRegistry::find(model_id);
    if (!model) return -1;

    std::string model_path = engine->models_dir + "/" + model->filename;
    if (access(model_path.c_str(), F_OK) != 0) return -1;

    // Reconfigure TTS engine with new model
    engine->pipeline.set_tts_voice(model_path);
    engine->tts_model_name = model->name;
    return 0;
}

int rcli_switch_stt(RCLIHandle handle, const char* model_id) {
    if (!handle || !model_id) return -1;
    auto* engine = static_cast<RCLIEngine*>(handle);

    auto model = rastack::SttModelRegistry::find(model_id);
    if (!model) return -1;

    std::string model_path = engine->models_dir + "/" + model->filename;
    if (access(model_path.c_str(), F_OK) != 0) return -1;

    // STT engine reconfiguration depends on whether it's streaming or offline
    // Read src/engines/stt_engine.h for available reconfiguration methods
    engine->stt_model_name = model->name;
    return 0;
}
```

Note: The actual implementation depends on the TTS/STT engine APIs. Read `src/engines/tts_engine.h` and `src/engines/stt_engine.h` to find the correct reconfiguration methods. The `set_tts_voice` method on the orchestrator already exists per `orchestrator.h:111`.

- [ ] **Step 3: Build and verify**

Run: `cd /Users/rchoi/Personal/rcli-dictate/build && cmake --build . -j$(sysctl -n hw.ncpu) 2>&1 | tail -5`

Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add src/api/rcli_api.h src/api/rcli_api.cpp
git commit -m "feat(api): add rcli_switch_tts and rcli_switch_stt for runtime model swap"
```

## Chunk 2: C Bridge Wrappers

### Task 4: Create overlay bridge

**Files:**
- Create: `src/bridge/rcli_overlay_bridge.h`
- Create: `src/bridge/rcli_overlay_bridge.mm`
- Modify: `CMakeLists.txt` (add bridge sources to rcli target)

- [ ] **Step 1: Create the C header**

Create `src/bridge/rcli_overlay_bridge.h`:

```c
#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// Overlay states matching rcli::OverlayState enum
#define RCLI_OVERLAY_RECORDING    0
#define RCLI_OVERLAY_TRANSCRIBING 1

void rcli_overlay_init(void);
void rcli_overlay_show(int state, double x, double y, int has_position);
void rcli_overlay_set_state(int state);
void rcli_overlay_dismiss(void);
void rcli_overlay_cleanup(void);

#ifdef __cplusplus
}
#endif
```

- [ ] **Step 2: Create the Obj-C++ implementation**

Create `src/bridge/rcli_overlay_bridge.mm`:

```objc
#include "bridge/rcli_overlay_bridge.h"
#include "dictate/overlay.h"
#include <optional>

extern "C" {

void rcli_overlay_init(void) {
    rcli::overlay_init();
}

void rcli_overlay_show(int state, double x, double y, int has_position) {
    auto overlay_state = static_cast<rcli::OverlayState>(state);
    std::optional<rcli::ScreenPoint> pos;
    if (has_position) {
        pos = rcli::ScreenPoint{x, y};
    }
    rcli::overlay_show(overlay_state, pos);
}

void rcli_overlay_set_state(int state) {
    rcli::overlay_set_state(static_cast<rcli::OverlayState>(state));
}

void rcli_overlay_dismiss(void) {
    rcli::overlay_dismiss();
}

void rcli_overlay_cleanup(void) {
    rcli::overlay_cleanup();
}

} // extern "C"
```

- [ ] **Step 3: Commit bridge files**

```bash
git add src/bridge/rcli_overlay_bridge.h src/bridge/rcli_overlay_bridge.mm
git commit -m "feat(bridge): add pure C wrapper for overlay"
```

### Task 5: Create paste bridge

**Files:**
- Create: `src/bridge/rcli_paste_bridge.h`
- Create: `src/bridge/rcli_paste_bridge.mm`

- [ ] **Step 1: Create the C header**

Create `src/bridge/rcli_paste_bridge.h`:

```c
#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// Copy text to clipboard and simulate Cmd+V paste.
// Returns 0 on success, -1 on failure.
int rcli_paste_text(const char* text);

// Send a macOS notification.
void rcli_send_notification(const char* title, const char* body);

#ifdef __cplusplus
}
#endif
```

- [ ] **Step 2: Create the Obj-C++ implementation**

Create `src/bridge/rcli_paste_bridge.mm`:

```objc
#include "bridge/rcli_paste_bridge.h"
#include "dictate/paste_engine.h"
#include <string>

extern "C" {

int rcli_paste_text(const char* text) {
    if (!text) return -1;
    std::string str(text);
    if (!rcli::clipboard_copy(str)) return -1;
    rcli::simulate_paste();
    return 0;
}

void rcli_send_notification(const char* title, const char* body) {
    if (!title || !body) return;
    rcli::send_notification(std::string(title), std::string(body));
}

} // extern "C"
```

- [ ] **Step 3: Commit**

```bash
git add src/bridge/rcli_paste_bridge.h src/bridge/rcli_paste_bridge.mm
git commit -m "feat(bridge): add pure C wrapper for paste engine"
```

### Task 6: Create caret bridge

**Files:**
- Create: `src/bridge/rcli_caret_bridge.h`
- Create: `src/bridge/rcli_caret_bridge.mm`

- [ ] **Step 1: Create the C header**

Create `src/bridge/rcli_caret_bridge.h`:

```c
#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// Get the screen position of the text caret in the focused app.
// Writes to out_x and out_y. Returns 0 on success, -1 if unavailable.
int rcli_get_caret_position(double* out_x, double* out_y);

#ifdef __cplusplus
}
#endif
```

- [ ] **Step 2: Create the Obj-C++ implementation**

Create `src/bridge/rcli_caret_bridge.mm`:

```objc
#include "bridge/rcli_caret_bridge.h"
#include "dictate/caret_position.h"

extern "C" {

int rcli_get_caret_position(double* out_x, double* out_y) {
    if (!out_x || !out_y) return -1;
    auto pos = rcli::get_caret_screen_position();
    if (!pos) return -1;
    *out_x = pos->x;
    *out_y = pos->y;
    return 0;
}

} // extern "C"
```

- [ ] **Step 3: Commit**

```bash
git add src/bridge/rcli_caret_bridge.h src/bridge/rcli_caret_bridge.mm
git commit -m "feat(bridge): add pure C wrapper for caret position"
```

### Task 7: Add bridge sources to CMake and verify build

**Files:**
- Modify: `CMakeLists.txt`

- [ ] **Step 1: Add bridge sources to the rcli library target**

In `CMakeLists.txt`, find the `add_library(rcli STATIC ...)` block and add the three bridge files to the source list:

```
src/bridge/rcli_overlay_bridge.mm
src/bridge/rcli_paste_bridge.mm
src/bridge/rcli_caret_bridge.mm
```

Also add `set_source_files_properties` for each `.mm` file (same pattern as existing `.mm` files):

```cmake
set_source_files_properties(src/bridge/rcli_overlay_bridge.mm PROPERTIES LANGUAGE CXX)
set_source_files_properties(src/bridge/rcli_paste_bridge.mm PROPERTIES LANGUAGE CXX)
set_source_files_properties(src/bridge/rcli_caret_bridge.mm PROPERTIES LANGUAGE CXX)
```

- [ ] **Step 2: Build and verify**

Run: `cd /Users/rchoi/Personal/rcli-dictate/build && cmake .. -DCMAKE_BUILD_TYPE=Release && cmake --build . -j$(sysctl -n hw.ncpu) 2>&1 | tail -10`

Expected: Build succeeds. Bridge files compile without errors.

- [ ] **Step 3: Commit**

```bash
git add CMakeLists.txt
git commit -m "build: add C bridge wrappers to CMake build"
```

## Chunk 3: xcframework Build Script

### Task 8: Create `scripts/build_xcframework.sh`

**Files:**
- Create: `scripts/build_xcframework.sh`

This script builds the C++ engine via CMake, merges all static libraries, and packages them as an xcframework that Xcode can consume.

- [ ] **Step 1: Create the script**

Create `scripts/build_xcframework.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Build RCLI engine as xcframework for the macOS app.
# Usage: bash scripts/build_xcframework.sh [--debug]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$ROOT_DIR/build-xcframework"
OUTPUT_DIR="$ROOT_DIR/app"
BUILD_TYPE="Release"

if [[ "${1:-}" == "--debug" ]]; then
    BUILD_TYPE="Debug"
fi

echo "=== Building RCLI engine ($BUILD_TYPE) ==="

# Step 1: CMake configure + build
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
cmake "$ROOT_DIR" \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DCMAKE_OSX_ARCHITECTURES=arm64

cmake --build . -j"$(sysctl -n hw.ncpu)" --target rcli

echo "=== Merging static libraries ==="

# Step 2: Find all static libs that rcli depends on
# The rcli target links: llama, ggml, sherpa-onnx-c-api, and various ggml-* backends
LIBS=(
    "$BUILD_DIR/librcli.a"
)

# Find all llama/ggml static libs
while IFS= read -r lib; do
    LIBS+=("$lib")
done < <(find "$BUILD_DIR/llama.cpp" -name "*.a" -type f 2>/dev/null)

# Find sherpa-onnx static libs
while IFS= read -r lib; do
    LIBS+=("$lib")
done < <(find "$BUILD_DIR/sherpa-onnx" -name "*.a" -type f 2>/dev/null)

echo "Found ${#LIBS[@]} static libraries to merge"

# Step 3: Merge into single static lib
MERGED_LIB="$BUILD_DIR/librcli_merged.a"
libtool -static -o "$MERGED_LIB" "${LIBS[@]}"
echo "Merged → $MERGED_LIB ($(du -h "$MERGED_LIB" | cut -f1))"

# Step 4: Create xcframework
FRAMEWORK_OUTPUT="$OUTPUT_DIR/RCLIEngine.xcframework"
rm -rf "$FRAMEWORK_OUTPUT"

# Collect all public headers
HEADERS_DIR="$BUILD_DIR/xcframework-headers"
rm -rf "$HEADERS_DIR"
mkdir -p "$HEADERS_DIR"
cp "$ROOT_DIR/src/api/rcli_api.h" "$HEADERS_DIR/"
cp "$ROOT_DIR/src/bridge/rcli_overlay_bridge.h" "$HEADERS_DIR/"
cp "$ROOT_DIR/src/bridge/rcli_paste_bridge.h" "$HEADERS_DIR/"
cp "$ROOT_DIR/src/bridge/rcli_caret_bridge.h" "$HEADERS_DIR/"

# Create module.modulemap for Swift import
cat > "$HEADERS_DIR/module.modulemap" <<'MODULEMAP'
module CRCLIEngine {
    header "rcli_api.h"
    header "rcli_overlay_bridge.h"
    header "rcli_paste_bridge.h"
    header "rcli_caret_bridge.h"
    export *
}
MODULEMAP

xcodebuild -create-xcframework \
    -library "$MERGED_LIB" \
    -headers "$HEADERS_DIR" \
    -output "$FRAMEWORK_OUTPUT"

echo "=== xcframework created ==="
echo "$FRAMEWORK_OUTPUT"

# Step 5: Copy Metal shaders if present
METALLIB=$(find "$BUILD_DIR" -name "ggml-metal.metallib" -type f | head -1)
if [[ -n "$METALLIB" ]]; then
    RESOURCES_DIR="$OUTPUT_DIR/RCLI/Resources"
    mkdir -p "$RESOURCES_DIR"
    cp "$METALLIB" "$RESOURCES_DIR/ggml-metal.metallib"
    echo "Copied Metal shaders → $RESOURCES_DIR/ggml-metal.metallib"

    # Also copy default.metallib if it exists
    DEFAULT_METALLIB=$(find "$BUILD_DIR" -name "default.metallib" -type f | head -1)
    if [[ -n "$DEFAULT_METALLIB" ]]; then
        cp "$DEFAULT_METALLIB" "$RESOURCES_DIR/default.metallib"
        echo "Copied default.metallib → $RESOURCES_DIR/"
    fi
fi

echo "=== Done ==="
echo "xcframework: $FRAMEWORK_OUTPUT"
echo "Next: open app/RCLI.xcodeproj and add the xcframework"
```

- [ ] **Step 2: Make executable**

Run: `chmod +x /Users/rchoi/Personal/rcli-dictate/scripts/build_xcframework.sh`

- [ ] **Step 3: Run the script and verify output**

Run: `bash /Users/rchoi/Personal/rcli-dictate/scripts/build_xcframework.sh`

Expected: Script creates `app/RCLIEngine.xcframework/` containing the merged static library and headers with a `module.modulemap`.

- [ ] **Step 4: Add xcframework to .gitignore**

Add to `.gitignore`:

```
# xcframework (built artifact)
app/RCLIEngine.xcframework/
build-xcframework/
```

- [ ] **Step 5: Commit**

```bash
git add scripts/build_xcframework.sh .gitignore
git commit -m "build: add xcframework build script for macOS app"
```

## Chunk 4: Xcode Project Scaffold

### Task 9: Create the Xcode project structure

**Files:**
- Create: `app/RCLI/RCLIApp.swift`
- Create: `app/RCLI/Views/MenuBarView.swift`
- Create: `app/RCLI/State/AppState.swift`
- Create: `app/RCLI/Info.plist`
- Create: `app/RCLI/Entitlements.plist`

This task creates the minimal Swift files by hand. The Xcode project file (`.xcodeproj`) must be created in Xcode itself — you cannot reliably generate it from the command line. The plan documents what the engineer needs to configure in Xcode after creating the project.

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p app/RCLI/Views app/RCLI/Services app/RCLI/State app/RCLI/Bridge app/RCLI/Resources
```

- [ ] **Step 2: Create `app/RCLI/Entitlements.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 3: Create `app/RCLI/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>RCLI needs microphone access to hear your voice commands and dictation.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>RCLI uses AppleScript to execute actions like creating notes, opening apps, and controlling system settings.</string>
</dict>
</plist>
```

- [ ] **Step 4: Create `app/RCLI/State/AppState.swift`**

```swift
import Foundation

enum PipelineState: Int {
    case idle = 0
    case listening = 1
    case processing = 2
    case speaking = 3
    case interrupted = 4
}

enum AppLifecycleState {
    case loading
    case ready
    case error(String)
}
```

- [ ] **Step 5: Create `app/RCLI/Views/MenuBarView.swift`**

A minimal menu bar popover that shows engine state:

```swift
import SwiftUI

struct MenuBarView: View {
    @Environment(EngineService.self) private var engine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status row
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.headline)
                Spacer()
            }

            Divider()

            // Quit
            Button("Quit RCLI") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 260)
    }

    private var statusColor: Color {
        switch engine.lifecycleState {
        case .loading: return .orange
        case .ready: return .green
        case .error: return .red
        }
    }

    private var statusText: String {
        switch engine.lifecycleState {
        case .loading: return "Starting up..."
        case .ready: return "Ready"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}
```

- [ ] **Step 6: Create `app/RCLI/Services/EngineService.swift`**

A minimal EngineService that initializes the C++ engine:

```swift
import Foundation
import Observation
import CRCLIEngine

@MainActor
@Observable
final class EngineService {
    var lifecycleState: AppLifecycleState = .loading
    var pipelineState: PipelineState = .idle

    private var handle: RCLIHandle?
    private let engineQueue = DispatchQueue(label: "ai.rcli.engine")

    func initialize() async {
        lifecycleState = .loading

        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                engineQueue.async {
                    let h = rcli_create(nil)
                    guard let h else {
                        cont.resume(throwing: RCLIError.initFailed("rcli_create returned nil"))
                        return
                    }

                    let modelsDir = NSString(string: "~/Library/RCLI/models").expandingTildeInPath
                    let result = rcli_init(h, modelsDir, 99)
                    if result != 0 {
                        rcli_destroy(h)
                        cont.resume(throwing: RCLIError.initFailed("rcli_init returned \(result)"))
                        return
                    }

                    Task { @MainActor in
                        self.handle = h
                    }
                    cont.resume()
                }
            }
            lifecycleState = .ready
        } catch {
            lifecycleState = .error(error.localizedDescription)
        }
    }

    func shutdown() {
        guard let h = handle else { return }
        handle = nil
        engineQueue.async {
            rcli_deregister_all_callbacks(h)
            rcli_destroy(h)
        }
    }
}

enum RCLIError: LocalizedError {
    case initFailed(String)
    case engineNotReady

    var errorDescription: String? {
        switch self {
        case .initFailed(let msg): return "Engine init failed: \(msg)"
        case .engineNotReady: return "Engine not ready"
        }
    }
}
```

- [ ] **Step 7: Create `app/RCLI/RCLIApp.swift`**

```swift
import SwiftUI

@main
struct RCLIApp: App {
    @State private var engine = EngineService()

    var body: some Scene {
        MenuBarExtra("RCLI", systemImage: menuBarIcon) {
            MenuBarView()
                .environment(engine)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarIcon: String {
        switch engine.lifecycleState {
        case .loading: return "circle.dotted"
        case .ready: return "waveform"
        case .error: return "exclamationmark.triangle"
        }
    }
}
```

- [ ] **Step 8: Commit all scaffold files**

```bash
git add app/
git commit -m "feat(app): add SwiftUI project scaffold with minimal MenuBarExtra"
```

### Task 10: Create Xcode project and configure build settings

This task must be done manually in Xcode. It cannot be automated.

- [ ] **Step 1: Open Xcode and create a new project**

1. File → New → Project → macOS → App
2. Product Name: `RCLI`
3. Team: your developer account (or None for now)
4. Organization Identifier: `ai.runanywhere`
5. Interface: SwiftUI
6. Language: Swift
7. Save to the `app/` directory

- [ ] **Step 2: Replace generated files**

Delete the Xcode-generated `ContentView.swift` and `RCLIApp.swift`. Replace with the files created in Task 9 (they're already in `app/RCLI/`).

- [ ] **Step 3: Add the xcframework**

1. In Xcode, select the RCLI target → General → Frameworks, Libraries, and Embedded Content
2. Click + → Add Other → Add Files → select `app/RCLIEngine.xcframework`
3. Set embed to "Do Not Embed" (it's a static library)

- [ ] **Step 4: Configure build settings**

In the RCLI target build settings:
- Deployment Target: macOS 14.0
- Enable Hardened Runtime: YES
- Code Signing Entitlements: `RCLI/Entitlements.plist`
- Info.plist File: `RCLI/Info.plist`
- Swift Language Version: Swift 6 (or latest)
- Other Linker Flags: add all the frameworks the C++ engine needs:
  ```
  -framework CoreAudio -framework AudioToolbox -framework AudioUnit
  -framework Foundation -framework AVFoundation -framework IOKit
  -framework ApplicationServices -framework Carbon -framework AppKit
  -framework Metal -framework MetalKit -framework Accelerate
  ```
- Header Search Paths: add the xcframework headers path (Xcode usually handles this automatically for xcframeworks)

- [ ] **Step 5: Add Metal shader resources**

1. In Xcode, drag `app/RCLI/Resources/ggml-metal.metallib` into the project
2. Ensure it's added to the RCLI target's "Copy Bundle Resources" build phase

- [ ] **Step 6: Build the app**

Run: Cmd+B in Xcode, or from terminal:
```bash
xcodebuild -project app/RCLI.xcodeproj -scheme RCLI -configuration Debug build
```

Expected: App builds successfully. Any linker errors at this stage likely mean missing framework flags or xcframework issues — resolve by checking the Other Linker Flags.

- [ ] **Step 7: Run the app**

Run from Xcode (Cmd+R). Expected:
- A `circle.dotted` icon appears in the menu bar (loading state)
- After 2-3 seconds (engine init), it changes to `waveform` (ready)
- Clicking the icon shows the popover with "Ready" status and a Quit button
- If models aren't downloaded, it shows an error state — this is expected

- [ ] **Step 8: Commit the Xcode project**

```bash
git add app/RCLI.xcodeproj
git commit -m "feat(app): configure Xcode project with xcframework and build settings"
```

---

## Verification Checklist

After completing all tasks, verify:

- [ ] `scripts/build_xcframework.sh` produces `app/RCLIEngine.xcframework/` with headers + merged static lib
- [ ] The xcframework contains a `module.modulemap` so Swift can `import CRCLIEngine`
- [ ] `ggml-metal.metallib` is in the app bundle's Resources
- [ ] The app builds and launches from Xcode
- [ ] Menu bar icon appears and transitions from loading → ready (or error if no models)
- [ ] Clicking the icon shows the popover
- [ ] Quit button terminates the app
- [ ] The CLI (`build/rcli`) still builds and works independently
- [ ] New C API functions (`rcli_deregister_all_callbacks`, `rcli_list_available_models`, `rcli_switch_tts`, `rcli_switch_stt`) are present in the header and compile

## What's Next

Plan 2 (Services) builds on this foundation:
- EngineProviding protocol + full EngineService implementation
- HotkeyService (CGEventTap)
- OverlayService (via C bridge)
- PermissionService
- Wire up dictation flow end-to-end
