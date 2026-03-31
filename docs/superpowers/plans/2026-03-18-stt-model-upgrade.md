# STT Model Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the reduced-scope STT upgrade by keeping Zipformer as the only streaming backend in this branch, expanding offline model support, clarifying streaming vs offline reporting surfaces, and hardening the existing dictation fallback.

**Architecture:** Preserve the current sherpa-onnx Zipformer streaming path instead of introducing streaming backend selection. Split runtime state into selected streaming model, selected offline model, and last backend used; present those concepts distinctly in the API and UI; then expand only the offline registry/setup flows and strengthen the current Zipformer dictation fallback path.

**Tech Stack:** C++17, sherpa-onnx C API, FTXUI CLI/TUI, shell-based model downloads, `rcli_test`, `rcli info`.

---

## File Structure

**Modify:**
- `docs/superpowers/specs/2026-03-18-stt-model-upgrade-design.md` - lock the reduced scope and remove current-branch Moonshine streaming work
- `docs/superpowers/plans/2026-03-18-stt-model-upgrade.md` - this execution plan
- `src/api/rcli_api.h` - split public STT reporting APIs and update doc blocks
- `src/api/rcli_api.cpp` - record separate streaming/offline selection state and last backend used
- `src/cli/model_pickers.h` - show streaming STT and offline STT separately
- `src/cli/tui_app.h` - rename or reorganize model-management and dashboard copy
- `src/cli/setup_cmds.h` - keep setup copy aligned with the actual supported model lineup
- `src/models/stt_model_registry.h` - expand offline model definitions while keeping Zipformer as the streaming default
- `src/pipeline/orchestrator.h` - add focused helper functions for streaming fallback flow if needed
- `src/pipeline/orchestrator.cpp` - harden the Zipformer fallback used when offline STT is unavailable
- `scripts/download_models.sh` - keep default downloads on Zipformer + Whisper base, add optional offline upgrades
- `src/test/test_pipeline.cpp` - add regression coverage for split reporting, offline selection, and Zipformer fallback

**Do not modify in this branch:**
- `deps/moonshine/`
- top-level CMake for new streaming runtimes
- any `streaming_model=` config rollout

The branch goal is a clearer and more robust Zipformer-plus-offline-upgrades story, not a new streaming backend.

---

### Task 1: Lock the reduced scope in docs before more implementation work

**Files:**
- Modify: `docs/superpowers/specs/2026-03-18-stt-model-upgrade-design.md`
- Modify: `docs/superpowers/plans/2026-03-18-stt-model-upgrade.md`

- [ ] **Step 1: Update the spec goals and supported lineup**

Rewrite the spec so it explicitly says:
- Zipformer is the only streaming backend in this branch
- offline model additions are in scope
- Moonshine streaming is deferred to a later spike or dependency-upgrade branch

- [ ] **Step 2: Remove in-branch Moonshine streaming claims**

Delete or rewrite:
- streaming model selection language
- `streaming_model=` rollout language
- native Moonshine implementation details presented as current-branch work

- [ ] **Step 3: Add explicit split-surface requirements**

Make the spec call out separate:
- streaming STT reporting
- offline STT reporting
- last-backend-used reporting
- CLI/TUI/info surfaces

- [ ] **Step 4: Rewrite this implementation plan to match**

Ensure every task below targets:
- offline upgrades
- split reporting and UX
- Zipformer fallback hardening

- [ ] **Step 5: Review both documents against the reduced-scope checklist**

