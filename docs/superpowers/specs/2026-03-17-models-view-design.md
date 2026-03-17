# Models View Redesign — Design Spec

**Date:** 2026-03-17
**Status:** Draft
**Scope:** Robin macOS app — Settings > Models tab

## Problem

The current Models tab is empty because it depends on `rcli_list_available_models()` from the C API, which isn't connected. Even if it were, the view is a flat list with no guidance — it doesn't tell users what to download or why.

## Goals

1. Show RCLI's full model catalog from a hardcoded Swift definition (no C API dependency).
2. Guide users toward the recommended base setup (~1 GB) with "Recommended" badges.
3. Enable download, activate, and delete for each model.

## Non-Goals

- VLM models (not part of the core voice pipeline; add later if Robin gets vision features).
- MetalRT-specific model variants (engine selection is an Advanced setting, not a model choice).
- Fetching the catalog from a remote manifest (premature; hardcode for now).
- Silero VAD and Snowflake embeddings (infrastructure, not user choices — one option each, downloaded during setup).

## Model Catalog

Hardcoded in Swift as `ModelCatalog.all`. Data sourced from the C++ registries (`src/models/model_registry.h`, `stt_model_registry.h`, `tts_model_registry.h`). Download URLs copied directly from C++ registry `url` / `download_url` fields. **All `name` fields must match the C++ registry `name` field exactly** — active model matching depends on this.

### LLM Models

Single `.gguf` files. Downloaded directly to `~/Library/RCLI/models/`.

| ID | Name | Size | Filename | Description | Recommended |
|----|------|------|----------|-------------|-------------|
| lfm2-1.2b | Liquid LFM2 1.2B Tool | 731 MB | lfm2-1.2b-tool-q4_k_m.gguf | Default, excellent tool calling | Yes |
| lfm2-350m | Liquid LFM2 350M | 219 MB | LFM2-350M-Q4_K_M.gguf | Ultra-fast, basic tool calling | No |
| lfm2.5-1.2b | Liquid LFM2.5 1.2B Instruct | 731 MB | LFM2.5-1.2B-Instruct-Q4_K_M.gguf | Newer LFM, good tool calling | No |
| lfm2-2.6b | Liquid LFM2 2.6B | 1.48 GB | LFM2-2.6B-Q4_K_M.gguf | Larger LFM, good tool calling | No |
| qwen3-0.6b | Qwen3 0.6B | 456 MB | qwen3-0.6b-q4_k_m.gguf | Fast, basic tool calling | No |
| qwen3.5-0.8b | Qwen3.5 0.8B | 600 MB | qwen3.5-0.8b-q4_k_m.gguf | Compact Qwen, basic tool calling | No |
| qwen3.5-2b | Qwen3.5 2B | 1.2 GB | qwen3.5-2b-q4_k_m.gguf | Balanced Qwen, good tool calling | No |
| qwen3-4b | Qwen3 4B | 2.5 GB | qwen3-4b-q4_k_m.gguf | Large Qwen, good tool calling | No |
| qwen3.5-4b | Qwen3.5 4B | 2.7 GB | qwen3.5-4b-q4_k_m.gguf | Smartest, excellent tool calling | Yes |
| llama3.2-3b | Llama 3.2 3B Instruct | 1.8 GB | llama-3.2-3b-instruct-q4_k_m.gguf | Meta Llama, good tool calling | No |

### STT Models

`.tar.bz2` archives that extract to directories. Archive directory name differs from engine directory name — must rename after extraction.

| ID | Name | Size | Directory | Archive Dir | Description | Recommended |
|----|------|------|-----------|-------------|-------------|-------------|
| whisper-base | Whisper base.en | 140 MB | whisper-base.en/ | sherpa-onnx-whisper-base.en | Offline transcription, ~5% WER | Yes |
| parakeet-tdt | Parakeet TDT 0.6B v3 | 640 MB | parakeet-tdt/ | sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8 | Best accuracy, ~1.9% WER | Yes |

Note: Zipformer (streaming, 50 MB) is always active for live mic input. It's infrastructure — not shown as a switchable model.

### TTS Models

`.tar.bz2` archives that extract to directories. Some require `espeak-ng-data/` (Piper voices). Archive directory name differs from engine directory name — must rename after extraction.

