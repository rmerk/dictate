# RCLI macOS App — Plan 2: Services

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the Swift service layer so the app can perform hotkey-triggered dictation end-to-end: press ⌘J → overlay appears → speak → transcribed text pasted into the active app.

**Architecture:** EngineProviding protocol defines the contract. EngineService wraps the C API with AsyncStream-based callbacks, proper threading, and error handling. HotkeyService, OverlayService, and PermissionService handle system integration. All services are `@MainActor @Observable`.

**Tech Stack:** Swift 6, SwiftUI (macOS 14+), C interop via CRCLIEngine module, CGEventTap, AXIsProcessTrusted

**Spec:** `docs/superpowers/specs/2026-03-16-rcli-macos-app-design.md`

**Depends on:** Plan 1 (Foundation) — xcframework built, Xcode project scaffold working

---

## Chunk 1: Types & Protocol

### Task 1: Define shared types

**Files:**
- Create: `app/RCLI/State/Types.swift`

- [ ] **Step 1: Create types file**

```swift
import Foundation

// Pipeline state matching C API enum values
enum PipelineState: Int, Sendable {
    case idle = 0
    case listening = 1
    case processing = 2
    case speaking = 3
    case interrupted = 4
}

// App lifecycle (independent of pipeline)
enum AppLifecycleState: Sendable {
    case loading
    case ready
    case error(String)
}

// Callback event types
struct TranscriptEvent: Sendable {
    let text: String
    let isFinal: Bool
}

struct ToolTraceEvent: Sendable {
    let event: String    // "detected" or "result"
    let toolName: String
    let data: String
    let success: Bool
}

// Model info (from rcli_list_available_models JSON)
struct ModelInfo: Identifiable, Sendable {
    let id: String
    let name: String
    let sizeBytes: Int64
    let type: ModelType
    let isDownloaded: Bool

    enum ModelType: String, Sendable {
        case llm, tts, stt
    }
}

// Action info (from rcli_action_list JSON)
struct ActionInfo: Identifiable, Sendable {
    let id: String
    let name: String
    let description: String
    let category: String
    let isEnabled: Bool
}

// Permission types
enum Permission: String, Sendable {
    case microphone
    case accessibility
}

// Errors
enum RCLIError: LocalizedError, Sendable {
    case initFailed(String)
    case modelNotFound(String)
    case modelLoadFailed(String)
    case permissionDenied(Permission)
    case engineNotReady
    case commandFailed(String)
    case transcriptionFailed
    case ragIngestFailed(String)
    case speakFailed

    var errorDescription: String? {
        switch self {
        case .initFailed(let msg): return "Engine init failed: \(msg)"
        case .modelNotFound(let id): return "Model not found: \(id)"
        case .modelLoadFailed(let id): return "Failed to load model: \(id)"
        case .permissionDenied(let p): return "\(p.rawValue) permission denied"
        case .engineNotReady: return "Engine not initialized"
        case .commandFailed(let msg): return "Command failed: \(msg)"
        case .transcriptionFailed: return "Transcription failed"
        case .ragIngestFailed(let msg): return "RAG ingest failed: \(msg)"
        case .speakFailed: return "TTS playback failed"
        }
    }
}
```

- [ ] **Step 2: Remove old AppState.swift types**

Delete the `PipelineState` and `AppLifecycleState` enums from `app/RCLI/State/AppState.swift` (created in Plan 1). That file can be deleted entirely — all types now live in `Types.swift`.

- [ ] **Step 3: Build to verify**

Run: `xcodebuild -project app/RCLI.xcodeproj -scheme RCLI build 2>&1 | tail -5`

Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add app/RCLI/State/Types.swift
git rm app/RCLI/State/AppState.swift  # if it existed
git commit -m "feat(app): add shared types, error enum, and callback event structs"
```

### Task 2: Define EngineProviding protocol

**Files:**
- Create: `app/RCLI/Services/EngineProviding.swift`

- [ ] **Step 1: Create protocol file**

```swift
import Foundation

@MainActor
protocol EngineProviding: Observable {
    // — Observable State —
    var pipelineState: PipelineState { get }
    var transcript: String { get }
    var isTranscriptFinal: Bool { get }
    var lastResponse: String { get }
    var audioLevel: Float { get }
    var isReady: Bool { get }
    var lifecycleState: AppLifecycleState { get }

    // — Event Streams —
    var transcriptStream: AsyncStream<TranscriptEvent> { get }
    var stateStream: AsyncStream<PipelineState> { get }
    var toolTraceStream: AsyncStream<ToolTraceEvent> { get }
    var responseStream: AsyncStream<String> { get }

    // — Lifecycle —
    func initialize(modelsDir: String, gpuLayers: Int) async throws
    func initializeSTTOnly(modelsDir: String, gpuLayers: Int) async throws
    func shutdown()

    // — Voice Pipeline —
    func startListening()
    func stopListening()
    func processAndSpeak(_ text: String) async throws -> String
    func stopProcessing()

