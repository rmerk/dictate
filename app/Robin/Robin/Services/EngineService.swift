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

    // — Engine (internal for extensions in separate files) —
    var handle: RCLIHandle?
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
