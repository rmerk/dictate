import Foundation
import Observation
import CRCLIEngine

/// Sendable wrapper for RCLIHandle to safely cross actor isolation boundaries.
/// Safety: all C API calls through the handle are serialized on engineQueue.
struct SendableHandle: @unchecked Sendable {
    let raw: RCLIHandle
}

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

    // — Private: continuations (Sendable lets — accessible from C trampolines) —
    private let transcriptContinuation: AsyncStream<TranscriptEvent>.Continuation
    private let stateContinuation: AsyncStream<PipelineState>.Continuation
    private let toolTraceContinuation: AsyncStream<ToolTraceEvent>.Continuation
    private let responseContinuation: AsyncStream<String>.Continuation

    // — Engine (internal for extensions in separate files) —
    // Wrapped as SendableHandle to safely cross isolation boundaries into engineQueue.
    var handle: RCLIHandle?

    /// Return handle wrapped for Sendable closure capture, or throw if engine not ready.
    func requireHandle() throws -> SendableHandle {
        guard let h = handle else { throw RCLIError.engineNotReady }
        return SendableHandle(raw: h)
    }

    /// Return handle wrapped for Sendable closure capture, or nil if engine not ready.
    func optionalHandle() -> SendableHandle? {
        guard let h = handle else { return nil }
        return SendableHandle(raw: h)
    }
    let engineQueue = DispatchQueue(label: "ai.rcli.engine")
    let ttsQueue = DispatchQueue(label: "ai.rcli.tts")
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

    deinit {
        // Finish continuations so stream consumer Tasks exit their for-await loops.
        // audioTimer is handled by shutdown() — deinit cannot access @MainActor-isolated
        // stored properties directly on all Swift compiler versions.
        transcriptContinuation.finish()
        stateContinuation.finish()
        toolTraceContinuation.finish()
        responseContinuation.finish()
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
        let trampolines = (
            transcript: Self.transcriptTrampoline,
            state: Self.stateTrampoline,
            toolTrace: Self.toolTraceTrampoline,
            response: Self.responseTrampoline
        )
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
                rcli_set_transcript_callback(h, trampolines.transcript, ptr)
                rcli_set_state_callback(h, trampolines.state, ptr)
                rcli_set_tool_trace_callback(h, trampolines.toolTrace, ptr)
                rcli_set_response_callback(h, trampolines.response, ptr)

                let sh = SendableHandle(raw: h)
                let model = String(cString: rcli_get_llm_model(h))
                let tts = String(cString: rcli_get_tts_model(h))
                let stt = String(cString: rcli_get_stt_model(h))
                let engine = String(cString: rcli_get_active_engine(h))
                let pers = String(cString: rcli_get_personality(h))
                Task { @MainActor in
                    self.handle = sh.raw
                    self.isReady = true
                    self.activeModel = model
                    self.activeTTSModel = tts
                    self.activeSTTModel = stt
                    self.activeEngine = engine
                    self.personality = pers
                }
                cont.resume()
            }
        }
        lifecycleState = .ready
        startAudioMetering()
    }

    func initializeSTTOnly(modelsDir: String, gpuLayers: Int) async throws {
        lifecycleState = .loading
        let trampolines = (
            transcript: Self.transcriptTrampoline,
            state: Self.stateTrampoline
        )
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
                rcli_set_transcript_callback(h, trampolines.transcript, ptr)
                rcli_set_state_callback(h, trampolines.state, ptr)

                let sh = SendableHandle(raw: h)
                Task { @MainActor in
                    self.handle = sh.raw
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

        // Finish all continuations so stream consumer tasks exit their for-await loops
        transcriptContinuation.finish()
        stateContinuation.finish()
        toolTraceContinuation.finish()
        responseContinuation.finish()

        guard let h = handle else { return }
        let sh = SendableHandle(raw: h)

        // Deregister callbacks synchronously before niling handle to prevent
        // dangling Unmanaged pointer access if a C callback fires between the two.
        engineQueue.sync {
            rcli_deregister_all_callbacks(sh.raw)
        }

        handle = nil
        isReady = false
        lifecycleState = .loading

        // Destroy asynchronously — may take time to drain in-flight operations
        engineQueue.async {
            rcli_destroy(sh.raw)
        }
    }

    // MARK: - Audio Metering

    private func startAudioMetering() {
        audioTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            // Capture handle on MainActor, then dispatch the C API call to engineQueue
            // to match the thread-safety contract for all other C API calls.
            Task { @MainActor [weak self] in
                guard let self, let sh = self.optionalHandle() else { return }
                self.engineQueue.async { [weak self] in
                    let level = rcli_get_audio_level(sh.raw)
                    Task { @MainActor [weak self] in
                        self?.audioLevel = level
                    }
                }
            }
        }
    }

    // MARK: - Static Trampolines

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