    // — Push-to-Talk —
    func startCapture()
    func stopAndTranscribe() async throws -> String

    // — Text Commands —
    func processCommand(_ text: String) async throws -> String

    // — TTS —
    func speak(_ text: String) async throws
    func stopSpeaking()
    var isSpeaking: Bool { get }

    // — Models —
    func switchModel(_ id: String) async throws
    func listAvailableModels() async throws -> [ModelInfo]
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
    func getInfo() async -> String
    func getContextInfo() async -> (promptTokens: Int, contextSize: Int)
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project app/RCLI.xcodeproj -scheme RCLI build 2>&1 | tail -5`

Expected: Build succeeds (protocol is just a definition, nothing conforms yet).

- [ ] **Step 3: Commit**

```bash
git add app/RCLI/Services/EngineProviding.swift
git commit -m "feat(app): add EngineProviding protocol — the v1→v2 XPC seam"
```

## Chunk 2: EngineService Core

### Task 3: EngineService — lifecycle and callback wiring

**Files:**
- Rewrite: `app/RCLI/Services/EngineService.swift`

This replaces the minimal EngineService from Plan 1 with the full implementation. Start with lifecycle (create, init, destroy) and callback registration via AsyncStream.

- [ ] **Step 1: Rewrite EngineService.swift**

```swift
import Foundation
import Observation
import CRCLIEngine

@MainActor
@Observable
final class EngineService: EngineProviding {
    // — Observable State —
    var pipelineState: PipelineState = .idle
    var transcript: String = ""
    var isTranscriptFinal: Bool = false
    var lastResponse: String = ""
    var audioLevel: Float = 0.0
    var isReady: Bool = false
    var lifecycleState: AppLifecycleState = .loading
    var isSpeaking: Bool = false
    var activeModel: String = ""
    var activeTTSModel: String = ""
    var activeSTTModel: String = ""
    var activeEngine: String = ""
    var personality: String = "default"
    var enabledActionCount: Int = 0
    var interruptedResponse: String = ""

    // — Event Streams —
    let transcriptStream: AsyncStream<TranscriptEvent>
    let stateStream: AsyncStream<PipelineState>
    let toolTraceStream: AsyncStream<ToolTraceEvent>
    let responseStream: AsyncStream<String>

    // — Private: continuations (nonisolated(unsafe) for C trampoline access) —
    nonisolated(unsafe) private let transcriptContinuation: AsyncStream<TranscriptEvent>.Continuation
    nonisolated(unsafe) private let stateContinuation: AsyncStream<PipelineState>.Continuation
    nonisolated(unsafe) private let toolTraceContinuation: AsyncStream<ToolTraceEvent>.Continuation
    nonisolated(unsafe) private let responseContinuation: AsyncStream<String>.Continuation

    // — Private: engine —
    private var handle: RCLIHandle?
    private let engineQueue = DispatchQueue(label: "ai.rcli.engine")
    private let ttsQueue = DispatchQueue(label: "ai.rcli.tts")
    private var audioTimer: Timer?

    init() {
        // Create all streams
        var tc: AsyncStream<TranscriptEvent>.Continuation!
        transcriptStream = AsyncStream { tc = $0 }
        transcriptContinuation = tc

        var sc: AsyncStream<PipelineState>.Continuation!
        stateStream = AsyncStream { sc = $0 }
        stateContinuation = sc

        var ttc: AsyncStream<ToolTraceEvent>.Continuation!
        toolTraceStream = AsyncStream { ttc = $0 }
        toolTraceContinuation = ttc

        var rc: AsyncStream<String>.Continuation!
        responseStream = AsyncStream { rc = $0 }
        responseContinuation = rc

        // Start internal stream consumers that update @Observable properties
        startStreamConsumers()
    }

