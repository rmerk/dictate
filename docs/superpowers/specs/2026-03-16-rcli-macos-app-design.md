# RCLI macOS App — Design Spec

## Overview

Transform RCLI from a CLI/TUI tool into a native macOS application for general users. The app wraps the existing C++ voice AI engine (STT, LLM, TTS, VAD, tool calling, RAG) in a SwiftUI interface that lives in the menu bar, with an on-demand conversation panel and system-wide hotkey dictation.

Target users: General Mac users — approachable onboarding, no terminal knowledge required.

Relationship to CLI: The app is the primary product. The CLI remains as a companion for power users and development. Both link the same C++ engine as a static library.

## Architecture

### Phase 1: Single-Process (v1 — ship fast)

Everything runs in one process. SwiftUI app links the C++ engine directly via xcframework.

```
RCLI.app (single process)
├── SwiftUI Layer (MenuBarExtra, Window, Settings, Onboarding)
├── Swift Service Layer (@MainActor @Observable)
│   ├── EngineService — wraps C API (rcli_api.h)
│   ├── HotkeyService — CGEventTap (active, consumes hotkey)
│   ├── OverlayService — bridges C wrapper for overlay
│   ├── PermissionService — mic, Accessibility checks
│   └── ModelDownloadService — URL download manager
├── C++ Engine (linked xcframework)
│   └── rcli_api.h → Orchestrator → STT/LLM/TTS/VAD/Tools/RAG
├── C Bridge Layer (pure C wrappers for Obj-C++ code)
│   └── rcli_overlay_bridge.h, rcli_paste_bridge.h, rcli_caret_bridge.h
└── Obj-C++ Implementations (overlay.mm, paste_engine.mm, caret_position.mm)
```

### Phase 2: XPC Extraction (v2 — harden)

Extract C++ engine into a bundled XPC service (`RCLIEngine.xpc`). The `EngineProviding` protocol (defined in v1) makes this a mechanical refactor — swap the concrete class, views don't change. XPC gives crash isolation (engine crash → auto-restart by launchd, UI stays up) and is Apple's endorsed pattern for ML compute isolation. Metal/GPU works from XPC on Apple Silicon (unified memory); IPC overhead is negligible for audio/text data.

## Build Integration

- CMake builds the C++ engine into a static library (existing build system, untouched)
- `scripts/build_xcframework.sh` merges all static libs (`libtool -static -o librcli_merged.a librcli.a libllama.a libggml.a libsherpa-onnx-c-api.a ...`), packages into xcframework
- Metal shaders (`ggml-metal.metallib`) must be copied into the app bundle's Resources separately — they cannot be embedded in a static library
- Xcode project (`app/RCLI.xcodeproj`) links the xcframework directly + bridging header for C APIs
- Debug builds can link the `.a` directly from `build/` to avoid xcframework regeneration
- xcframework is for CI/release builds only

## Repo Structure

```
rcli/
├── src/                          # Existing C++ (untouched)
├── CMakeLists.txt                # Existing build
├── build/                        # CLI build output
│
├── app/                          # NEW — macOS app
│   ├── RCLI.xcodeproj/
│   ├── RCLI/                     # App target
│   │   ├── RCLIApp.swift         # @main, scenes (MenuBarExtra + Window + Settings)
│   │   ├── Views/
│   │   │   ├── MenuBarView.swift       # Menu bar popover content
│   │   │   ├── PanelView.swift         # Conversation window
│   │   │   ├── SettingsView.swift      # Preferences (5 tabs)
│   │   │   ├── OnboardingView.swift    # First-run wizard
│   │   │   └── ModelManagerView.swift  # Download/switch models
│   │   ├── Services/
│   │   │   ├── EngineService.swift           # @MainActor @Observable, wraps C API
│   │   │   ├── EngineService+Voice.swift     # Listening, capture, transcribe
│   │   │   ├── EngineService+Commands.swift  # processCommand, speak
│   │   │   ├── EngineService+Models.swift    # switchModel, getInfo
│   │   │   ├── EngineService+RAG.swift       # Ingest, query
│   │   │   ├── HotkeyService.swift           # CGEventTap wrapper
│   │   │   ├── OverlayService.swift          # Bridges C overlay wrapper
│   │   │   ├── PermissionService.swift       # Mic, Accessibility
│   │   │   └── ModelDownloadService.swift    # URL download manager
│   │   ├── State/
│   │   │   └── AppState.swift          # Pipeline state, engine info
│   │   ├── Bridge/
│   │   │   └── RCLI-Bridging-Header.h  # Imports C wrappers (NOT Obj-C++ headers)
│   │   └── Resources/
│   │       └── Assets.xcassets
│   └── Entitlements.plist
│
├── src/bridge/                   # NEW — Pure C wrappers for Obj-C++ code
│   ├── rcli_overlay_bridge.h     # C functions wrapping overlay.mm
│   ├── rcli_overlay_bridge.mm
│   ├── rcli_paste_bridge.h       # C functions wrapping paste_engine.mm
│   ├── rcli_paste_bridge.mm
│   ├── rcli_caret_bridge.h       # C functions wrapping caret_position.mm
│   └── rcli_caret_bridge.mm
│
└── scripts/
    └── build_xcframework.sh      # NEW — CMake → merged static lib → xcframework
```

