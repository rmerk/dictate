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