| ID | Name | Size | Directory | Archive Dir | Description | Recommended |
|----|------|------|-----------|-------------|-------------|-------------|
| piper-lessac | Piper Lessac (English) | 60 MB | piper-voice/ | vits-piper-en_US-lessac-medium | Default English voice | Yes |
| piper-amy | Piper Amy (English) | 60 MB | piper-amy/ | vits-piper-en_US-amy-medium | Alternative English voice | No |
| kitten-nano | KittenTTS Nano (English) | 90 MB | kitten-nano-en-v0_1-fp16/ | kitten-nano-en-v0_1-fp16 | 8 voices, great quality | No |
| matcha-ljspeech | Matcha LJSpeech (English) | 100 MB | matcha-icefall-en_US-ljspeech/ | matcha-icefall-en_US-ljspeech | Great quality | No |
| kokoro-en | Kokoro English v0.19 | 310 MB | kokoro-en-v0_19/ | kokoro-en-v0_19 | 11 voices, excellent quality | Yes |
| kokoro-multi | Kokoro Multi-lang v1.1 | 500 MB | kokoro-multi-lang-v1_1/ | kokoro-multi-lang-v1_1 | 103 voices, Chinese + English | No |

## UI Design

### Layout

The view has three sections grouped by role: **LLM**, **Speech-to-Text**, **Text-to-Speech**. Each section is a `Section` inside a `List`. Recommended models sort to the top of their section.

### Model Row

Each row displays:

```
┌──────────────────────────────────────────────────────┐
│  Liquid LFM2 1.2B Tool     Recommended      Active   │
│  731 MB · Excellent tool calling             ✓ 🗑     │
└──────────────────────────────────────────────────────┘
```

**Left side:**
- Model name (`.body` font, bold)
- Size + description on second line (`.caption`, secondary color)

**Right side — state-dependent:**

| State | Display |
|-------|---------|
| Bundled, not downloaded | No download button (bundled models installed by `rcli setup`) |
| Not downloaded | `Download` button (`.borderedProminent`, `.controlSize(.small)`) |
| Downloading | `ProgressView` (linear, determinate) + `Cancel` button (x icon) |
| Download/extraction failed | Error text (`.caption`, red) + `Retry` button |
| Downloaded, inactive | `Activate` button + trash icon button |
| Downloaded, active | Green "Active" badge + trash icon (disabled) |

**Recommended badge:** Small capsule with "Recommended" text, green background (`.green.opacity(0.2)`), green text — same style as the onboarding `ModelCard` tag.

### Disk Usage Footer

Below the list, a footer shows total disk usage of downloaded models:

```
Disk Usage:  1.2 GB
```

Uses `.caption` font, secondary color. Sums `sizeBytes` of all catalog entries where the model is detected as downloaded.

### Empty State

If no models are downloaded, show a centered message:

```
No models downloaded yet.
Download recommended models to get started.
```

## Data Model

### `ModelCatalogEntry` (new struct)

```swift
struct ModelCatalogEntry: Identifiable, Equatable {
    let id: String              // e.g. "lfm2-1.2b" — matches C++ registry ID
    let name: String            // e.g. "Liquid LFM2 1.2B Tool" — matches C++ registry name EXACTLY
    let sizeBytes: Int64        // e.g. 731_000_000
    let type: ModelType         // .llm, .stt, .tts
    let description: String     // e.g. "Default, excellent tool calling"
    let source: ModelSource     // .bundled or .remote(URL)
    let localPath: String       // Filename for LLM (e.g. "lfm2-1.2b-tool-q4_k_m.gguf")
                                // or directory name for STT/TTS (e.g. "kokoro-en-v0_19")
    let archiveDirName: String? // For archives where extracted dir != localPath
                                // e.g. "sherpa-onnx-whisper-base.en" extracts, then renamed to "whisper-base.en"
                                // nil when archive dir == localPath (e.g. kokoro-en-v0_19)
    let isRecommended: Bool

    /// Derived from type — LLMs are single .gguf files, STT/TTS are .tar.bz2 archives
    var isArchive: Bool { type == .stt || type == .tts }
}

enum ModelSource: Equatable {
    case bundled            // Installed by rcli setup (whisper-base, piper-lessac)
    case remote(URL)        // Downloaded from HuggingFace/GitHub
}
```

Models with `.bundled` source (whisper-base, piper-lessac) are installed by `rcli setup` / `download_models.sh`. Their rows never show a "Download" button — only status (Active/Downloaded) and delete/activate controls.

`ModelCatalogEntry` supersedes `ModelInfo` for the Models settings tab. `ModelInfo` remains for the `listAvailableModels()` C API codepath but is not used by this view.