## EngineService — Concurrency Design

### Deployment Target

macOS 14 (Sonoma). This gives us `@Observable`, `MenuBarExtra(.window)`, `SMAppService`, and `CADisplayLink`. For Accessibility permission checks, use `AXIsProcessTrusted()` (available on all macOS versions).

### Protocol (v1→v2 Seam)

Views depend on `EngineProviding` protocol, not the concrete class. The protocol covers the full C API surface organized by concern.

```swift
@MainActor
protocol EngineProviding: Observable {
    // — Observable State (drives SwiftUI) —
    var pipelineState: PipelineState { get }
    var transcript: String { get }
    var isTranscriptFinal: Bool { get }
    var lastResponse: String { get }
    var audioLevel: Float { get }
    var isReady: Bool { get }

    // — Event Streams (callbacks → Swift) —
    var transcriptStream: AsyncStream<TranscriptEvent> { get }
    var stateStream: AsyncStream<PipelineState> { get }
    var toolTraceStream: AsyncStream<ToolTraceEvent> { get }
    var responseStream: AsyncStream<String> { get }

    // — Lifecycle —
    func initialize(modelsDir: String, gpuLayers: Int) async throws
    func initializeSTTOnly(modelsDir: String, gpuLayers: Int) async throws
    func shutdown()

    // — Voice Pipeline (live mode: mic → STT → LLM → TTS) —
    func startListening()
    func stopListening()
    func processAndSpeak(_ text: String) async throws -> String
    func stopProcessing()  // universal cancel

    // — Push-to-Talk (dictation) —
    func startCapture()
    func stopAndTranscribe() async throws -> String

    // — Text Commands —
    func processCommand(_ text: String) async throws -> String

    // — TTS —
    func speak(_ text: String) async throws  // uses rcli_speak_streaming (CoreAudio)
    func stopSpeaking()
    var isSpeaking: Bool { get }

    // — Models —
    func switchModel(_ id: String) async throws
    func listAvailableModels() async throws -> [ModelInfo]  // requires new C API
    var activeModel: String { get }
    var activeTTSModel: String { get }
    var activeSTTModel: String { get }
    var activeEngine: String { get }

    // — Personality —
    var personality: String { get }
    func setPersonality(_ key: String) throws

    // — Actions —
    func listActions() async -> [ActionInfo]
    func setActionEnabled(_ name: String, enabled: Bool)
    func isActionEnabled(_ name: String) -> Bool
    func saveActionPreferences() throws
    func disableAllActions()
    func resetActionsToDefaults()
    var enabledActionCount: Int { get }

    // — RAG —
    func ragIngest(directory: String) async throws
    func ragLoadIndex(path: String) async throws
    func ragQuery(_ query: String) async throws -> String
    func ragClear()

    // — Voice Mode —
    func startVoiceMode(wakePhrase: String) async throws
    func stopVoiceMode()

    // — Barge-In —
    func setBargeInEnabled(_ enabled: Bool)
    func isBargeInEnabled() -> Bool
    var interruptedResponse: String { get }

    // — Conversation —
    func clearHistory()

    // — Info —
    func getInfo() async -> String  // JSON
    func getContextInfo() async -> (promptTokens: Int, contextSize: Int)
}
```

