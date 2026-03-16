# RCLI macOS App — UI Design Prompt

## What is RCLI?

RCLI is an on-device voice AI assistant for macOS. It runs entirely locally — no cloud, no API keys. Users speak commands ("open Safari", "create a note called Ideas") and RCLI executes them. It also does dictation (speak → text pasted into any app) and general conversation.

The app lives in the **menu bar** — no dock icon. It's invisible until you need it. Think Raycast or Alfred, but voice-first.

## Target User

General Mac users. Not developers. They shouldn't need to understand models, terminals, or permissions. The app should feel as simple as Apple's built-in Dictation, but far more capable.

## Platform & Constraints

- **macOS 14+ (Sonoma)**, Apple Silicon
- **SwiftUI** with `MenuBarExtra` (`.window` style popover)
- **Dark mode primary**, light mode supported
- **SF Symbols** for all icons
- App is `LSUIElement` — no dock icon, no app menu bar. Menu bar icon only.
- Native macOS look and feel. No custom chrome. Follow Apple HIG.

---

## Surfaces to Design

### 1. Menu Bar Icon

A single icon in the macOS menu bar (right side, near Wi-Fi/battery). Changes to reflect the current state:

| State | Icon | Color | Notes |
|-------|------|-------|-------|
| Idle / ready | `waveform` | Default (template) | Normal state, most of the time |
| Listening | `waveform` | Red / accent | User is speaking, mic is active |
| Processing | `bolt.fill` | Orange | AI is thinking (LLM inference) |
| Speaking | `speaker.wave.2` | Green | AI is speaking back (TTS) |
| Error | `exclamationmark.triangle` | Red | Permission missing or engine error |
| Loading | `circle.dotted` | Default | Engine initializing at launch (~3s) |

### 2. Menu Bar Popover

Clicking the menu bar icon opens a popover (SwiftUI `MenuBarExtra` with `.window` style). This is the home base — at-a-glance status and quick actions.

**Contents:**
- **Status row**: Green/red dot + state label ("Ready", "Listening...") + active model name (e.g., "Qwen3 0.6B")
- **Quick actions** (large tap targets):
  - Start Dictation — shortcut label ⌘J
  - Open Panel — shortcut label ⌘⇧J
  - Voice Mode (always-listening)
- **When listening**: Replace quick actions with a live waveform visualization + partial transcript text + "Press ⌘J or Enter to stop" hint
- **Footer**: Settings link, Quit link

**Design notes:**
- Keep it compact — this is a popover, not a window
- Should feel like Control Center or the Wi-Fi menu, not a full app
- ~280px wide max

### 3. Conversation Panel

A standalone window (not attached to the menu bar) for extended interaction. Opens via ⌘⇧J or the menu bar "Open Panel" action. Closeable without quitting the app.

**Size:** 420×600 default, resizable with min size

**Layout (top to bottom):**

**Title bar area:**
- App name "RCLI" left-aligned
- Model picker (dropdown/popup button) right-aligned — shows active model, click to switch

**Conversation area (scrolling):**
- Chat-style message bubbles/rows
- User messages show: text, input method badge (🎤 voice / ⌨️ typed), timestamp
- Assistant responses show: text, response time (e.g., "347ms")
- Tool execution traces inline between user message and response — green accent, compact (e.g., "✓ Executed: create_note — Created 'Ideas' in Notes")
- When assistant is thinking: typing indicator or "Processing..." state

**Input bar (bottom, fixed):**
- Text field: "Type a command or press ⌘J to speak..."
- Mic button (circular) to the right of the text field — tap to start voice input within the panel
- Send button appears when text is entered

**Design notes:**
- The conversation panel should feel like iMessage or the Shortcuts app conversation view — clean, native, not busy
- Tool traces should be visually distinct but not dominant — they're supporting info
- The panel is the "20% case" — most users interact via hotkey dictation and never open this

### 4. Settings Window

Standard macOS Preferences window, opened via ⌘, from the menu bar popover, or via the onboarding "re-run" option. Uses `Settings` scene with tabbed navigation (macOS standard `TabView` with `.tabViewStyle(.automatic)`).

**Tabs:**

**General**
- Launch at login (toggle) — uses SMAppService
- Personality picker (dropdown): Default, Professional, Quirky, etc.
- Output mode: Text only / Voice only / Both (segmented control)
- Check for updates (Sparkle)

**Models**
- List of model categories: LLM, STT, TTS
- Each model shows: name, size, status (Downloaded / Not Downloaded / Active)
- Download button with progress bar
- "Active" checkmark on the selected model
- Delete button for downloaded models (with confirmation)
- Show total disk usage

**Hotkeys**
- Dictation hotkey recorder (default ⌘J)
- Panel hotkey recorder (default ⌘⇧J)
- Voice mode hotkey recorder
- Standard macOS key recorder UI (click to record, press new combo)