Confirm no section still implies:
- Moonshine streaming is selectable now
- a new streaming runtime is landing in this branch
- the default download bundle changes away from Zipformer

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/specs/2026-03-18-stt-model-upgrade-design.md docs/superpowers/plans/2026-03-18-stt-model-upgrade.md
git commit -m "docs(stt): reduce scope to offline upgrades and zipformer fallback"
```

---

### Task 2: Split API and runtime STT state into streaming, offline, and last-used concepts

**Files:**
- Modify: `src/api/rcli_api.h`
- Modify: `src/api/rcli_api.cpp`
- Test: `src/test/test_pipeline.cpp`

- [ ] **Step 1: Add focused failing API/runtime tests**

Add assertions that verify the runtime can report:
- selected streaming STT model
- selected offline STT model
- last STT backend used

Run:

```bash
cd /Users/rchoi/Personal/rcli-dictate/build && ./rcli_test --api-only
```

Expected: new STT reporting assertions fail before implementation.

- [ ] **Step 2: Define the minimal runtime state**

Add well-named state fields in the API/runtime layer for:

```cpp
std::string selected_streaming_stt_model;
std::string selected_offline_stt_model;
std::string last_stt_backend_used;
```

Keep streaming fixed to `zipformer` in this branch instead of introducing streaming auto-detect.

- [ ] **Step 3: Factor helper functions in `src/api/rcli_api.cpp`**

Use small helpers rather than duplicating string assembly or selection logic. Target helpers such as:

```cpp
static std::string resolve_selected_streaming_stt_model();
static const rcli::SttModelDef* resolve_selected_offline_stt(...);
static void record_last_stt_backend_used(...);
```

- [ ] **Step 4: Update the public reporting API**

Replace narrow or ambiguous reporting with explicit APIs:

```cpp
const char* rcli_get_selected_streaming_stt_model(RCLIHandle handle);
const char* rcli_get_selected_offline_stt_model(RCLIHandle handle);
const char* rcli_get_last_stt_backend_used(RCLIHandle handle);
```

Update the doc blocks in `src/api/rcli_api.h` to describe the difference between configured selection and actual runtime usage.

- [ ] **Step 5: Keep init behavior honest**

Ensure:
- `rcli_init()` records `zipformer` as the selected streaming model
- `rcli_init_stt_only()` records the resolved offline model independently
- no code path suggests that streaming model selection is user-configurable in this branch

- [ ] **Step 6: Re-run API tests**

Run:

```bash
cd /Users/rchoi/Personal/rcli-dictate/build && ./rcli_test --api-only
```

Expected: split reporting tests pass.

- [ ] **Step 7: Commit**

```bash
git add src/api/rcli_api.h src/api/rcli_api.cpp src/test/test_pipeline.cpp
git commit -m "refactor(api): split streaming and offline stt reporting"
```

---

### Task 3: Update CLI, TUI, and info surfaces to distinguish fixed streaming Zipformer from selectable offline STT

**Files:**
- Modify: `src/cli/model_pickers.h`
- Modify: `src/cli/tui_app.h`
- Modify: `src/api/rcli_api.cpp`
- Test: `src/test/test_pipeline.cpp`

- [ ] **Step 1: Capture the current incorrect UX**

Before editing, note where the product surface is misleading:
- STT copy collapses streaming and offline concepts together
- streaming Zipformer can read as an implementation detail instead of a surfaced fixed mode
- offline selection UI does not clearly indicate that it only affects offline STT

- [ ] **Step 2: Split the picker into streaming and offline sections**

Update `src/cli/model_pickers.h` so `rcli models stt` shows:
- `Streaming STT`
- `Offline STT`

The streaming section should say Zipformer is fixed in this branch. The offline section should show the selected or auto-detected offline model.

- [ ] **Step 3: Update dashboard and info copy**

Replace hardcoded summary strings with output derived from the split runtime state, for example:
- streaming: `Zipformer (fixed in this branch)`
- offline: resolved model name
- last backend used: offline model vs Zipformer fallback where appropriate

- [ ] **Step 4: Remove implied unsupported behavior**

Delete copy that implies:
- there is a second streaming STT backend available now
- users can switch streaming backends in this branch
- setup already installs a new streaming default

- [ ] **Step 5: Smoke test the surfaced output**

Run:

```bash
cd /Users/rchoi/Personal/rcli-dictate/build && ./rcli models
cd /Users/rchoi/Personal/rcli-dictate/build && ./rcli info
```

Expected:
- streaming and offline STT appear separately
- streaming is clearly fixed to Zipformer
- offline selection appears separately
- no stale Moonshine-streaming wording remains

- [ ] **Step 6: Commit**

```bash
git add src/cli/model_pickers.h src/cli/tui_app.h src/api/rcli_api.cpp
git commit -m "feat(cli): split streaming and offline stt surfaces"
```

---

### Task 4: Expand offline registry and setup/download flows without changing the streaming default bundle

**Files:**
- Modify: `src/models/stt_model_registry.h`
- Modify: `scripts/download_models.sh`
- Modify: `src/cli/setup_cmds.h`
- Test: `src/test/test_pipeline.cpp`

- [ ] **Step 1: Add failing registry/setup tests or notes**

Verify the current behavior still assumes only the older offline lineup and does not clearly distinguish optional offline upgrades.

- [ ] **Step 2: Register the offline upgrade models**

Add entries for:
- `distil-whisper-large-v3.5`
- `parakeet-tdt-1.1b`

Keep:
- `whisper-base`
- `parakeet-tdt`
- `zipformer`

Do not add active Moonshine streaming entries in this branch.

- [ ] **Step 3: Keep offline resolution focused**

Preserve the existing `resolve_active_stt()` model:
- pinned offline selection if configured
- otherwise best installed offline model
- otherwise current safe fallback behavior

Avoid adding a parallel `resolve_active_streaming()` path in this branch.

- [ ] **Step 4: Update setup and download copy**

Keep the default download bundle on:
- `zipformer`
- `whisper-base`

Add optional offline-upgrade download and setup messaging for:
- Distil-Whisper large-v3.5
- Parakeet TDT 1.1B

- [ ] **Step 5: Verify install detection and user messaging**

Run:

```bash
bash /Users/rchoi/Personal/rcli-dictate/scripts/download_models.sh /tmp/rcli-stt-plan-check
cd /Users/rchoi/Personal/rcli-dictate/build && ./rcli models stt
```

Expected:
- default bundle still includes Zipformer
- optional offline upgrades are visible when installed
- setup text matches the actual supported lineup

- [ ] **Step 6: Clean up the temporary download directory**

Run:

```bash
rm -rf /tmp/rcli-stt-plan-check
```

- [ ] **Step 7: Commit**

```bash
git add src/models/stt_model_registry.h scripts/download_models.sh src/cli/setup_cmds.h src/test/test_pipeline.cpp
git commit -m "feat(stt): add offline upgrades without changing streaming defaults"
```

---

### Task 5: Harden the Zipformer dictation fallback and record actual backend usage

**Files:**
- Modify: `src/pipeline/orchestrator.h`
- Modify: `src/pipeline/orchestrator.cpp`
- Modify: `src/api/rcli_api.cpp`
- Test: `src/test/test_pipeline.cpp`

- [ ] **Step 1: Add a failing dictation fallback test**

Exercise `rcli_init_stt_only()` with offline STT unavailable and verify dictation still yields text through the Zipformer fallback path.

Run:

```bash
cd /Users/rchoi/Personal/rcli-dictate/build && ./rcli_test --stt-only
```

Expected: fallback-focused test fails with the current one-shot decode behavior.

- [ ] **Step 2: Extract a well-named helper for the fallback decode flow**

Move the fallback logic into a focused helper rather than leaving it inline. Target a name such as:

```cpp
rastack::TextSegment decode_with_zipformer_fallback(
    const std::vector<float>& audio_buf);