v1: `EngineService: EngineProviding` (direct C API calls)
v2: `XPCEngineService: EngineProviding` (NSXPCConnection)

### String Lifetime Rule

All C API calls that return `const char*` with "Caller must NOT free" must be immediately copied to a Swift `String` synchronously on the same thread before any other C API call. The pointer may be invalidated by the next call. This applies in both trampolines (copy before yielding to AsyncStream) and engineQueue blocks (copy before resuming continuation).

The one exception is `rcli_get_timings()` which returns caller-owned `char*` — wrap with `defer { free(ptr) }`.

### Callback Delivery — Single Path via AsyncStream

C callbacks are bridged to Swift via `AsyncStream` as the single delivery mechanism. There is NO dual path — trampolines yield into streams, and an internal `.task` consumer on `EngineService` reads from the streams and updates `@Observable` properties. Views bind to the `@Observable` properties for simple cases, or consume streams directly for real-time updates.

```swift
// In EngineService init:
let (transcriptStream, transcriptContinuation) = AsyncStream.makeStream(of: TranscriptEvent.self)

// Store continuation as nonisolated(unsafe) — accessed only from C trampolines
nonisolated(unsafe) let continuation = transcriptContinuation

// Static trampoline (fires on C++ thread):
// 1. Copy string synchronously (before pointer is invalidated)
// 2. Yield into stream (Sendable, safe from any thread)
private let transcriptTrampoline: RCLITranscriptCallback = {
    text, isFinal, userData in
    let service = Unmanaged<EngineService>
        .fromOpaque(userData!).takeUnretainedValue()
    let str = String(cString: text!)  // copy immediately
    service.continuation.yield(TranscriptEvent(text: str, isFinal: isFinal != 0))
}

// Internal consumer (started once at init, updates @Observable):
Task { @MainActor [weak self] in
    guard let self else { return }
    for await event in transcriptStream {
        self.transcript = event.text
        self.isTranscriptFinal = event.isFinal
    }
}
```

### Threading Model

```
@MainActor (EngineService)
┌─────────────────────────────────────────────────┐
│ All @Observable properties live here             │
│ SwiftUI reads these safely                       │
│ Internal .task consumers update from streams     │
└──────────┬──────────────────▲────────────────────┘
           │ dispatch to      │ resume continuation
           │ engineQueue      │
engineQueue (serial DispatchQueue — blocking C calls)
┌──────────▼──────────────────┼────────────────────┐
│ rcli_init()             — 2-3s (model load)      │
│ rcli_process_command()  — 1-5s (LLM inference)   │
│ rcli_stop_capture_and_transcribe() — ~1s         │
│ rcli_switch_llm()       — 1-2s (model swap)      │
│                                                  │
│ Pattern:                                         │
│   withCheckedThrowingContinuation { cont in      │
│       engineQueue.async {                        │
│           let result = rcli_xxx(handle, ...)     │
│           guard let result else {                │
│               cont.resume(throwing: .failed(...))│
│               return                             │
│           }                                      │
│           let str = String(cString: result)      │
│           cont.resume(returning: str)            │
│       }                                          │
│   }                                              │
└──────────────────────────────────────────────────┘

ttsQueue (separate serial DispatchQueue — TTS playback)
┌──────────────────────────────────────────────────┐
│ rcli_speak_streaming()  — blocks for duration    │
│ Separate queue so engineQueue isn't blocked      │
│ rcli_stop_speaking() is thread-safe, callable    │
│ from anywhere                                    │
└──────────────────────────────────────────────────┘

C++ Engine Threads (STT, LLM, TTS workers)
┌──────────────────────────────────────────────────┐
│ Callbacks fire here                              │
│ 1. Copy const char* to String synchronously      │
│ 2. Yield into AsyncStream continuation           │
│ (continuation is nonisolated(unsafe), Sendable)  │
└──────────────────────────────────────────────────┘
```

### Callback Registration & Cleanup

