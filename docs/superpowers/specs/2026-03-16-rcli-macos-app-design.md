# RCLI macOS App — Design Spec

## Overview

Transform RCLI from a CLI/TUI tool into a native macOS application for general users. The app wraps the existing C++ voice AI engine (STT, LLM, TTS, VAD, tool calling, RAG) in a SwiftUI interface that lives in the menu bar, with an on-demand conversation panel and system-wide hotkey dictation.

**Target users:** General Mac users — approachable onboarding, no terminal knowledge required.

**Relationship to CLI:** The app is the primary product. The CLI remains as a companion for power users and development. Both link the same C++ engine as a static library.

## Architecture

### Phase 1: Single-Process (v1 — ship fast)

Everything runs in one process. SwiftUI app links the C++ engine directly via xcframework.

```
RCLI.app (single process)
├── SwiftUI Layer (MenuBarExtra, Window, Settings, Onboarding)
├── Swift Service Layer (@MainActor @Observable)
│   ├── EngineService — wraps C API (rcli_api.h)
│   ├── HotkeyService — CGEventTap (listen-only)
│   ├── OverlayService — bridges existing Obj-C++ overlay
│   ├── PermissionService — mic, Input Monitoring checks
│   └── ModelDownloadService — URL download manager
├── C++ Engine (linked xcframework)
│   └── rcli_api.h → Orchestrator → STT/LLM/TTS/VAD/Tools/RAG
└── Obj-C++ Bridge (existing overlay.mm, paste_engine.mm, caret_position.mm)
```

### Phase 2: XPC Extraction (v2 — harden)

Extract C++ engine into a bundled XPC service (`RCLIEngine.xpc`). The `EngineProviding` protocol (defined in v1) makes this a mechanical refactor — swap the concrete class, views don't change. XPC gives crash isolation (engine crash → auto-restart by launchd, UI stays up) and is Apple's endorsed pattern for ML compute isolation. Metal/GPU works from XPC with zero overhead on Apple Silicon (unified memory).

## Build Integration

- **CMake** builds the C++ engine into a static library (existing build system, untouched)
- **`scripts/build_xcframework.sh`** packages the static lib + headers into an xcframework
- **Xcode project** (`app/RCLI.xcodeproj`) links the xcframework directly + bridging header for `rcli_api.h`
- **Debug builds** can link the `.a` directly from `build/` to avoid xcframework regeneration during development
- **xcframework** is for CI/release builds only

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
│   │   │   ├── OverlayService.swift          # Bridges Obj-C++ overlay
│   │   │   ├── PermissionService.swift       # Mic, Input Monitoring
│   │   │   └── ModelDownloadService.swift    # URL download manager
│   │   ├── State/
│   │   │   └── AppState.swift          # Pipeline state, engine info
│   │   ├── Bridge/
│   │   │   └── RCLI-Bridging-Header.h  # Imports overlay, paste, caret
│   │   └── Resources/
│   │       └── Assets.xcassets
│   └── Entitlements.plist
│
└── scripts/
    └── build_xcframework.sh      # NEW — CMake → xcframework
```

## EngineService — Concurrency Design

### Protocol (v1→v2 Seam)

Views depend on `EngineProviding` protocol, not the concrete class:

```swift
@MainActor
protocol EngineProviding: Observable {
    var pipelineState: PipelineState { get }
    var transcript: String { get }
    var lastResponse: String { get }
    var audioLevel: Float { get }
    var engineInfo: EngineInfo? { get }
    var isReady: Bool { get }

    func initialize(modelsDir: String) async throws
    func shutdown()
    func startListening()
    func stopListening()
    func startCapture()
    func stopAndTranscribe() async -> String
    func processCommand(_ text: String) async -> String
    func speak(_ text: String) async
    func stopSpeaking()
    func switchModel(_ id: String) async throws
}
```

v1: `EngineService: EngineProviding` (direct C API calls)
v2: `XPCEngineService: EngineProviding` (NSXPCConnection)

### Threading Model

```
@MainActor (EngineService)
┌─────────────────────────────────────────────────┐
│ All @Observable properties live here             │
│ SwiftUI reads these safely                       │
└──────────┬──────────────────▲────────────────────┘
           │ dispatch to      │ publish results
           │ engineQueue      │ back on MainActor