    private func startStreamConsumers() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            for await event in self.transcriptStream {
                self.transcript = event.text
                self.isTranscriptFinal = event.isFinal
            }
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            for await state in self.stateStream {
                self.pipelineState = state
                self.isSpeaking = (state == .speaking)
            }
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            for await response in self.responseStream {
                self.lastResponse = response
            }
        }
    }

    // MARK: - Lifecycle

    func initialize(modelsDir: String, gpuLayers: Int) async throws {
        lifecycleState = .loading
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            engineQueue.async { [weak self] in
                guard let self else {
                    cont.resume(throwing: RCLIError.engineNotReady)
                    return
                }
                let h = rcli_create(nil)
                guard let h else {
                    cont.resume(throwing: RCLIError.initFailed("rcli_create returned nil"))
                    return
                }
                let result = rcli_init(h, modelsDir, Int32(gpuLayers))
                if result != 0 {
                    rcli_destroy(h)
                    cont.resume(throwing: RCLIError.initFailed("rcli_init returned \(result)"))
                    return
                }
                // Register callbacks
                let ptr = Unmanaged.passUnretained(self).toOpaque()
                rcli_set_transcript_callback(h, Self.transcriptTrampoline, ptr)
                rcli_set_state_callback(h, Self.stateTrampoline, ptr)
                rcli_set_tool_trace_callback(h, Self.toolTraceTrampoline, ptr)
                rcli_set_response_callback(h, Self.responseTrampoline, ptr)

                Task { @MainActor in
                    self.handle = h
                    self.isReady = true
                    self.activeModel = String(cString: rcli_get_llm_model(h))
                    self.activeTTSModel = String(cString: rcli_get_tts_model(h))
                    self.activeSTTModel = String(cString: rcli_get_stt_model(h))
                    self.activeEngine = String(cString: rcli_get_active_engine(h))
                }
                cont.resume()
            }
        }
        lifecycleState = .ready
        startAudioMetering()
    }

    func initializeSTTOnly(modelsDir: String, gpuLayers: Int) async throws {
        lifecycleState = .loading
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            engineQueue.async { [weak self] in
                guard let self else {
                    cont.resume(throwing: RCLIError.engineNotReady)
                    return
                }
                let h = rcli_create(nil)
                guard let h else {
                    cont.resume(throwing: RCLIError.initFailed("rcli_create returned nil"))
                    return
                }
                let result = rcli_init_stt_only(h, modelsDir, Int32(gpuLayers))
                if result != 0 {
                    rcli_destroy(h)
                    cont.resume(throwing: RCLIError.initFailed("rcli_init_stt_only returned \(result)"))
                    return
                }
                let ptr = Unmanaged.passUnretained(self).toOpaque()
                rcli_set_transcript_callback(h, Self.transcriptTrampoline, ptr)
                rcli_set_state_callback(h, Self.stateTrampoline, ptr)

                Task { @MainActor in
                    self.handle = h
                    self.isReady = true
                }
                cont.resume()
            }
        }
        lifecycleState = .ready
    }

    func shutdown() {
        audioTimer?.invalidate()
        audioTimer = nil
        guard let h = handle else { return }
        handle = nil
        isReady = false
        engineQueue.async {
            rcli_deregister_all_callbacks(h)
            rcli_destroy(h)
        }
    }

    // MARK: - Audio Metering

    private func startAudioMetering() {
        audioTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard let h = self.handle else { return }
                self.audioLevel = rcli_get_audio_level(h)
            }
        }
    }

    // MARK: - Static Trampolines

    // All trampolines: copy const char* to String synchronously, yield into stream

    private static let transcriptTrampoline: RCLITranscriptCallback = {
        text, isFinal, userData in
        guard let userData, let text else { return }
        let service = Unmanaged<EngineService>.fromOpaque(userData).takeUnretainedValue()
        let str = String(cString: text)
        service.transcriptContinuation.yield(TranscriptEvent(text: str, isFinal: isFinal != 0))
    }

    private static let stateTrampoline: RCLIStateCallback = {
        _, newState, userData in
        guard let userData else { return }
        let service = Unmanaged<EngineService>.fromOpaque(userData).takeUnretainedValue()
        if let state = PipelineState(rawValue: Int(newState)) {
            service.stateContinuation.yield(state)
        }
    }

    private static let toolTraceTrampoline: RCLIToolTraceCallback = {
        event, toolName, data, success, userData in
        guard let userData else { return }
        let service = Unmanaged<EngineService>.fromOpaque(userData).takeUnretainedValue()
        let e = event.map { String(cString: $0) } ?? ""
        let t = toolName.map { String(cString: $0) } ?? ""
        let d = data.map { String(cString: $0) } ?? ""
        service.toolTraceContinuation.yield(ToolTraceEvent(
            event: e, toolName: t, data: d, success: success != 0))
    }

    private static let responseTrampoline: RCLIResponseCallback = {
        response, userData in
        guard let userData, let response else { return }
        let service = Unmanaged<EngineService>.fromOpaque(userData).takeUnretainedValue()
        let str = String(cString: response)
        service.responseContinuation.yield(str)
    }
}
```

- [ ] **Step 2: Build to verify**

Expected: Build succeeds. EngineService conforms to EngineProviding (partially — remaining methods added in next tasks).

- [ ] **Step 3: Commit**

```bash
git add app/RCLI/Services/EngineService.swift
git commit -m "feat(app): implement EngineService core — lifecycle, callbacks, AsyncStreams"
```

### Task 4: EngineService+Voice — listening, capture, transcribe

**Files:**
- Create: `app/RCLI/Services/EngineService+Voice.swift`

- [ ] **Step 1: Create voice extension**

```swift
import Foundation
import CRCLIEngine

extension EngineService {
    func startListening() {
        guard let h = handle else { return }
        engineQueue.async { rcli_start_listening(h) }
    }

    func stopListening() {
        guard let h = handle else { return }
        engineQueue.async { rcli_stop_listening(h) }
    }

    func startCapture() {
        guard let h = handle else { return }
        engineQueue.async { rcli_start_capture(h) }
    }