Use `Unmanaged.passUnretained(self)` for `user_data` (NOT `passRetained` — that creates a retain cycle). `EngineService` is held alive by the SwiftUI environment for the app's lifetime, so the unretained pointer is safe as long as callbacks are deregistered before deallocation.

Cleanup requires a new C API function:

```c
// NEW — Add to rcli_api.h
// Deregister all callbacks under engine mutex and wait for any in-flight
// callback to complete. Must be called before rcli_destroy().
void rcli_deregister_all_callbacks(RCLIHandle handle);
```

`EngineService.deinit` calls `rcli_deregister_all_callbacks(handle)` then `rcli_destroy(handle)`.

### Audio Metering

Poll `rcli_get_audio_level()` at 30Hz via `Timer.publish`. Dispatch the read to `engineQueue` to avoid racing with concurrent C API calls. Standard pattern for audio metering.

### Error Handling

All `async throws` methods use `withCheckedThrowingContinuation` and throw `RCLIError`:

```swift
enum RCLIError: LocalizedError {
    case initFailed(String)           // rcli_init returned non-zero
    case modelNotFound(String)        // model file missing
    case modelLoadFailed(String)      // rcli_switch_llm failed
    case permissionDenied(Permission) // mic or accessibility
    case engineNotReady               // called before init
    case commandFailed(String)        // rcli_process_command returned NULL
    case transcriptionFailed          // rcli_stop_capture_and_transcribe returned NULL
    case ragIngestFailed(String)      // document processing error
    case speakFailed                  // rcli_speak_streaming returned non-zero
}
```

UI error surfaces:
- Menu bar popover banner: persistent issues (permissions, init failure)
- Conversation panel inline: per-request failures (command failed, model OOM)
- Onboarding alert: setup failures (download failed, permission denied)
- Init failure recovery: menu bar popover shows error state with "Re-download Models" button, "Try Smaller Model" suggestion, and "Open Settings" link

## UI Design

### App Scenes

```swift
@main
struct RCLIApp: App {
    @State private var engine = EngineService()

    var body: some Scene {
        MenuBarExtra("RCLI", systemImage: "waveform") {
            MenuBarView()
                .environment(engine)
        }
        .menuBarExtraStyle(.window)

        Window("RCLI", id: "panel") {
            PanelView()
                .environment(engine)
        }
        .defaultSize(width: 420, height: 600)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environment(engine)
        }
    }
}
```

`LSUIElement=YES` in Info.plist — no dock icon, menu bar only. During onboarding, temporarily call `NSApp.setActivationPolicy(.regular)` to ensure permission dialogs are visible, then switch back to `.accessory` when complete.

### 1. Menu Bar Popover (~280px wide)

- Status indicator (green dot = ready, red pulsing = listening)
- Active model name
- Quick actions as side-by-side tappable cards: Start Dictation (⌘J), Open Panel (⌘⇧J)
- Voice Mode toggle
- Settings and Quit links
- When listening: shows live waveform visualization and partial transcript
- Loading state: "Starting up..." with progress indicator, disabled quick actions (shown during 2-3s engine init)
- Error state: error description + "Open Settings" / "Re-download Models" actions

### 2. Conversation Panel (420×600)

- Opens on demand via hotkey (⌘⇧J) or menu bar click
- Chat-style interface: user messages (voice or typed) and RCLI responses
- Tool execution traces shown inline as compact green-accented badges
- Response timing displayed
- Model switcher in title bar
- Text input field + mic button at bottom
- Closes without quitting the app
- Empty state: "Try saying..." with 3-4 example commands and a visual hint about ⌘J

### 3. Settings (5 tabs)

- General: Launch at login (SMAppService), personality, output mode (text/voice/both)
- Models: Download/switch LLM, STT, TTS models. LLM and STT/TTS in separate sections. Size, status, active indicator. Disk usage bar at bottom.
- Hotkeys: Configure dictation, panel, voice mode shortcuts. Note: "⌘J is also used by Safari for Downloads. Choose a different shortcut if this conflicts."
- Actions: All actions enabled by default. Simple view shows category toggles (Productivity, System, Media). "Customize individual actions" disclosure reveals the full 43-toggle list with search/filter.
- Advanced: Performance picker ("Balanced" / "Maximum Quality" / "Battery Saver" mapping to GPU layer presets). Permissions status panel with "Open System Settings" buttons. RAG settings (v2). Auto-update channel.