```

If the existing file structure prefers class methods, keep the same intent: one well-named function owns the fallback flow.

- [ ] **Step 3: Replace the weak one-tick dictation fallback**

Use the robust multi-step flow:
- reset Zipformer streaming STT
- feed captured audio
- feed trailing silence
- pump `process_tick()` in a bounded loop
- return the final decoded result

- [ ] **Step 4: Record the backend actually used**

When transcription completes, set `last_stt_backend_used` to either:
- the selected offline model/backend
- `zipformer-fallback`

Make runtime reporting reflect behavior, not just selection state.

- [ ] **Step 5: Re-run fallback tests**

Run:

```bash
cd /Users/rchoi/Personal/rcli-dictate/build && ./rcli_test --stt-only
```

Expected: dictation fallback and last-used-backend assertions pass.

- [ ] **Step 6: Commit**

```bash
git add src/pipeline/orchestrator.h src/pipeline/orchestrator.cpp src/api/rcli_api.cpp src/test/test_pipeline.cpp
git commit -m "fix(dictate): harden zipformer fallback reporting"
```

---

### Task 6: Verify the reduced-scope branch end-to-end

**Files:**
- Modify: `src/test/test_pipeline.cpp`
- Modify: `docs/superpowers/specs/2026-03-18-stt-model-upgrade-design.md` if verification reveals stale claims
- Modify: `docs/superpowers/plans/2026-03-18-stt-model-upgrade.md` if verification reveals stale steps

- [ ] **Step 1: Re-read the reduced-scope checklist**

Confirm the implementation now matches all six branch requirements:
- revised spec
- rewritten plan
- split API/runtime state
- split CLI/TUI/info surfaces
- offline-only registry/setup expansion
- hardened Zipformer fallback

- [ ] **Step 2: Run the targeted verification suite**

Run:

```bash
cd /Users/rchoi/Personal/rcli-dictate/build && ./rcli_test --api-only
cd /Users/rchoi/Personal/rcli-dictate/build && ./rcli_test --stt-only
cd /Users/rchoi/Personal/rcli-dictate/build && ./rcli info
```

Expected:
- split STT reporting passes
- fallback coverage passes
- info output reflects separate streaming and offline concepts

- [ ] **Step 3: Check for stale product language**

Search the changed surfaces and confirm there is no user-facing wording that still implies:
- selectable Moonshine streaming
- a changed streaming default bundle
- unfinished fallback semantics

- [ ] **Step 4: Fix any remaining stale docs or copy**

If verification finds drift, update the relevant doc or UI copy before claiming the branch is aligned.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/specs/2026-03-18-stt-model-upgrade-design.md docs/superpowers/plans/2026-03-18-stt-model-upgrade.md src/test/test_pipeline.cpp src/api/rcli_api.cpp src/cli/model_pickers.h src/cli/tui_app.h src/models/stt_model_registry.h src/pipeline/orchestrator.cpp scripts/download_models.sh src/cli/setup_cmds.h
git commit -m "test(stt): verify reduced-scope stt upgrade"
```

---

## Notes

- Keep new logic in well-named helper functions instead of duplicating state assembly or fallback handling.
- Update doc blocks whenever a public function changes.
- Preserve backward compatibility for existing installs and config files.
- `stt_model=` remains the offline selection key in this branch.
- Do not add `streaming_model=` rollout work here.
- Do not introduce Moonshine runtime code, dependency wiring, or user-facing selection copy in this branch.

## Deferred Follow-Up

Only consider Moonshine streaming in a later dedicated branch after validating an actual dependency/runtime path. That follow-up should start from a fresh spec and should not be mixed into this reduced-scope branch.