    func stopAndTranscribe() async throws -> String {
        guard let h = handle else { throw RCLIError.engineNotReady }
        return try await withCheckedThrowingContinuation { cont in
            engineQueue.async {
                let result = rcli_stop_capture_and_transcribe(h)
                guard let result else {
                    cont.resume(throwing: RCLIError.transcriptionFailed)
                    return
                }
                let str = String(cString: result)
                cont.resume(returning: str)
            }
        }
    }

    func stopProcessing() {
        guard let h = handle else { return }
        rcli_stop_processing(h) // documented as safe from any thread
    }

    func startVoiceMode(wakePhrase: String) async throws {
        guard let h = handle else { throw RCLIError.engineNotReady }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            engineQueue.async {
                let result = rcli_start_voice_mode(h, wakePhrase)
                if result != 0 {
                    cont.resume(throwing: RCLIError.initFailed("Voice mode start failed"))
                    return
                }
                cont.resume()
            }
        }
    }

    func stopVoiceMode() {
        guard let h = handle else { return }
        engineQueue.async { rcli_stop_voice_mode(h) }
    }
}
```

- [ ] **Step 2: Build and commit**

```bash
git add app/RCLI/Services/EngineService+Voice.swift
git commit -m "feat(app): add EngineService+Voice — listening, capture, transcribe, voice mode"
```

### Task 5: EngineService+Commands — processCommand, speak, processAndSpeak

**Files:**
- Create: `app/RCLI/Services/EngineService+Commands.swift`

- [ ] **Step 1: Create commands extension**

```swift
import Foundation
import CRCLIEngine

extension EngineService {
    func processCommand(_ text: String) async throws -> String {
        guard let h = handle else { throw RCLIError.engineNotReady }
        return try await withCheckedThrowingContinuation { cont in
            engineQueue.async {
                let result = rcli_process_command(h, text)
                guard let result else {
                    cont.resume(throwing: RCLIError.commandFailed("NULL response"))
                    return
                }
                let str = String(cString: result)
                cont.resume(returning: str)
            }
        }
    }

    func processAndSpeak(_ text: String) async throws -> String {
        guard let h = handle else { throw RCLIError.engineNotReady }
        return try await withCheckedThrowingContinuation { cont in
            engineQueue.async {
                let result = rcli_process_and_speak(h, text, nil, nil)
                guard let result else {
                    cont.resume(throwing: RCLIError.commandFailed("NULL response"))
                    return
                }
                let str = String(cString: result)
                cont.resume(returning: str)
            }
        }
    }

    func speak(_ text: String) async throws {
        guard let h = handle else { throw RCLIError.engineNotReady }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            // TTS on separate queue so it doesn't block engineQueue
            ttsQueue.async {
                let result = rcli_speak_streaming(h, text, nil, nil)
                if result != 0 {
                    cont.resume(throwing: RCLIError.speakFailed)
                    return
                }
                cont.resume()
            }
        }
    }

    func stopSpeaking() {
        guard let h = handle else { return }
        rcli_stop_speaking(h) // thread-safe
    }

    func clearHistory() {
        guard let h = handle else { return }
        engineQueue.async { rcli_clear_history(h) }
    }
}
```

- [ ] **Step 2: Build and commit**

```bash
git add app/RCLI/Services/EngineService+Commands.swift
git commit -m "feat(app): add EngineService+Commands — processCommand, speak, TTS on separate queue"
```

### Task 6: EngineService+Models — switch, list, info

**Files:**
- Create: `app/RCLI/Services/EngineService+Models.swift`

- [ ] **Step 1: Create models extension**

```swift
import Foundation
import CRCLIEngine