engineQueue (serial DispatchQueue)
┌──────────▼──────────────────┼────────────────────┐
│ All blocking C API calls run here                │
│ rcli_init()             — 2-3s (model load)      │
│ rcli_process_command()  — 1-5s (LLM inference)   │
│ rcli_stop_capture_and_transcribe() — ~1s         │
│ rcli_switch_llm()       — 1-2s (model swap)      │
└──────────────────────────────────────────────────┘

C++ Engine Threads (STT, LLM, TTS workers)
┌──────────────────────────────────────────────────┐
│ Callbacks fire here — never touch @Observable    │
│ Use Task { @MainActor in ... } to publish        │
└──────────────────────────────────────────────────┘
```

### C Callback Pattern

Static trampoline functions with `Unmanaged` pointer for `user_data`. Callbacks dispatch to MainActor via `Task { @MainActor in }`. Critical: deregister all callbacks in `deinit` before destroying the engine handle to prevent dangling pointer crashes.

### Audio Metering

Poll `rcli_get_audio_level()` at 30Hz via `Timer.publish`. Standard pattern for audio metering (same as Logic Pro, GarageBand). `CADisplayLink` available on macOS 14+ as alternative.

## UI Design

### App Scenes

```swift
@main
struct RCLIApp: App {
    var body: some Scene {
        MenuBarExtra("RCLI", systemImage: "waveform") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)

        Window("RCLI", id: "panel") {
            PanelView()
        }
        .defaultSize(width: 420, height: 600)

        Settings {
            SettingsView()
        }
    }
}
```

`LSUIElement=YES` in Info.plist — no dock icon, menu bar only.

### 1. Menu Bar Popover

- Status indicator (green dot = ready, red pulsing = listening)
- Active model name
- Quick actions: Start Dictation (⌘J), Open Panel (⌘⇧J), Voice Mode
- Settings and Quit links
- When listening: shows live waveform visualization and partial transcript

### 2. Conversation Panel (420×600)

- Opens on demand via hotkey (⌘⇧J) or menu bar click
- Chat-style interface: user messages (voice or typed) and RCLI responses
- Tool execution traces shown inline (green accent, "Executed: create_note")
- Response timing displayed
- Model switcher in title bar
- Text input field + mic button at bottom
- Closes without quitting the app

### 3. Settings (5 tabs)

- **General**: Launch at login (SMAppService), personality, output mode (text/voice/both)
- **Models**: Download/switch LLM, STT, TTS models. Size, status, active indicator
- **Hotkeys**: Configure dictation, panel, voice mode shortcuts
- **Actions**: Enable/disable 43 macOS actions, toggle by group
- **Advanced**: GPU layers, memory pool, RAG settings, permissions status, auto-update channel

### 4. Onboarding (4-step wizard)

1. **Welcome** — what RCLI does, everything runs locally
2. **Models** — pick and download a model (Qwen3 0.6B recommended, with upgrade options)
3. **Permissions** — request microphone and Input Monitoring, with explanation before each system dialog
4. **Hotkey** — configure or accept default (⌘J)

Every step is skippable. Wizard can be re-run from Settings.

### 5. Overlay

Reuse existing Obj-C++ floating circle overlay via bridging header. Shows recording (pulsing mic) and transcribing (spinner) states near cursor position. No changes for v1.

### 6. Menu Bar Icon States

| Icon | Color | State |
|------|-------|-------|
| `waveform` | Default | Idle, ready |
| `waveform` | Red | Listening / recording |
| `bolt.fill` | Orange | Processing (LLM) |
| `speaker.wave.2` | Green | Speaking (TTS) |
| `exclamationmark.triangle` | Red | Error / permission issue |

## Permission Handling

### Required Permissions

- **Microphone**: `com.apple.security.device.audio-input` entitlement. Requested via standard system dialog.
- **Input Monitoring**: For CGEventTap (listen-only). Checked via `CGPreflightListenEventAccess()`, requested via `CGRequestListenEventAccess()`. Does NOT require Accessibility permission.

### Degradation

- **Mic denied**: Disable voice input, show text-only mode. Persistent banner with deep link to System Settings.
- **Input Monitoring denied**: Disable global hotkey. App still works via menu bar click and panel. Settings shows prompt to enable.
- **Permission revoked while running**: PermissionService polls every 30s. On revocation, disable affected feature and show banner. On re-grant, re-enable automatically.
- **Onboarding**: Explain WHY before each system dialog. Allow skipping — user can grant later.

## Core User Flows

### Hotkey Dictation (primary)

```
User presses ⌘J
→ HotkeyService detects keydown
→ OverlayService.show(.recording, caretPosition)
→ EngineService.startCapture()
→ (user speaks, audioLevel updates overlay waveform)
→ User releases ⌘J / presses Enter / Escape
→ OverlayService.setState(.transcribing)
→ text = await EngineService.stopAndTranscribe()
→ PasteEngine.paste(text, to: frontmostApp)
→ OverlayService.dismiss()
```

### Voice Command

```
User activates voice command (hotkey or panel button)
→ EngineService.startListening() (live pipeline: mic → STT → LLM → TTS)
→ Callbacks stream to UI:
   - transcriptCallback → PanelView shows live transcript
   - stateCallback → UI updates (listening → processing → speaking)
   - toolTraceCallback → PanelView shows "Opening Safari..."
   - responseCallback → PanelView shows response