### 4. Onboarding (4-step wizard)

Horizontal step indicator at top (1-2-3-4 with connecting lines).

1. Welcome — what RCLI does, three feature cards (Voice Commands, Dictation, Private), "Get Started"
2. Models — pick and download a model. Download starts immediately on selection and continues in background while user proceeds to steps 3-4. Progress shown as secondary indicator. Retry button on failure with resume support. "Skip for now" clearly states "You can download later from Settings."
3. Permissions — three permissions requested in order:
   - Microphone (one-click system dialog, highest success rate)
   - Accessibility (required for hotkey + paste + caret detection). Explanation: "RCLI needs Accessibility to detect your keyboard shortcut and paste text into apps. It does not log or record any keystrokes." Visual guide showing where to toggle in System Settings. Auto-detect when granted.
   - Each permission shows ✓ when granted, skippable
4. Hotkey — "Set your dictation shortcut" with key recorder. Default ⌘J.

Every step is skippable. Wizard can be re-run from Settings. Post-onboarding: show macOS notification "You're all set! Press ⌘J anywhere to start dictating."

### 5. Overlay

Reuse existing Obj-C++ floating circle overlay via C bridge wrappers. Shows recording (pulsing mic) and transcribing (spinner) states near cursor position. No changes for v1.

### 6. Menu Bar Icon States

| Icon | Color | State |
|------|-------|-------|
| `waveform` | Default (template) | Idle, ready |
| `waveform` | Tinted red | Listening / recording |
| `bolt.fill` | Tinted orange | Processing (LLM) / Speaking (TTS) |
| `exclamationmark.triangle` | Tinted red | Error / permission issue |
| `circle.dotted` | Default | Loading (engine init, ~3s at launch) |

Note: Collapsed Processing and Speaking into one "Working" state (bolt.fill orange) per UX review — users don't need to distinguish these. Use SF Symbol shape as primary differentiator; color is secondary (may not render on all menu bar backgrounds).

## Permission Handling

### Required Permissions

- Microphone: `com.apple.security.device.audio-input` entitlement. Standard system dialog.
- Accessibility: Required for CGEventTap (active/filter mode to consume hotkey), paste engine (CGEventPost for ⌘V), and caret position detection (AXUIElement). Checked via `AXIsProcessTrusted()`. Requested via `AXIsProcessTrustedWithOptions` with prompt during onboarding (app must be `.regular` activation policy for dialog to appear).

### Degradation

- Mic denied: Disable voice input, show text-only mode. Persistent banner with deep link to System Settings > Privacy > Microphone.
- Accessibility denied: Disable global hotkey and paste-after-dictation. App still works via menu bar click + panel + text commands. Settings shows prompt with visual guide to enable.
- Both denied: App functions as text-only command tool via panel. Show prominent setup prompt.
- Permission revoked while running: PermissionService polls every 2-3s when permission banner is visible or app just became frontmost; every 30s otherwise. On revocation, disable affected feature and show banner. On re-grant, re-enable automatically.
- Onboarding: Explain WHY before each system dialog. Add privacy reassurance for Accessibility ("does not log keystrokes"). Allow skipping — user can grant later.

## Core User Flows

### Hotkey Dictation (primary)

```
User presses ⌘J
→ HotkeyService (active CGEventTap) detects and consumes the event
→ OverlayService.show(.recording, caretPosition)
→ EngineService.startCapture()
→ (user speaks, audioLevel updates overlay waveform)
→ User releases ⌘J / presses Enter / Escape
→ OverlayService.setState(.transcribing)
→ text = try await EngineService.stopAndTranscribe()
→ PasteEngine.paste(text, to: frontmostApp)
→ OverlayService.dismiss()
```

### Voice Command

```
User activates voice command (hotkey or panel button)
→ EngineService.startListening() (live pipeline: mic → STT → LLM → TTS)
→ AsyncStreams deliver events to UI:
   - transcriptStream → PanelView shows live transcript
   - stateStream → UI updates (listening → processing → speaking)
   - toolTraceStream → PanelView shows "Opening Safari..."
   - responseStream → PanelView shows response
→ Pipeline completes (or barge-in interrupt)
→ pipelineState → .idle
```