### `ModelType` — extract to top-level enum

```swift
enum ModelType: String, Sendable {
    case llm, tts, stt

    var displayName: String {
        switch self {
        case .llm: return "LLM"
        case .stt: return "Speech-to-Text"
        case .tts: return "Text-to-Speech"
        }
    }
}
```

Remove nested `ModelInfo.ModelType` and update `ModelInfo.type` to reference the new top-level `ModelType`.

### `ModelCatalog` (new enum with static data)

```swift
enum ModelCatalog {
    static let all: [ModelCatalogEntry] = [ /* hardcoded entries */ ]

    static func models(ofType type: ModelType) -> [ModelCatalogEntry] {
        all.filter { $0.type == type }
            .sorted { ($0.isRecommended ? 0 : 1) < ($1.isRecommended ? 0 : 1) }
    }
}
```

Add a DEBUG assertion for ID and localPath uniqueness:
```swift
#if DEBUG
static let _validateUniqueness: Void = {
    assert(Set(all.map(\.id)).count == all.count, "Duplicate model IDs in catalog")
    assert(Set(all.map(\.localPath)).count == all.count, "Duplicate localPaths in catalog")
}()
#endif
```

### Download state detection

The view checks download state in this order:
1. `downloadService.activeDownloads[model.id]` — is it downloading? Check `.failed` for error state.
2. `downloadService.completedDownloads.contains(model.id)` — just finished this session?
3. File/directory existence on disk:
   - LLM: `FileManager.default.fileExists(atPath: modelsDir/model.localPath)`
   - STT/TTS: `FileManager.default.fileExists(atPath: modelsDir/model.localPath)` (checks directory exists)

### Active model matching

Match catalog entries to the engine's active model using **exact string equality**, not substring matching. Add computed properties to `EngineService`:

```swift
var activeModelId: String? {
    ModelCatalog.all.first { $0.name == activeModel }?.id
}
var activeSTTModelId: String? {
    ModelCatalog.all.first { $0.name == activeSTTModel }?.id
}
var activeTTSModelId: String? {
    ModelCatalog.all.first { $0.name == activeTTSModel }?.id
}
```

The view compares `entry.id == engine.activeModelId`. Exact equality works because catalog `name` fields match C++ registry names exactly. If no match is found (e.g., a model loaded outside the catalog), no model shows as "Active" — this is correct behavior.

## Interactions

### Download

**Pre-check:** Before starting, verify available disk space via `FileManager.default.attributesOfFileSystem(forPath:)[.systemFreeSize]`. If available space < model `sizeBytes` * 2 (for archives) or * 1.1 (for GGUF), show an alert: "Not enough disk space. {needed} required, {available} available."

Tap "Download" → calls `downloadService.download(modelId:name:url:destinationFilename:)`. The `destinationFilename` parameter is the catalog entry's `localPath` — the download service must use this as the final filename, **not** `suggestedFilename` from the server response.

Row transitions to progress state. On completion:
- **LLM (.gguf):** File is moved to `~/Library/RCLI/models/{localPath}`. Verify file size is within 10% of expected `sizeBytes`; if not, delete and show error.
- **STT/TTS (.tar.bz2):** See "Archive Extraction" below.

### Archive Extraction

After downloading a `.tar.bz2` archive:

1. Run `/usr/bin/tar xjf {archive} -C ~/Library/RCLI/models/` via `Process`.
2. Check `Process.terminationStatus == 0`. If non-zero, delete partial extraction directory and show error.
3. If `archiveDirName` differs from `localPath`: rename extracted `archiveDirName/` to `localPath/`.
4. Verify the extracted directory exists and is non-empty.
5. **Only then** delete the `.tar.bz2` archive file.
6. On any failure, clean up partial files/directories and show error with "Retry" button.

### Activate

**LLM:** Tap "Activate" → calls `engine.switchModel(id)` (existing, calls `rcli_switch_llm`). **Also writes `model={id}` to config file** so the selection persists across restarts.

**STT/TTS:** No runtime switch C API exists. Tap "Activate" → writes the model ID to `~/Library/RCLI/config` and sets `engine.activeSTTModel` / `engine.activeTTSModel` on the service. The C++ engine reads this config on next startup. Show a subtle note: "Takes effect on next launch" beneath the Active badge for STT/TTS models.

**Config file format** (`~/Library/RCLI/config`) is key=value, one per line:
```
model=lfm2-1.2b
stt_model=whisper-base
tts_model=piper-lessac
```