→ Pipeline completes (or barge-in interrupt)
→ pipelineState → .idle
```

### Text Command

```
User types in PanelView
→ response = await EngineService.processCommand(text)
→ Tool traces and response appear in conversation
```

### App Launch

```
App starts (login item or manual)
→ Check first-run flag
→ First run: show OnboardingView (models → permissions → hotkey)
→ EngineService.initialize(modelsDir:)  // 2-3s, show loading in menu bar
→ HotkeyService.start()
→ Menu bar icon active, app ready
```

## Dependencies

| Dependency | Purpose | Integration |
|-----------|---------|-------------|
| SettingsAccess | Fix SettingsLink in MenuBarExtra | SPM |
| Sparkle | Auto-updates (non-App Store) | SPM |
| rcli_engine.xcframework | C++ engine | Binary (CMake-built) |
| Existing Obj-C++ | overlay.mm, paste_engine.mm, caret_position.mm | Bridging header |

## Distribution

- **Developer ID** certificate (Apple Developer Program, $99/year)
- **Hardened Runtime** enabled
- **Notarization** via `notarytool` (not App Store — no sandbox required)
- **Sparkle** for auto-updates
- Entitlements: `com.apple.security.device.audio-input`, possibly `com.apple.security.cs.disable-library-validation` if loading unsigned dylibs

## Visual Style Direction

Based on reference mockups. These are stylistic guidelines, not pixel-exact wireframes.

- Dark mode primary with macOS vibrancy/translucency on panels and popovers (NSVisualEffectView / `.ultraThinMaterial`)
- Native macOS chrome throughout — no custom window decorations, follow HIG
- SF Symbols for all iconography. Waveform motif as a recurring brand element.
- Menu bar popover styled like Control Center — compact, dark, translucent background
- Quick actions in the popover as side-by-side tappable cards (Start Dictation, Open Panel) rather than a flat list
- Conversation panel: dark background, user messages as colored bubbles (right-aligned or accent-tinted), assistant responses in neutral cards. Tool traces as compact green-accented inline badges.
- Settings: standard macOS tab bar with SF Symbol icons per tab. Models tab splits LLM and STT/TTS into sections with disk usage bar at the bottom.
- Onboarding: horizontal step indicator (numbered circles connected by lines) at the top rather than a sidebar. Three feature cards on the welcome screen (Voice Commands, Dictation, Private). Clean, spacious, one action per step.
- Model cards in onboarding as rounded, selectable tiles with accent border on selection and a "Recommended" tag on the default option.
- Accent color: system blue default. Waveform icon tinted per state in the menu bar.
- Loading state icon: three-dot animation pattern (distinct from the other SF Symbol states)

## Open Questions

- App name: RCLI? Something user-facing? (mockups explored "wave form" as a direction)
- App icon: needs design — waveform motif is the leading direction
- Conversation persistence: save history across sessions? How much?
- Multiple windows: can user open multiple conversation panels?
- RAG in the app: expose document ingestion in the UI, or keep it CLI-only for v1?
- Voice mode in the app: always-listening wake word — include in v1 or defer?