### Text Command

```
User types in PanelView
→ response = try await EngineService.processCommand(text)
→ Tool traces and response appear in conversation
```

### App Launch

```
App starts (login item or manual)
→ Check first-run flag
→ First run: show OnboardingView
   → Model download begins in background
   → User proceeds through permissions + hotkey while download continues
   → Post-onboarding: if download still in progress, show "Finishing setup..." in popover
→ EngineService.initialize(modelsDir:gpuLayers:)  // 2-3s
   → Menu bar icon shows circle.dotted during init
   → Popover shows "Starting up..." with disabled actions
   → On failure: show error state with recovery actions
→ HotkeyService.start()
→ Menu bar icon → waveform, app ready
→ First time: send notification "You're all set! Press ⌘J to start dictating"
```

### Sleep/Wake

```
macOS sleep detected
→ Cancel any active session (recording, listening, processing)
→ Dismiss overlay if visible
→ Set pipelineState → .idle
macOS wake detected
→ Engine remains initialized (models in memory)
→ Re-verify permissions (poll immediately)
→ Ready for next interaction
```

## New C API Functions Required

```c
// Deregister all callbacks under engine mutex, wait for in-flight callbacks.
// Must be called before rcli_destroy().
void rcli_deregister_all_callbacks(RCLIHandle handle);

// List available models in the registry as JSON.
// Returns JSON array: [{id, name, size_bytes, download_url, is_downloaded}]
// Caller must free() the returned string.
const char* rcli_list_available_models(RCLIHandle handle);

// Switch TTS voice at runtime.
// Returns 0 on success, -1 on failure.
int rcli_switch_tts(RCLIHandle handle, const char* model_id);

// Switch STT model at runtime.
// Returns 0 on success, -1 on failure.
int rcli_switch_stt(RCLIHandle handle, const char* model_id);
```

## C Bridge Layer (Obj-C++ → Pure C)

Existing Obj-C++ headers (`overlay.h`, `paste_engine.h`, `caret_position.h`) use C++ types (`std::string`, `std::optional`, `std::function`) which cannot be imported via Swift bridging headers. Thin C wrappers expose the functionality:

```c
// rcli_overlay_bridge.h
void rcli_overlay_init(void);
void rcli_overlay_show(int state, double x, double y, int has_position);
void rcli_overlay_set_state(int state);
void rcli_overlay_dismiss(void);
void rcli_overlay_cleanup(void);

// rcli_paste_bridge.h
int rcli_paste_text(const char* text);

// rcli_caret_bridge.h
int rcli_get_caret_position(double* out_x, double* out_y);
```

## Dependencies

| Dependency | Purpose | Integration |
|-----------|---------|-------------|
| SettingsAccess | Fix SettingsLink in MenuBarExtra | SPM |
| Sparkle | Auto-updates (non-App Store) | SPM |
| rcli_engine.xcframework | C++ engine (merged static libs) | Binary (CMake-built) |
| Obj-C++ bridge wrappers | C wrappers for overlay, paste, caret | Compiled into xcframework |

## Distribution

### Entitlements (complete list)

```xml
<!-- Entitlements.plist -->
com.apple.security.device.audio-input              <!-- Microphone -->
com.apple.security.automation.apple-events          <!-- AppleScript actions (43 macOS actions) -->
com.apple.security.cs.disable-library-validation    <!-- Required: vendored llama.cpp/sherpa-onnx static libs -->
```

Additional if needed (test under Hardened Runtime):
- `com.apple.security.cs.allow-unsigned-executable-memory` — if llama.cpp or ONNX Runtime uses JIT/runtime code generation

### Info.plist keys

```xml
LSUIElement: YES
NSMicrophoneUsageDescription: "RCLI needs microphone access to hear your voice commands and dictation."
NSAppleEventsUsageDescription: "RCLI uses AppleScript to execute actions like creating notes, opening apps, and controlling system settings."
SUFeedURL: "<sparkle appcast URL>"
```

### Signing & Notarization