Config write implementation:
1. Read file contents (create if doesn't exist).
2. Replace existing key line if found, otherwise append.
3. Write back using `String.write(to:atomically:encoding:)` with `atomically: true`.
4. If write fails, do NOT update `engine.activeModel` / `activeSTTModel` / `activeTTSModel` — keep UI in sync with reality. Show error alert.

### Delete

Tap trash icon → confirmation alert ("Delete {name}? This will free {size}."):
- **LLM:** Removes single file `~/Library/RCLI/models/{localPath}`.
- **STT/TTS:** Removes entire directory `~/Library/RCLI/models/{localPath}/` recursively.

Trash icon is disabled when: (a) the model is active, or (b) the model has an active download/extraction in progress.

The delete guard is enforced at the service layer too — `deleteModel()` must verify the model is not active before removing files, regardless of what the UI shows.

### Cancel Download

Tap cancel (x) during download → calls `downloadService.cancelDownload(modelId:)`. Row returns to "Download" button state. The cancellation is handled via the `URLSessionDelegate` (`didCompleteWithError` with `NSURLErrorCancelled`) — do NOT resume the continuation in `cancelDownload()` directly to avoid double-resume crashes.

### Download Failure

If download or extraction fails (network error, disk full, corrupt archive), row shows error message in red `.caption` text + "Retry" button. Tapping Retry re-initiates the download.

## File Changes

| File | Change |
|------|--------|
| `State/Types.swift` | Extract `ModelType` to top-level enum with `displayName` (remove nested `ModelInfo.ModelType`, update `ModelInfo`); add `ModelCatalogEntry` struct; add `ModelSource` enum |
| **New:** `State/ModelCatalog.swift` | Hardcoded model catalog with all 18 entries + download URLs + archive dir names |
| `Views/Settings/ModelsSettingsView.swift` | Rewrite: use `ModelCatalog`, wire up download/activate/delete, add error/extraction states |
| `Services/ModelDownloadService.swift` | Accept `destinationFilename` param (use instead of `suggestedFilename`); add `extractArchive(at:to:renameTo:)` with error handling; add `deleteModel(path:isDirectory:)`; fix cancel race (delegate-only continuation resume) |
| `Services/EngineService+Models.swift` | Add `activeModelId` / `activeSTTModelId` / `activeTTSModelId` computed properties; add `switchSTTModel(_:)` and `switchTTSModel(_:)` (config write + property update); persist LLM selection to config after `switchModel()` |
| `RobinApp.swift` / `AppDelegate` | Move `ModelDownloadService` from `@State` in `OnboardingView` to `AppDelegate`; inject via `.environment()` |
| `Views/OnboardingView.swift` | Remove `@State private var downloadService`; consume from environment instead |

## Testing

### Manual Tests

- Build and run in Xcode. Verify all 18 models appear in correct sections.
- Recommended models sort to top of each section.
- Download an LLM model → verify progress bar, completion, file on disk with correct filename.
- Download a TTS model → verify archive extraction, directory renamed to expected name on disk.
- Activate a downloaded LLM → verify badge switches immediately and persists after restart.
- Activate a downloaded STT/TTS → verify "Takes effect on next launch" note.
- Delete a non-active model → verify file/directory removed, row returns to download state.
- Cancel an in-progress download → verify row returns to Download button, can re-download.
- Disconnect network mid-download → verify error text + Retry button.
- Verify disk usage footer updates after download/delete.
- Bundled models (whisper-base, piper-lessac) show no Download button.

### Automated Tests (in `RobinTests`)

| Test | What it validates |
|------|-------------------|
| `ModelCatalog` unique IDs | No duplicate `id` values |
| `ModelCatalog` unique `localPath` | No two models write to same location |
| `ModelCatalog` URL presence | All non-bundled models have `.remote(URL)` source |
| `ModelCatalog` archive consistency | All `.stt`/`.tts` entries have `isArchive == true` (derived) |
| `models(ofType:)` sorting | Recommended models appear before non-recommended |
| `activeModelId` exact matching | "Liquid LFM2 1.2B Tool" matches `lfm2-1.2b`, NOT `lfm2.5-1.2b` |
| `activeModelId` nil for unknown | Unknown model name returns `nil` |
| Config file round-trip | Write key, read back, verify; replace existing key, verify others preserved |
| Config file creation | Write to non-existent file creates it |
