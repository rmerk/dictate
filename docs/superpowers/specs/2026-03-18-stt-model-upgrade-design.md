# STT Model Upgrade Design

**Date:** 2026-03-18
**Status:** Draft v3

## Goals

Ship the STT upgrade for this branch with a reduced scope:

- keep `Zipformer` as the only supported streaming STT backend
- expand and improve offline STT model selection
- split API, CLI, TUI, and info surfaces into explicit streaming vs offline concepts
- preserve dictation behavior when offline STT is unavailable by hardening the existing Zipformer fallback

This branch does not implement Moonshine streaming selection or native Moonshine integration.

## Constraints

- English primary, multilingual nice-to-have
- Preserve existing model support for backward compatibility
- Prefer the lowest-risk integration path first
- Do not widen the runtime or dependency surface for unproven streaming backends in this branch
- Per-model size cap: 3 GB

## Supported Model Lineup In This Branch

| Slot | Model | Runtime | Size | Role |
|------|-------|---------|------|------|
| Streaming fixed | Zipformer 20M | sherpa-onnx (existing) | 50 MB | Only live/streaming STT backend in this branch |
| Offline bundled | Whisper base.en | sherpa-onnx (existing) | 140 MB | Existing default offline setup |
| Offline upgrade | Distil-Whisper large-v3.5 | sherpa-onnx | ~750 MB | Mid-tier offline upgrade |
| Offline premium | Parakeet TDT 1.1B | sherpa-onnx | ~1.2 GB | Best offline accuracy target |
| Offline existing | Parakeet TDT 0.6B | sherpa-onnx (existing) | 640 MB | Keep for existing users |

Default setup for this branch remains `Zipformer + Whisper base.en`, with optional offline upgrades layered on top.

## Deferred Streaming Follow-Up

Moonshine streaming is explicitly deferred. It may be revisited only after one of these is true:

1. `sherpa-onnx` exposes a validated streaming integration surface that fits this project cleanly.
2. A separate spike proves a simulated-streaming or native-runtime approach is worth the added ownership cost.

Until then, the code and UX in this branch must not imply that Moonshine is selectable or supported for streaming use.

## Current-State Reality Check

- `SttEngine` is directly coupled to sherpa-onnx online recognizer APIs today.
- `rcli_init()` and `rcli_init_stt_only()` both hardcode Zipformer model paths for streaming STT.
- `resolve_active_stt()` and `stt_model=` already exist for offline STT selection.
- The CLI currently collapses STT reporting into a mix of fixed streaming assumptions and offline-only selection.
- `Orchestrator` already relies on streaming STT as the fallback path when offline STT is unavailable in some flows, but dictation fallback is weaker than the file/stream fallback flow.

These facts mean the lowest-risk branch is:

- keep streaming fixed to Zipformer
- improve offline model coverage
- clarify surfaces that currently blur streaming and offline STT together
- strengthen the existing Zipformer fallback instead of replacing it

## Architecture

### Streaming STT

Streaming STT stays fixed to Zipformer in this branch.

That means:

- `rcli_init()` continues to initialize Zipformer streaming STT
- `rcli_init_stt_only()` continues to initialize Zipformer streaming STT because dictation may still need fallback decoding
- `Orchestrator` continues to treat streaming STT as the live mic path
- no new streaming model resolver or `streaming_model=` config key is introduced in this branch

The implementation work here is not backend selection. It is making the fixed streaming layer easier to reason about and reporting it clearly.

### Offline STT

Offline STT remains the main upgrade surface.

`OfflineSttEngine` already supports the relevant backend families:

- Distil-Whisper large-v3.5 fits `OfflineSttBackend::WHISPER`
- Parakeet TDT 1.1B fits `OfflineSttBackend::NEMO_TRANSDUCER`

This branch should focus on:

- adding offline registry entries
- keeping offline auto-detect and pinned selection behavior clear
- making setup/download flows aware of the expanded offline lineup

### Runtime And API State

Even though streaming stays fixed to Zipformer, the runtime should report streaming and offline STT separately.

The API cleanup should split three concerns that are currently easy to conflate:

- selected streaming STT model
- selected offline STT model
- last STT backend actually used for transcription

Target reporting shape:

- `rcli_get_selected_streaming_stt_model()` returns `zipformer` in this branch
- `rcli_get_selected_offline_stt_model()` returns the resolved offline model ID
- `rcli_get_last_stt_backend_used()` reports whether the last transcription used the configured offline path or the Zipformer fallback path

This keeps configuration state separate from runtime behavior and avoids overloading a narrow API such as `rcli_is_using_parakeet()`.

### CLI / TUI / Info UX

The user-facing surfaces should distinguish streaming and offline STT explicitly, even though streaming is fixed.

Target UX:

- one streaming STT section labeled as fixed to Zipformer in this branch
- one offline STT section showing the selected or auto-detected offline model
- info/reporting output that does not compress both concepts into one misleading sentence
- no copy that implies there is already a second streaming backend to choose from

The goal is clearer product surface area, not new streaming configuration.

## Data Flow

### Streaming (live TUI mode)

