# STT Model Upgrade Design

**Date:** 2026-03-18
**Status:** Draft

## Goals

Upgrade the entire STT pipeline — both streaming (live TUI) and offline (dictation/listen mode) — to use the best available open-source models in 2026. Prioritize accuracy over latency over simplicity. Per-model size cap: 3 GB.

## Constraints

- English primary, multilingual nice-to-have
- Open to a second inference backend (Moonshine native C++) if it doesn't require massive refactors
- Must preserve existing model support for backward compatibility

## Model Lineup

| Slot | Model | Runtime | Size | Role |
|------|-------|---------|------|------|
| Streaming default | Moonshine v2 Small | Moonshine native C++ | ~150 MB | Live TUI mode |
| Streaming lightweight | Moonshine v2 Tiny | Moonshine native C++ | ~60 MB | Optional, low footprint |
| Streaming fallback | Zipformer 20M | sherpa-onnx (existing) | 50 MB | Downloadable fallback via `rcli models` |
| Offline bundled | Whisper base.en | sherpa-onnx (existing) | 140 MB | Ships with setup |
| Offline upgrade | Distil-Whisper large-v3.5 | sherpa-onnx | ~750 MB | Optional mid-tier |
| Offline premium | Parakeet TDT 1.1B | sherpa-onnx | ~1.2 GB | Optional, best accuracy |
| Offline existing | Parakeet TDT 0.6B | sherpa-onnx (existing) | 640 MB | Kept for existing users |

Default setup bundles: Moonshine v2 Small + Whisper base.en (~290 MB).

## Architecture

### Streaming STT — Two Concrete Classes (No Virtual Interface)

The current `SttEngine` class is tightly coupled to sherpa-onnx's `OnlineRecognizer`. Rather than introducing a virtual `IStreamingStt` interface (which adds vtable overhead on a hot path called thousands of times per second), we use two concrete classes:

- `SttEngine` — existing Zipformer/sherpa-onnx implementation, unchanged
- `MoonshineStt` — new class wrapping Moonshine's native C++ runtime

Both expose the same method signatures: `init()`, `feed_audio()`, `process_tick()`, `get_result()`, `has_result()`, `reset()`. No inheritance, no virtual dispatch.

**Namespace:** `MoonshineStt` goes in `namespace rastack` alongside the existing `SttEngine`. The `rastack`/`rcli` namespace split is pre-existing tech debt — unifying it is out of scope for this work.

**Orchestrator integration:** The orchestrator holds both as members with an enum guard:

```cpp
enum class StreamingSttBackend { ZIPFORMER, MOONSHINE };

// In Orchestrator:
SttEngine        stt_;                      // existing Zipformer
#if RCLI_ENABLE_MOONSHINE
MoonshineStt     moonshine_stt_;            // new — compiled out when disabled
#endif
StreamingSttBackend active_streaming_ = StreamingSttBackend::ZIPFORMER;
```

All existing `stt_.feed_audio()` / `stt_.process_tick()` / `stt_.get_result()` call sites get wrapped in a helper or guarded by `active_streaming_`. This is ~10 call sites in orchestrator.cpp. Chosen over `std::variant` (awkward visit syntax) and `unique_ptr` (unnecessary heap allocation for a member that lives for the process lifetime).

**Lazy init:** Only the selected streaming backend is initialized. If `active_streaming_ == MOONSHINE`, Zipformer is not loaded (and vice versa). Users who prefer Zipformer pay zero cost for Moonshine being compiled in.

**Buffering note:** Moonshine v2 uses sliding-window attention with a fixed window size (~3 seconds / ~48000 samples at 16kHz — confirm exact value from Moonshine docs during implementation). Unlike Zipformer which expects continuous small chunks (~10ms), `MoonshineStt` must handle chunk-by-chunk feeding internally — buffering up to the window size and running inference when it has enough. The orchestrator should not need to know about this difference.

### Offline STT — Registry Extension Only