extension EngineService {
    func switchModel(_ id: String) async throws {
        guard let h = handle else { throw RCLIError.engineNotReady }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            engineQueue.async { [weak self] in
                let result = rcli_switch_llm(h, id)
                if result != 0 {
                    cont.resume(throwing: RCLIError.modelLoadFailed(id))
                    return
                }
                let name = String(cString: rcli_get_llm_model(h))
                let engine = String(cString: rcli_get_active_engine(h))
                Task { @MainActor in
                    self?.activeModel = name
                    self?.activeEngine = engine
                }
                cont.resume()
            }
        }
    }

    func listAvailableModels() async throws -> [ModelInfo] {
        guard let h = handle else { throw RCLIError.engineNotReady }
        return try await withCheckedThrowingContinuation { cont in
            engineQueue.async {
                guard let json = rcli_list_available_models(h) else {
                    cont.resume(returning: [])
                    return
                }
                let str = String(cString: json)
                free(json) // caller-owned

                // Parse JSON array
                guard let data = str.data(using: .utf8),
                      let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
                else {
                    cont.resume(returning: [])
                    return
                }

                let models = arr.compactMap { dict -> ModelInfo? in
                    guard let id = dict["id"] as? String,
                          let name = dict["name"] as? String,
                          let size = dict["size_bytes"] as? Int64,
                          let typeStr = dict["type"] as? String,
                          let type = ModelInfo.ModelType(rawValue: typeStr),
                          let downloaded = dict["is_downloaded"] as? Bool
                    else { return nil }
                    return ModelInfo(id: id, name: name, sizeBytes: size,
                                    type: type, isDownloaded: downloaded)
                }
                cont.resume(returning: models)
            }
        }
    }

    func setPersonality(_ key: String) throws {
        guard let h = handle else { throw RCLIError.engineNotReady }
        let result = rcli_set_personality(h, key)
        if result != 0 { throw RCLIError.commandFailed("Invalid personality: \(key)") }
        personality = key
    }

    func setBargeInEnabled(_ enabled: Bool) {
        guard let h = handle else { return }
        rcli_set_barge_in_enabled(h, enabled ? 1 : 0)
    }

    func isBargeInEnabled() -> Bool {
        guard let h = handle else { return false }
        return rcli_is_barge_in_enabled(h) != 0
    }

    func getInfo() async -> String {
        guard let h = handle else { return "{}" }
        return await withCheckedContinuation { cont in
            engineQueue.async {
                let result = rcli_get_info(h)
                let str = result.map { String(cString: $0) } ?? "{}"
                cont.resume(returning: str)
            }
        }
    }

    func getContextInfo() async -> (promptTokens: Int, contextSize: Int) {
        guard let h = handle else { return (0, 0) }
        return await withCheckedContinuation { cont in
            engineQueue.async {
                var tokens: Int32 = 0
                var ctx: Int32 = 0
                rcli_get_context_info(h, &tokens, &ctx)
                cont.resume(returning: (Int(tokens), Int(ctx)))
            }
        }
    }
}
```

- [ ] **Step 2: Build and commit**

```bash
git add app/RCLI/Services/EngineService+Models.swift
git commit -m "feat(app): add EngineService+Models — switch, list, personality, info"
```

### Task 7: EngineService+RAG and EngineService+Actions

**Files:**
- Create: `app/RCLI/Services/EngineService+RAG.swift`
- Create: `app/RCLI/Services/EngineService+Actions.swift`

- [ ] **Step 1: Create RAG extension**

```swift
import Foundation
import CRCLIEngine

extension EngineService {
    func ragIngest(directory: String) async throws {
        guard let h = handle else { throw RCLIError.engineNotReady }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            engineQueue.async {
                let result = rcli_rag_ingest(h, directory)
                if result != 0 {
                    cont.resume(throwing: RCLIError.ragIngestFailed(directory))
                    return
                }
                cont.resume()
            }
        }
    }

    func ragLoadIndex(path: String) async throws {
        guard let h = handle else { throw RCLIError.engineNotReady }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            engineQueue.async {
                let result = rcli_rag_load_index(h, path)
                if result != 0 {
                    cont.resume(throwing: RCLIError.ragIngestFailed("Failed to load index at \(path)"))
                    return
                }
                cont.resume()
            }
        }
    }

    func ragQuery(_ query: String) async throws -> String {
        guard let h = handle else { throw RCLIError.engineNotReady }
        return try await withCheckedThrowingContinuation { cont in
            engineQueue.async {
                guard let result = rcli_rag_query(h, query) else {
                    cont.resume(throwing: RCLIError.commandFailed("RAG query returned nil"))
                    return
                }
                cont.resume(returning: String(cString: result))
            }
        }
    }

    func ragClear() {
        guard let h = handle else { return }
        engineQueue.async { rcli_rag_clear(h) }
    }
}
```

- [ ] **Step 2: Create Actions extension**

```swift
import Foundation
import CRCLIEngine

extension EngineService {
    func listActions() async -> [ActionInfo] {
        guard let h = handle else { return [] }
        return await withCheckedContinuation { cont in
            engineQueue.async {
                guard let json = rcli_action_list(h) else {
                    cont.resume(returning: [])
                    return
                }
                let str = String(cString: json)
                guard let data = str.data(using: .utf8),
                      let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
                else {
                    cont.resume(returning: [])
                    return
                }
                let actions = arr.compactMap { dict -> ActionInfo? in
                    guard let name = dict["name"] as? String else { return nil }
                    return ActionInfo(
                        id: name,
                        name: name,
                        description: dict["description"] as? String ?? "",
                        category: dict["category"] as? String ?? "other",
                        isEnabled: dict["enabled"] as? Bool ?? true
                    )
                }
                cont.resume(returning: actions)
            }
        }
    }

    func setActionEnabled(_ name: String, enabled: Bool) {
        guard let h = handle else { return }
        rcli_set_action_enabled(h, name, enabled ? 1 : 0)
        enabledActionCount = Int(rcli_num_actions_enabled(h))
    }

    func isActionEnabled(_ name: String) -> Bool {
        guard let h = handle else { return false }
        return rcli_is_action_enabled(h, name) != 0
    }

    func saveActionPreferences() throws {
        guard let h = handle else { throw RCLIError.engineNotReady }
        let result = rcli_save_action_preferences(h)
        if result != 0 { throw RCLIError.commandFailed("Failed to save action preferences") }
    }