- Developer ID certificate (Apple Developer Program, $99/year)
- Hardened Runtime enabled
- Notarization via `notarytool` (not App Store — no sandbox required)
- Sparkle for auto-updates — signing identity must match between running app and downloaded update
- Non-sandboxed + notarized is a well-established pattern (Homebrew, VS Code, Alfred)

### Sparkle Requirements

- `SUFeedURL` in Info.plist pointing to appcast XML
- App must be code signed with a stable Developer ID
- Sparkle verifies signing identity of downloaded updates matches running app
- No network entitlement needed (non-sandboxed apps have unrestricted network access)

## Visual Style Direction

Based on reference mockups. These are stylistic guidelines, not pixel-exact wireframes.

- Dark mode primary with macOS vibrancy/translucency on panels and popovers (NSVisualEffectView / `.ultraThinMaterial`)
- Native macOS chrome throughout — no custom window decorations, follow HIG
- SF Symbols for all iconography. Waveform motif as a recurring brand element.
- Menu bar popover styled like Control Center — compact, dark, translucent background
- Quick actions in the popover as side-by-side tappable cards (Start Dictation, Open Panel) rather than a flat list
- Conversation panel: dark background, user messages as colored bubbles (right-aligned or accent-tinted), assistant responses in neutral cards. Tool traces as compact green-accented inline badges.
- Settings: standard macOS tab bar with SF Symbol icons per tab. Models tab splits LLM and STT/TTS into sections with disk usage bar at the bottom.
- Onboarding: horizontal step indicator (numbered circles connected by lines) at the top. Three feature cards on the welcome screen (Voice Commands, Dictation, Private). Clean, spacious, one action per step.
- Model cards in onboarding as rounded, selectable tiles with accent border on selection and a "Recommended" tag on the default option.
- Accent color: system blue default. SF Symbol shape changes are the primary state differentiator in the menu bar; color tinting is secondary.
- Loading state icon: `circle.dotted` SF Symbol

## Model Downloads

Models are downloaded via `ModelDownloadService` using `URLSession` with background download support.

- Source: same URLs as `scripts/download_models.sh` (Hugging Face CDN). Model registry exposed via new `rcli_list_available_models()` C API to avoid duplicating URLs in Swift.
- Storage: `~/Library/RCLI/models/` (shared with CLI, outside app sandbox)
- Resume: `URLSessionDownloadTask` supports automatic resume on interruption
- Integrity: SHA256 checksum verification after download (checksums in model registry)
- Progress: published as `@Observable` properties for UI binding (per-model progress, overall progress). Download progress also visible in menu bar popover when active.
- Failure: retry button with resume support. Clear error message ("Download failed — check your internet connection"). Partial downloads resume automatically.
- Onboarding: download begins immediately on model selection and continues in background while user proceeds through permissions and hotkey steps.

## Decisions (Resolved)

- CGEventTap mode: Active tap (`kCGEventTapOptionDefault`) that consumes the hotkey event (returns NULL). Requires Accessibility permission, matching the existing working implementation in `hotkey_listener.mm`.
- Conversation persistence: v1 does NOT persist across sessions. In-memory only. Persistence is a v2 feature.
- Multiple panels: No. Single `Window` (not `WindowGroup`). One conversation panel instance.
- RAG in app: CLI-only for v1. Protocol includes RAG methods for future use.
- Voice mode: included in v1 as a menu bar quick action.
- `rcli_speak` vs `rcli_speak_streaming`: always use `rcli_speak_streaming` (CoreAudio ring buffer) on a dedicated `ttsQueue`. Never use `rcli_speak` (afplay subprocess).
- Obj-C++ bridging: C wrapper functions (not direct Obj-C++ imports) since Swift bridging headers cannot import C++ types.
- Actions UI: category-level toggles by default, individual 43-action list behind "Customize" disclosure.
- GPU layers: exposed as "Performance" picker (Balanced/Maximum Quality/Battery Saver), not a raw slider.

## Open Questions

- App name: RCLI? Something user-facing? (mockups explored "wave form" as a direction)
- App icon: needs design — waveform motif is the leading direction
- VoiceOver and keyboard navigation: accessibility audit needed before shipping