```text
Mic -> RingBuffer -> VAD -> ZipformerStt.feed_audio()
                           |
                           +-> process_tick()
                           |
                           +-> partial/final text -> Orchestrator -> LLM
```

This remains the current live pipeline shape.

### Offline (dictation / listen mode)

```text
Mic -> capture buffer -> stop -> OfflineSttEngine.transcribe(buffer)
```

Offline model selection changes, but the primary flow does not.

### Dictation Fallback

Today `stop_capture_and_transcribe()` falls back to streaming STT if offline STT is unavailable, but that fallback is weaker than the existing file/stream fallback flows. It currently does one reset, one feed, one `process_tick()`, and one `get_result()`.

This branch should harden that path by aligning it with the more robust Zipformer decode flow already used elsewhere:

- reset streaming STT
- feed captured audio
- feed trailing silence
- pump `process_tick()` in a bounded loop
- fetch the final result

The branch should preserve dictation functionality without making offline STT mandatory.

## Model Registry Changes

### Offline Registry

Add new offline entries to `SttModelDef` and keep the existing `resolve_active_stt()` pattern for offline selection.

Target additions:

- `distil-whisper-large-v3.5`
- `parakeet-tdt-1.1b`

Keep:

- `whisper-base`
- `parakeet-tdt`

Priority should prefer the intended higher-quality installed offline model while preserving current installs and fallback behavior.

### Streaming Registry

Streaming registry work in this branch should stay minimal.

Keep Zipformer represented accurately in the registry and reporting paths where needed, but do not add active Moonshine entries, `streaming_model=` persistence, or streaming auto-detect policy in this branch.

## Init-Time Behavior

Both init paths should continue to bring up Zipformer streaming STT and a separately resolved offline STT selection.

Target init logic:

```text
rcli_init / rcli_init_stt_only
  +-- Streaming: initialize Zipformer
  +-- Offline: resolve_active_stt()
```

Important note: `rcli_init_stt_only()` must still initialize Zipformer because dictation may fall back to streaming decode when offline STT is unavailable.

## Build System And Dependencies

No new streaming runtime or dependency family is part of this branch.

That means:

- no `deps/moonshine`
- no new top-level CMake toggles for alternate streaming runtimes
- no second ONNX Runtime owner
- no native-runtime coexistence work in this branch

Any dependency-upgrade or native-runtime exploration belongs to a later follow-up, not this implementation.

## Model Downloads And Setup

Target model policy for this branch:

- `scripts/download_models.sh` continues to download Zipformer + Whisper base.en by default
- Distil-Whisper large-v3.5 and Parakeet TDT 1.1B become optional offline upgrades
- setup and picker flows should describe Zipformer as the streaming default and the offline lineup separately

This preserves the current streaming installation behavior while still expanding offline choices.

## Error Handling And Fallbacks

- **Offline selection missing files:** surface a clear error and fall back according to existing offline resolver policy
- **Offline init failure:** log directly and keep Zipformer fallback available where existing flows already support it
- **Model download failure:** retry once, then surface a direct error; do not silently swap to a different model
- **Dictation offline unavailable:** use the hardened Zipformer fallback path rather than failing immediately

## Testing

### API / Runtime Reporting

- verify streaming and offline model reporting are separate
- verify `rcli_get_last_stt_backend_used()` reflects actual runtime behavior
- verify current Zipformer streaming init behavior remains intact

### Offline Regression

- feed known WAV files through each supported offline model and assert transcript quality by a tolerant metric rather than exact string equality
- ensure `resolve_active_stt()` continues to prefer the best installed offline model
- verify older installs still resolve cleanly

### Dictation And Fallback Coverage

- exercise `rcli_init_stt_only()` with offline STT present
- exercise `rcli_init_stt_only()` with offline STT unavailable
- verify the hardened Zipformer fallback still produces text in the offline-unavailable case

### CLI / TUI / Info Coverage

- verify streaming and offline STT are shown separately
- verify no surface implies selectable Moonshine streaming in this branch
- verify setup/download copy matches the actual supported lineup

## Migration And Rollback

### Existing Users

- do not remove Zipformer automatically
- do not change the default streaming bundle in this branch
- preserve existing offline selection semantics through `stt_model=...`
- do not break users who only have the old default models installed

### Rollback

No new streaming rollback mechanism is required in this branch because streaming remains Zipformer-only.

Offline rollback should remain the existing model-selection behavior:

- switch offline selection back through `rcli models`
- or clear the pinned offline model and fall back to auto-detect

## Decision Gate

Recommended implementation order:

1. Revise spec and plan language to remove in-branch Moonshine streaming work.
2. Split runtime and API reporting into streaming, offline, and last-used concepts.
3. Update CLI, TUI, and info surfaces to present streaming and offline STT separately.
4. Expand offline registry and setup/download flows.
5. Harden and test the existing Zipformer dictation fallback.
6. Revisit Moonshine only in a later dedicated spike or dependency-upgrade branch.

## Performance Targets

- **Streaming latency:** preserve current Zipformer live responsiveness
- **Offline accuracy:** new offline options should match or beat current Parakeet TDT 0.6B on the project corpus
- **Fallback reliability:** dictation should still return text when offline STT is unavailable via the hardened Zipformer path