    func disableAllActions() {
        guard let h = handle else { return }
        rcli_disable_all_actions(h)
        enabledActionCount = 0
    }

    func resetActionsToDefaults() {
        guard let h = handle else { return }
        rcli_reset_actions_to_defaults(h)
        enabledActionCount = Int(rcli_num_actions_enabled(h))
    }
}
```

- [ ] **Step 3: Build and commit**

```bash
git add app/RCLI/Services/EngineService+RAG.swift app/RCLI/Services/EngineService+Actions.swift
git commit -m "feat(app): add EngineService+RAG and EngineService+Actions"
```

## Chunk 3: System Services

### Task 8: PermissionService

**Files:**
- Create: `app/RCLI/Services/PermissionService.swift`

- [ ] **Step 1: Create permission service**

```swift
import Foundation
import Observation
import ApplicationServices
import AVFoundation

@MainActor
@Observable
final class PermissionService {
    var microphoneGranted: Bool = false
    var accessibilityGranted: Bool = false

    private var pollTimer: Timer?
    private var fastPolling: Bool = false

    func startPolling() {
        checkAll()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkAll() }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Switch to fast polling (2s) when permission banner is visible
    func setFastPolling(_ fast: Bool) {
        guard fast != fastPolling else { return }
        fastPolling = fast
        stopPolling()
        let interval: TimeInterval = fast ? 2.0 : 30.0
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkAll() }
        }
    }

    func checkAll() {
        microphoneGranted = checkMicrophone()
        accessibilityGranted = checkAccessibility()
    }

    func requestMicrophone() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        microphoneGranted = granted
        return granted
    }

    func requestAccessibility() {
        // Open System Settings to Accessibility pane
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    func openMicrophoneSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Private

    private func checkMicrophone() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    private func checkAccessibility() -> Bool {
        AXIsProcessTrusted()
    }
}
```

- [ ] **Step 2: Build and commit**

```bash
git add app/RCLI/Services/PermissionService.swift
git commit -m "feat(app): add PermissionService — mic and Accessibility checks with polling"
```

### Task 9: HotkeyService

**Files:**
- Create: `src/bridge/rcli_hotkey_bridge.h`
- Create: `src/bridge/rcli_hotkey_bridge.mm`
- Modify: `CMakeLists.txt` (add bridge source)
- Create: `app/RCLI/Services/HotkeyService.swift`

The existing `hotkey_listener.mm` is well-tested and handles edge cases (re-enable on timeout, Enter-to-stop, event consumption). We bridge it via a C wrapper rather than reimplementing in Swift.

- [ ] **Step 1: Create hotkey C bridge header**

Create `src/bridge/rcli_hotkey_bridge.h`:

```c
#pragma once

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*RCLIHotkeyCallback)(void* user_data);

// Start listening for a global hotkey (e.g., "cmd+j").
// Returns 1 on success, 0 on failure (Accessibility not granted).
int rcli_hotkey_start(const char* hotkey_str, RCLIHotkeyCallback callback, void* user_data);

// Stop listening and release the event tap.
void rcli_hotkey_stop(void);

// Set whether the hotkey is "active" (recording in progress).
// When active, bare Enter also triggers the callback.
void rcli_hotkey_set_active(int active);

// Check if Accessibility permission is granted. Returns 1 if yes.
int rcli_hotkey_check_accessibility(void);

#ifdef __cplusplus
}
#endif
```

- [ ] **Step 2: Create hotkey C bridge implementation**

Create `src/bridge/rcli_hotkey_bridge.mm`:

```objc
#include "bridge/rcli_hotkey_bridge.h"
#include "dictate/hotkey_listener.h"
#include <string>

static RCLIHotkeyCallback g_bridge_callback = nullptr;
static void* g_bridge_user_data = nullptr;

extern "C" {

int rcli_hotkey_start(const char* hotkey_str, RCLIHotkeyCallback callback, void* user_data) {
    if (!hotkey_str || !callback) return 0;
    g_bridge_callback = callback;
    g_bridge_user_data = user_data;
    bool ok = rcli::hotkey_start(std::string(hotkey_str), []{
        if (g_bridge_callback) {
            g_bridge_callback(g_bridge_user_data);
        }
    });
    return ok ? 1 : 0;
}

void rcli_hotkey_stop(void) {
    rcli::hotkey_stop();
    g_bridge_callback = nullptr;
    g_bridge_user_data = nullptr;
}

void rcli_hotkey_set_active(int active) {
    rcli::hotkey_set_active(active != 0);
}

int rcli_hotkey_check_accessibility(void) {
    return rcli::hotkey_check_accessibility() ? 1 : 0;
}

} // extern "C"
```

- [ ] **Step 3: Add to CMake and build**

Add `src/bridge/rcli_hotkey_bridge.mm` to the rcli library sources in `CMakeLists.txt` and add the `set_source_files_properties` line.

Run: `cd build && cmake .. && cmake --build . -j$(sysctl -n hw.ncpu)`

- [ ] **Step 4: Create Swift HotkeyService**

Create `app/RCLI/Services/HotkeyService.swift`:

```swift
import Foundation
import Observation
import CRCLIEngine