`OfflineSttEngine` already supports Whisper and NeMo transducer backends via `OfflineSttBackend` enum. Adding Distil-Whisper and Parakeet TDT 1.1B requires only new registry entries — they use the same backends:

- Distil-Whisper large-v3.5 → `OfflineSttBackend::WHISPER`
- Parakeet TDT 1.1B → `OfflineSttBackend::NEMO_TRANSDUCER`

### Model Registry Changes

Add `runtime` field to `SttModelDef`:

```cpp
std::string runtime;  // "sherpa-onnx" or "moonshine"
```

Existing entries get `runtime: "sherpa-onnx"`. Moonshine entries get `runtime: "moonshine"`. Init code uses this field to select which streaming class to instantiate.

Moonshine models use single `.ort` files instead of encoder/decoder/joiner split. Add a `model_file` field to `SttModelDef` for single-file models (Moonshine). The existing `encoder_file`/`decoder_file`/`joiner_file` fields remain for sherpa-onnx models. `is_stt_installed()` checks `model_file` when non-empty, otherwise `encoder_file`.

Add `streaming_model` config key to `~/Library/RCLI/config` (alongside existing `stt_model`):

```
stt_model=parakeet-tdt        # offline model selection (existing)
streaming_model=moonshine-v2-small  # streaming model selection (new)
```

`resolve_active_streaming()` follows the same pattern as `resolve_active_stt()`: user preference > auto-detect (highest priority installed streaming model) > Zipformer fallback. Exposed in `rcli models` alongside offline model selection.

Lives in `stt_model_registry.h` (namespace `rcli`) alongside the existing offline helpers. Returns a model ID string that the orchestrator maps to `StreamingSttBackend` enum. Add `read_selected_streaming_id()` / `write_selected_streaming_id()` config helpers mirroring the existing `read_selected_stt_id()` / `write_selected_stt_id()`.

## Data Flow

### Streaming (live TUI mode)

```
Mic -> RingBuffer -> VAD (Silero) -> MoonshineStt.feed_audio()
                                          |
                                    process_tick() -> partial results -> Orchestrator
                                          |
                                    endpoint detected -> final text -> LLM
```

Same flow as current Zipformer path. Moonshine v2's sliding-window attention handles long utterances without accumulating latency.

### Offline (dictation / listen mode)

```
Mic -> capture buffer -> stop -> OfflineSttEngine.transcribe(buffer)
                                        |
                                 backend selection:
                                   Whisper / Distil-Whisper / Parakeet
```

No change to this flow.

### Init-time Selection

Both `rcli_init` and `rcli_init_stt_only` must be updated — today `rcli_init_stt_only` (used by the dictation daemon) hardcodes Zipformer paths. Both init paths share the same streaming selection logic:

```
rcli_init / rcli_init_stt_only
  +-- Streaming: resolve_active_streaming()
  |     +-- User preference (streaming_model config key)
  |     +-- Auto-detect (highest priority installed streaming model)
  |     +-- Fallback: Zipformer
  +-- Offline: resolve_active_stt() (existing logic, unchanged)
```

Note: `rcli_init_stt_only` initializes streaming STT even though dictation uses the offline path — the streaming engine is used as a fallback in `stop_capture_and_transcribe()` when no offline model is available.

## Build System & Dependencies

### Moonshine C++ Runtime

- Clone into `deps/moonshine` (same pattern as `deps/llama.cpp`, `deps/sherpa-onnx`)
- Add clone step to `scripts/setup.sh`
- `add_subdirectory(deps/moonshine)` in root CMakeLists.txt
- Link `moonshine` target to `rcli` target

### OnnxRuntime Strategy

This is the critical decision gate. Moonshine uses OnnxRuntime internally; sherpa-onnx bundles its own copy. Two copies in one process risks symbol conflicts.

**Spike (must be done first):**
1. Build Moonshine against sherpa-onnx's bundled OnnxRuntime headers and library
2. Load both a sherpa-onnx model and a Moonshine model in the same process
3. Verify no crashes or symbol conflicts