**Actions**
- List of all 43 macOS actions, grouped by category (Productivity, System, Media, etc.)
- Toggle switch for each action
- "Enable All" / "Disable All" buttons
- Search/filter field at top
- Brief description for each action

**Advanced**
- GPU layers slider (0–99, default 99)
- Permissions status panel:
  - Microphone: ✓ Granted / ✗ Not Granted (with "Open System Settings" button)
  - Input Monitoring: ✓ Granted / ✗ Not Granted (with "Open System Settings" button)
- RAG settings (index path, re-index button) — may be hidden for v1
- Auto-update channel: Stable / Beta

### 5. Onboarding Window

A first-run wizard shown once on first launch. Can be re-triggered from Settings. Centered window, fixed size (~600×450).

**Step 1 — Welcome**
- App icon + "Welcome to RCLI"
- Brief tagline: "Your voice assistant, running entirely on your Mac. No cloud. No subscriptions."
- Three feature highlights with icons:
  - 🎤 Voice commands — control your Mac by speaking
  - ✏️ Dictation — speak text into any app
  - 🔒 Private — everything runs locally on your device
- "Get Started" button

**Step 2 — Download Models**
- "RCLI needs AI models to work. Choose one to download:"
- Three model cards (selectable):
  - Qwen3 0.6B — "Fast responses, 456 MB" — tagged "Recommended"
  - Qwen3.5 2B — "Smarter, 1.5 GB"
  - Qwen3.5 4B — "Most capable, 2.7 GB"
- Selected card has accent border
- "Download & Continue" button (shows progress during download)
- "Skip for now" text link (subtle)

**Step 3 — Permissions**
- "RCLI needs two permissions to work:"
- **Microphone** card:
  - Mic icon + "Microphone access"
  - "Needed to hear your voice commands and dictation"
  - "Grant Access" button → triggers system dialog
  - Shows ✓ after granted
- **Input Monitoring** card:
  - Keyboard icon + "Input Monitoring"
  - "Needed for the global keyboard shortcut (⌘J) to work anywhere"
  - "Grant Access" button → triggers system dialog
  - Shows ✓ after granted
- "Skip — I'll set this up later" text link
- "Continue" button (enabled even if permissions skipped)

**Step 4 — Hotkey**
- "Press your dictation hotkey"
- Large key recorder UI showing current combo (default ⌘J)
- "Click to change" instruction
- "You can change this anytime in Settings"
- "Done" button → dismisses onboarding, app is ready

**Step indicator:**
- Left sidebar or top bar showing 4 steps with progress (dots or numbered circles)
- Completed steps show checkmark
- Current step highlighted

**Design notes:**
- The onboarding should feel like macOS Setup Assistant — clean, spacious, one thing at a time
- No overwhelming text walls
- Every step has a clear single action
- Total time to complete: ~2 minutes (including model download)

### 6. Permission Banner

A non-modal banner shown at the top of the menu bar popover or panel when a required permission is missing.

- Yellow/orange accent
- Icon + brief message: "Microphone access needed for voice commands"
- "Grant Access" button (opens System Settings) or "Enable in Settings" link
- Dismissible but reappears on next open if still missing

### 7. Overlay (Existing — No Redesign Needed)

A floating translucent circle (~60×60px) that appears near the text cursor when dictation is active. Already built in Obj-C++ using NSVisualEffectView. Two states:
- **Recording**: Pulsing microphone icon (red/accent)
- **Transcribing**: Spinning progress indicator

This overlay is reused as-is. Mentioned here for completeness so the designer understands the full picture.

---

## Visual Direction

- **Native macOS** — not Electron-looking, not iOS-ported. Should feel like it belongs next to Finder and System Settings.
- **Minimal** — the app is mostly invisible. When it does appear, it should be clean and focused.
- **Dark mode first** — most power users and the voice-AI audience skew dark mode. Light mode must work but dark mode is the hero.
- **SF Symbols everywhere** — no custom icons except the app icon itself.
- **Accent color**: System blue default, but consider a branded accent (the waveform theme suggests something audio-related).

## App Icon

Needs design. Should convey: voice, AI, local/private, Mac-native. Ideas to explore:
- Waveform motif
- Microphone + brain/chip
- Abstract sound wave in a rounded rect
- Keep it simple — it lives in the menu bar at 22×22 and on the dock during onboarding at 128×128

---

## Reference Apps (for design feel)

- **Raycast** — menu bar app with popover, clean and fast
- **Whisper Transcription** — macOS voice-to-text, minimal UI
- **ChatGPT desktop app** — conversation panel style (but we're more minimal)
- **Cleanshot X** — menu bar utility with popover + settings, good permission handling
- **Apple Dictation** — the overlay behavior during dictation (our overlay is similar)