@MainActor
@Observable
final class HotkeyService {
    var isListening: Bool = false
    var isRecording: Bool = false
    var hotkeyString: String = "cmd+j"

    var onHotkeyPressed: (() -> Void)?

    func start() -> Bool {
        let ptr = Unmanaged.passUnretained(self).toOpaque()
        let result = rcli_hotkey_start(hotkeyString, Self.hotkeyTrampoline, ptr)
        isListening = (result != 0)
        return isListening
    }

    func stop() {
        rcli_hotkey_stop()
        isListening = false
    }

    func setRecording(_ active: Bool) {
        isRecording = active
        rcli_hotkey_set_active(active ? 1 : 0)
    }

    static func checkAccessibility() -> Bool {
        rcli_hotkey_check_accessibility() != 0
    }

    // Static trampoline — dispatches to main thread
    private static let hotkeyTrampoline: RCLIHotkeyCallback = { userData in
        guard let userData else { return }
        let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
        // hotkey_listener.mm already dispatches to main queue, so we're on main
        Task { @MainActor in
            service.onHotkeyPressed?()
        }
    }
}
```

- [ ] **Step 5: Build and commit**

```bash
git add src/bridge/rcli_hotkey_bridge.h src/bridge/rcli_hotkey_bridge.mm CMakeLists.txt
git add app/RCLI/Services/HotkeyService.swift
git commit -m "feat(app): add HotkeyService — C bridge for global hotkey with CGEventTap"
```

### Task 10: OverlayService

**Files:**
- Create: `app/RCLI/Services/OverlayService.swift`

- [ ] **Step 1: Create overlay service**

Uses the C bridge wrappers from Plan 1 (Task 4).

```swift
import Foundation
import Observation
import CRCLIEngine

@MainActor
@Observable
final class OverlayService {
    private var initialized = false

    func initialize() {
        guard !initialized else { return }
        rcli_overlay_init()
        initialized = true
    }

    func show(state: OverlayState, caretX: Double? = nil, caretY: Double? = nil) {
        let stateInt: Int32 = (state == .recording) ? RCLI_OVERLAY_RECORDING : RCLI_OVERLAY_TRANSCRIBING
        if let x = caretX, let y = caretY {
            rcli_overlay_show(stateInt, x, y, 1)
        } else {
            rcli_overlay_show(stateInt, 0, 0, 0)
        }
    }

    func setState(_ state: OverlayState) {
        let stateInt: Int32 = (state == .recording) ? RCLI_OVERLAY_RECORDING : RCLI_OVERLAY_TRANSCRIBING
        rcli_overlay_set_state(stateInt)
    }

    func dismiss() {
        rcli_overlay_dismiss()
    }

    func cleanup() {
        rcli_overlay_cleanup()
        initialized = false
    }

    enum OverlayState {
        case recording
        case transcribing
    }
}
```

- [ ] **Step 2: Build and commit**

```bash
git add app/RCLI/Services/OverlayService.swift
git commit -m "feat(app): add OverlayService — bridges C overlay wrapper"
```

## Chunk 4: Dictation Flow Integration

### Task 11: Wire up dictation flow in MenuBarView

**Files:**
- Modify: `app/RCLI/Views/MenuBarView.swift`
- Modify: `app/RCLI/RCLIApp.swift`

This wires together all services for the primary user flow: ⌘J → overlay → speak → transcribe → paste.

- [ ] **Step 1: Update RCLIApp.swift to create and inject all services**

```swift
import SwiftUI

@main
struct RCLIApp: App {
    @State private var engine = EngineService()
    @State private var hotkey = HotkeyService()
    @State private var overlay = OverlayService()
    @State private var permissions = PermissionService()