**If spike passes:** Proceed with `deps/moonshine` native integration.
**If spike fails:** Fall back to Moonshine-via-sherpa-onnx (recently added support). This eliminates the second runtime entirely — `MoonshineStt` becomes another sherpa-onnx backend and the `runtime` field, CMake gating, and separate dep become unnecessary. Simpler, but may sacrifice Moonshine-native optimizations.

### CMake Gating

```cmake
option(RCLI_ENABLE_MOONSHINE "Enable Moonshine v2 streaming STT" ON)
```

If OFF or Moonshine fails to build, streaming falls back to Zipformer-only. No hard dependency.

### Model Downloads

- `scripts/download_models.sh` updated to pull Moonshine v2 Small (replaces Zipformer in default setup)
- Zipformer no longer downloaded by default — available via `rcli models`
- Distil-Whisper, Parakeet 1.1B, Moonshine Tiny available via `rcli models`

## Error Handling & Fallbacks

- **Moonshine init failure:** Log warning, fall back to Zipformer if installed, otherwise error suggesting `rcli models` to download a streaming model
- **Model download failure:** Retry once, then surface error with URL for manual download. No silent fallback to a different model
- **ORT version mismatch:** Detected at CMake time, not runtime. Build fails with clear message pointing to `RCLI_ENABLE_MOONSHINE=OFF`
- **Missing model files:** Extend `is_stt_installed()` to check Moonshine `.ort` files the same way it checks encoder files

## Testing

### Unit Tests

- Feed known WAV files through each STT model and assert transcript accuracy using **WER threshold** (< 10% against reference transcript), not exact string matching — different models produce slightly different output
- Same test structure for both `MoonshineStt` and `SttEngine` (Zipformer) to verify they're interchangeable

### Offline Regression Corpus

- Small test corpus (3-5 WAV files with known reference transcripts) in `test/audio/`
- Runs against every installed offline model in the registry as part of `rcli_test`
- Catches regressions when adding new models or updating sherpa-onnx

### ORT Compatibility Test

- Concrete pass/fail test for the OnnxRuntime spike: load both a sherpa-onnx model and a Moonshine model in the same process, run inference on both, verify no crashes or symbol conflicts

### Benchmark

- Extend `rcli bench` to include Moonshine streaming and new offline models
- Compare latency and accuracy against current Zipformer/Whisper/Parakeet baselines

### Integration (Manual)

Smoke test checklist for `rcli listen` and `rcli dictate` with each model:
1. Start mode, record ~5 seconds of speech, verify transcript appears
2. Verify overlay states transition correctly (dictation mode)
3. Verify paste works (dictation mode)
4. Verify model switching via `rcli models` takes effect on next engine init

### Fallback

- Build with `RCLI_ENABLE_MOONSHINE=OFF`, verify Zipformer-only path works
- Remove Moonshine model files, verify graceful fallback with clear error message

## Migration & Rollback

**Existing users running `setup.sh` again:** Downloads Moonshine v2 Small alongside existing models. Does not remove Zipformer if already present. Streaming auto-detect picks Moonshine (higher priority) unless user has set `streaming_model=zipformer` in config.

**Rollback to Zipformer:** `rcli models` to select Zipformer as streaming model, or set `streaming_model=zipformer` in config. No rebuild required. Zipformer stays downloadable via `rcli models`.

**`rcli_is_using_parakeet()` API:** Deprecate in favor of a new `rcli_get_stt_backend_name()` that returns the active offline model name. The boolean is insufficient with 4 offline backends.

## Performance Targets

- **Streaming latency:** Partial results within 200ms of speech (Moonshine v2 Small targets ~148ms)
- **Offline accuracy:** New models must match or beat current Parakeet TDT 0.6B (~1.9% WER on clean audio)
- **Memory:** Moonshine v2 Small runtime footprint should not increase dictation daemon RSS by more than 150 MB over current Zipformer baseline