    var body: some Scene {
        MenuBarExtra("RCLI", systemImage: menuBarIcon) {
            MenuBarView()
                .environment(engine)
                .environment(hotkey)
                .environment(overlay)
                .environment(permissions)
                .task { await startApp() }
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarIcon: String {
        switch engine.lifecycleState {
        case .loading: return "circle.dotted"
        case .ready:
            switch engine.pipelineState {
            case .listening: return "waveform"
            case .processing, .speaking: return "bolt.fill"
            default: return "waveform"
            }
        case .error: return "exclamationmark.triangle"
        }
    }

    private func startApp() async {
        // Initialize overlay
        overlay.initialize()

        // Start permission polling
        permissions.startPolling()

        // Initialize engine
        let modelsDir = NSString(string: "~/Library/RCLI/models").expandingTildeInPath
        do {
            try await engine.initialize(modelsDir: modelsDir, gpuLayers: 99)
        } catch {
            return // lifecycleState is already .error
        }

        // Start hotkey if accessibility granted
        if permissions.accessibilityGranted {
            setupHotkey()
        }
    }

    private func setupHotkey() {
        hotkey.onHotkeyPressed = { [engine, hotkey, overlay] in
            Task { @MainActor in
                if hotkey.isRecording {
                    // Stop recording
                    hotkey.setRecording(false)
                    overlay.setState(.transcribing)

                    do {
                        let text = try await engine.stopAndTranscribe()
                        if !text.isEmpty {
                            rcli_paste_text(text)
                        }
                    } catch {
                        // Transcription failed — just dismiss
                    }
                    overlay.dismiss()
                } else {
                    // Start recording
                    var caretX: Double = 0
                    var caretY: Double = 0
                    let hasCaret = rcli_get_caret_position(&caretX, &caretY)

                    if hasCaret == 0 {
                        overlay.show(state: .recording, caretX: caretX, caretY: caretY)
                    } else {
                        overlay.show(state: .recording)
                    }

                    engine.startCapture()
                    hotkey.setRecording(true)
                }
            }
        }
        _ = hotkey.start()
    }
}
```

- [ ] **Step 2: Update MenuBarView with status and controls**

```swift
import SwiftUI

struct MenuBarView: View {
    @Environment(EngineService.self) private var engine
    @Environment(HotkeyService.self) private var hotkey
    @Environment(PermissionService.self) private var permissions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.headline)
                Spacer()
                if case .ready = engine.lifecycleState {
                    Text(engine.activeModel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Permission warnings
            if !permissions.microphoneGranted {
                PermissionBanner(
                    message: "Microphone access needed",
                    action: { Task { await permissions.requestMicrophone() } }
                )
            }
            if !permissions.accessibilityGranted {
                PermissionBanner(
                    message: "Accessibility needed for hotkey",
                    action: { permissions.requestAccessibility() }
                )
            }

            if case .ready = engine.lifecycleState {
                Divider()

                // Quick actions
                HStack(spacing: 8) {
                    QuickActionCard(
                        icon: "mic.fill",
                        label: "Dictation",
                        shortcut: "⌘J",
                        enabled: permissions.microphoneGranted && permissions.accessibilityGranted
                    )
                    QuickActionCard(
                        icon: "text.bubble",
                        label: "Panel",
                        shortcut: "⌘⇧J",
                        enabled: true
                    )
                }
            }

            Divider()

            Button("Settings...") {
                // TODO: open settings (Plan 3)
            }
            .buttonStyle(.plain)

            Button("Quit RCLI") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .frame(width: 280)
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
        case .ready:
            switch engine.pipelineState {
            case .idle: return "Ready"
            case .listening: return "Listening..."
            case .processing: return "Processing..."
            case .speaking: return "Speaking..."
            case .interrupted: return "Interrupted"
            }
        case .error(let msg): return msg
        }
    }
}

// MARK: - Supporting Views

struct PermissionBanner: View {
    let message: String
    let action: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
            Spacer()
            Button("Grant") { action() }
                .font(.caption)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(8)
        .background(.orange.opacity(0.1))
        .cornerRadius(8)
    }
}

struct QuickActionCard: View {
    let icon: String
    let label: String
    let shortcut: String
    let enabled: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
            Text(label)
                .font(.caption)
            Text(shortcut)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.quaternary)
        .cornerRadius(8)
        .opacity(enabled ? 1.0 : 0.4)
    }
}
```

- [ ] **Step 3: Build the app**

Run: `xcodebuild -project app/RCLI.xcodeproj -scheme RCLI build`

Expected: Builds successfully.

- [ ] **Step 4: Test end-to-end dictation**

1. Build the xcframework: `bash scripts/build_xcframework.sh`
2. Build and run the app from Xcode
3. Grant Microphone and Accessibility permissions
4. Open any text field (Notes, TextEdit, etc.)
5. Press ⌘J — overlay should appear
6. Speak — then press ⌘J again or Enter
7. Transcribed text should paste into the text field

- [ ] **Step 5: Commit**

```bash
git add app/RCLI/RCLIApp.swift app/RCLI/Views/MenuBarView.swift
git commit -m "feat(app): wire up end-to-end dictation flow — hotkey → overlay → transcribe → paste"
```

---

## Verification Checklist

After completing all tasks:

- [ ] EngineProviding protocol compiles and EngineService fully conforms
- [ ] Engine initializes successfully from the app (menu bar shows "Ready")
- [ ] AsyncStream callbacks work (pipelineState updates in real-time)
- [ ] Audio metering updates at 30Hz
- [ ] ⌘J starts recording (overlay appears with mic icon)
- [ ] ⌘J again or Enter stops recording (overlay shows spinner, then dismisses)
- [ ] Transcribed text pastes into the frontmost app
- [ ] Permission banners appear when mic or accessibility is missing
- [ ] "Grant" buttons open the correct System Settings panes
- [ ] Quit button terminates the app cleanly (callbacks deregistered)

## What's Next

Plan 3 (UI & Distribution) builds on this:
- Full conversation PanelView
- Settings (5 tabs)
- Onboarding wizard
- ModelDownloadService
- Sparkle auto-updates
- Entitlements, signing, notarization
